import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/gym.dart';
import '../models/gym_usage.dart';
import '../models/invoice.dart';
import '../utils/platform_pricing.dart';

/// Handles the platform's own billing of *gyms* (as opposed to
/// `BillingService`, which handles a gym billing its members). Reads the
/// usage counters
/// maintained by Cloud Functions triggers (see `functions/index.js`) and lets
/// the super admin turn them into a real [Invoice] — stored separately in
/// `platformInvoices` so it never mixes with a gym's own member invoices.
class PlatformBillingService {
  PlatformBillingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _gymUsage =>
      _firestore.collection('gymUsage');

  CollectionReference<Map<String, dynamic>> get _platformInvoices =>
      _firestore.collection('platformInvoices');

  DocumentReference<Map<String, dynamic>> get _counterRef =>
      _firestore.collection('settings').doc('platformInvoiceSettings');

  // ── Usage ────────────────────────────────────────────────────────────────

  /// Streams live usage for a single gym. Never errors on a missing
  /// document — a gym with no usage yet just reads as all-zero.
  Stream<GymUsage> watchUsage(String gymId) {
    return _gymUsage.doc(gymId).snapshots().map(
          (snap) => snap.exists ? GymUsage.fromSnapshot(snap) : GymUsage.empty(gymId),
        );
  }

  /// Streams usage for every gym that has a `gymUsage` document, keyed by
  /// gymId, for the super admin overview screen.
  Stream<Map<String, GymUsage>> watchAllUsage() {
    return _gymUsage.snapshots().map(
          (snap) => {
            for (final doc in snap.docs) doc.id: GymUsage.fromSnapshot(doc),
          },
        );
  }

  Future<GymUsage> getUsage(String gymId) async {
    final snap = await _gymUsage.doc(gymId).get();
    return snap.exists ? GymUsage.fromSnapshot(snap) : GymUsage.empty(gymId);
  }

  /// Estimated charge for [gymId] under the current billing period (i.e.
  /// since its last invoice), using [PlatformPricing].
  Future<PlatformCharge> previewCharge(String gymId) async {
    return PlatformPricing.compute(await getUsage(gymId));
  }

  // ── Platform invoices (billed to a gym) ─────────────────────────────────

  Stream<List<Invoice>> streamInvoicesForGym(String gymId) {
    return _platformInvoices
        .where('gymId', isEqualTo: gymId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Invoice.fromSnapshot).toList()
        ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
      return list;
    });
  }

  Stream<List<Invoice>> streamAllInvoices() {
    return _platformInvoices.snapshots().map((snap) {
      final list = snap.docs.map(Invoice.fromSnapshot).toList()
        ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
      return list;
    });
  }

  /// Generates and stores a platform invoice billing [gym] for its usage
  /// since the last invoice (or since tracking began, for the first one),
  /// using [PlatformPricing] to compute the amount. On success, snapshots
  /// the gym's current write/delete counters onto its `gymUsage` doc so the
  /// *next* invoice only bills the delta.
  Future<Invoice> generateInvoiceForGym(
    Gym gym, {
    String notes = '',
    Duration dueIn = const Duration(days: 14),
    String sellerName = 'FitFlow',
    String sellerAddress = '',
    String sellerTaxId = '',
    String language = 'en',
  }) async {
    final now = DateTime.now();
    final periodLabel = DateFormat('MMMM yyyy').format(now);

    final invoiceRef = _platformInvoices.doc();
    final usageRef = _gymUsage.doc(gym.id);
    String invoiceNumber = '';

    await _firestore.runTransaction((tx) async {
      // Read the usage doc *inside* the transaction (not from a pre-fetched
      // snapshot) so a concurrent usage-tracking write between the initial
      // call and this transaction's commit can't cause it to bill and
      // snapshot stale counters.
      final usageSnap = await tx.get(usageRef);
      final usage = usageSnap.exists
          ? GymUsage.fromSnapshot(usageSnap)
          : GymUsage.empty(gym.id);
      final charge = PlatformPricing.compute(usage);

      final counterSnap = await tx.get(_counterRef);
      final cData = counterSnap.data() ?? {};
      final nextSeq = (cData['nextSequence'] as num? ?? 1).toInt();
      invoiceNumber = 'PLAT-${nextSeq.toString().padLeft(4, '0')}';

      tx.set(_counterRef, {'nextSequence': nextSeq + 1}, SetOptions(merge: true));

      tx.set(invoiceRef, <String, dynamic>{
        'invoiceNumber': invoiceNumber,
        'gymId': gym.id,
        'userId': gym.adminUid,
        'memberName': gym.name,
        'memberEmail': gym.adminEmail,
        'memberPhone': '',
        'memberAddress': gym.address,
        'memberTaxId': '',
        'subscriptionId': '',
        'planName': 'FitFlow Platform Usage — $periodLabel',
        'currency': charge.currency,
        'totalAmount': charge.total,
        'amountPaid': 0,
        'taxAmount': 0,
        'discountAmount': 0,
        'stampDuty': 0,
        'sellerName': sellerName,
        'sellerAddress': sellerAddress,
        'sellerTaxId': sellerTaxId,
        'language': language,
        'status': InvoiceStatus.unpaid,
        'issuedAt': Timestamp.fromDate(now),
        'dueDate': Timestamp.fromDate(now.add(dueIn)),
        'notes': notes,
        'items': charge.lines
            .map((l) => InvoiceItem(
                  description: l.description,
                  amount: l.amount,
                  currency: charge.currency,
                ).toMap())
            .toList(),
        'payments': <Map<String, dynamic>>[],
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'isCreditNote': false,
      });

      // Snapshot the counters this invoice was billed against so the next
      // invoice only charges for usage accrued after this point.
      tx.set(
        usageRef,
        {
          'lastInvoicedWrites': usage.writes,
          'lastInvoicedDeletes': usage.deletes,
          'lastInvoicedAt': Timestamp.fromDate(now),
        },
        SetOptions(merge: true),
      );
    });

    final saved = await invoiceRef.get();
    return Invoice.fromSnapshot(saved);
  }

  Future<void> markInvoicePaid(String invoiceId) async {
    final ref = _platformInvoices.doc(invoiceId);
    final snap = await ref.get();
    final total = (snap.data()?['totalAmount'] as num?) ?? 0;
    await ref.update({
      'status': InvoiceStatus.paid,
      'amountPaid': total,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }
}
