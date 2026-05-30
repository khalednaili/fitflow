import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/invoice.dart';
import '../models/user_subscription.dart';

/// Settings stored in Firestore for invoice numbering.
class InvoiceSettings {
  const InvoiceSettings({
    this.prefix = 'INV',
    this.startNumber = 1,
    this.nextSequence = 1,
  });

  final String prefix;
  final int startNumber;

  /// The next sequence number that will be used when creating an invoice.
  final int nextSequence;

  factory InvoiceSettings.fromMap(Map<String, dynamic> map) => InvoiceSettings(
        prefix: (map['prefix'] ?? 'INV') as String,
        startNumber: (map['startNumber'] ?? 1) as int,
        nextSequence: (map['nextSequence'] ?? map['startNumber'] ?? 1) as int,
      );
}

class BillingService {
  BillingService({
    this.gymId = '',
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _firestore;

  /// Firestore doc used to store invoice settings + counter for this gym.
  String get _settingsDocId =>
      gymId.isNotEmpty ? 'invoiceSettings_$gymId' : 'invoiceSettings';

  DocumentReference<Map<String, dynamic>> get _settingsRef =>
      _firestore.collection('settings').doc(_settingsDocId);

  // ── Invoice CRUD ──────────────────────────────────────────────────────────

  Query<Map<String, dynamic>> get _invoicesQuery {
    Query<Map<String, dynamic>> q = _firestore.collection('invoices');
    if (gymId.isNotEmpty) {
      q = q.where('gymId', isEqualTo: gymId);
    }
    return q;
  }

  Stream<List<Invoice>> streamInvoices() {
    return _invoicesQuery
        .orderBy('issuedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Invoice.fromSnapshot(d)).toList());
  }

  /// Streams invoices for a specific member, sorted by date descending.
  /// Filters by userId only to avoid requiring a composite Firestore index.
  Stream<List<Invoice>> streamInvoicesForUser(String userId) {
    return _firestore
        .collection('invoices')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => Invoice.fromSnapshot(d)).toList()
        ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
      return list;
    });
  }

  Future<Invoice?> getInvoice(String invoiceId) async {
    final doc =
        await _firestore.collection('invoices').doc(invoiceId).get();
    if (!doc.exists) return null;
    return Invoice.fromSnapshot(doc);
  }

  // ── Invoice settings ─────────────────────────────────────────────────────

  /// Returns the current invoice numbering settings for this gym.
  Future<InvoiceSettings> getInvoiceSettings() async {
    final snap = await _settingsRef.get();
    if (!snap.exists) return const InvoiceSettings();
    return InvoiceSettings.fromMap(snap.data()!);
  }

  /// Persists invoice settings.
  ///
  /// If [resetCounter] is true (or [startNumber] has changed), the running
  /// sequence is reset to [startNumber]; otherwise the counter continues from
  /// wherever it currently is.
  Future<void> saveInvoiceSettings({
    required String prefix,
    required int startNumber,
    bool resetCounter = false,
  }) async {
    final current = await getInvoiceSettings();
    final nextSeq =
        resetCounter || startNumber != current.startNumber
            ? startNumber
            : current.nextSequence;

    await _settingsRef.set(
      <String, dynamic>{
        'prefix': prefix.trim(),
        'startNumber': startNumber,
        'nextSequence': nextSeq,
        if (gymId.isNotEmpty) 'gymId': gymId,
      },
    );
  }

  // ── Create invoice ────────────────────────────────────────────────────────

  /// Creates an invoice document.
  ///
  /// The invoice number is assigned atomically via a Firestore transaction,
  /// using the sequential counter stored in the gym's invoice settings doc.
  /// Format: `{prefix}-{YYYY}-{sequence:04d}` e.g. `INV-2025-0001`.
  Future<Invoice> createInvoice({
    required String userId,
    required String memberName,
    required String memberEmail,
    String memberPhone = '',
    required UserSubscription subscription,
    required String planName,
    String notes = '',
    DateTime? dueDate,
  }) async {
    final now = DateTime.now();

    final payments = subscription.paymentHistory
        .map((p) => InvoicePayment(
              amount: p.amount,
              date: p.date,
              method: p.method,
              notes: p.notes,
            ))
        .toList();

    final status = subscription.amountPaid >= subscription.totalAmount
        ? 'paid'
        : subscription.amountPaid > 0
            ? 'partial'
            : 'unpaid';

    final items = [
      InvoiceItem(
        description: planName,
        amount: subscription.totalAmount,
        currency: subscription.currency,
      ),
    ];

    // Pre-allocate a document reference so we can set it inside the transaction.
    final invoiceRef = _firestore.collection('invoices').doc();
    String invoiceNumber = '';

    await _firestore.runTransaction((tx) async {
      final settingsSnap = await tx.get(_settingsRef);
      final sData = settingsSnap.data() ?? {};
      final rawPrefix = (sData['prefix'] as String? ?? 'INV').trim();
      final effectivePrefix = rawPrefix.isEmpty ? 'INV' : rawPrefix;
      final startNumber = (sData['startNumber'] as int? ?? 1);
      final nextSeq = settingsSnap.exists
          ? (sData['nextSequence'] as int? ?? startNumber)
          : startNumber;

      invoiceNumber =
          '$effectivePrefix-${now.year}-${nextSeq.toString().padLeft(4, '0')}';

      // Increment the counter atomically.
      tx.set(
        _settingsRef,
        <String, dynamic>{
          'prefix': rawPrefix,
          'startNumber': startNumber,
          'nextSequence': nextSeq + 1,
          if (gymId.isNotEmpty) 'gymId': gymId,
        },
      );

      tx.set(invoiceRef, <String, dynamic>{
        'invoiceNumber': invoiceNumber,
        'gymId': gymId,
        'userId': userId,
        'memberName': memberName,
        'memberEmail': memberEmail,
        'memberPhone': memberPhone,
        'subscriptionId': subscription.id,
        'planName': planName,
        'currency': subscription.currency,
        'totalAmount': subscription.totalAmount,
        'amountPaid': subscription.amountPaid,
        'status': status,
        'issuedAt': Timestamp.fromDate(now),
        if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate),
        'notes': notes,
        'items': items.map((i) => i.toMap()).toList(),
        'payments': payments.map((p) => p.toMap()).toList(),
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });

    return Invoice(
      id: invoiceRef.id,
      invoiceNumber: invoiceNumber,
      gymId: gymId,
      userId: userId,
      memberName: memberName,
      memberEmail: memberEmail,
      memberPhone: memberPhone,
      subscriptionId: subscription.id,
      planName: planName,
      currency: subscription.currency,
      totalAmount: subscription.totalAmount,
      amountPaid: subscription.amountPaid,
      status: status,
      issuedAt: now,
      dueDate: dueDate,
      notes: notes,
      items: items,
      payments: payments,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> deleteInvoice(String invoiceId) async {
    await _firestore.collection('invoices').doc(invoiceId).delete();
  }

  // ── Revenue analytics ─────────────────────────────────────────────────────

  /// Computes revenue stats by scanning all gym subscriptions client-side.
  Future<RevenueStats> computeRevenueStats() async {
    Query<Map<String, dynamic>> q =
        _firestore.collection('user_subscriptions');
    if (gymId.isNotEmpty) {
      q = q.where('gymId', isEqualTo: gymId);
    }

    final snap = await q.get();
    final subs = snap.docs
        .map((d) => UserSubscription.fromSnapshot(d))
        .toList();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = thisMonthStart;

    int revenueToday = 0;
    int revenueThisMonth = 0;
    int revenueLastMonth = 0;
    int newPaymentsThisMonth = 0;
    int totalOutstanding = 0;
    final monthlyTrend = <String, int>{};
    final revenueByMethod = <String, int>{};

    // Build the 6-month key list
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      monthlyTrend[key] = 0;
    }

    String currency = '';

    for (final sub in subs) {
      if (currency.isEmpty && sub.currency.isNotEmpty) {
        currency = sub.currency;
      }

      // Outstanding balance
      if (sub.status != 'cancelled') {
        totalOutstanding += sub.remainingAmount.clamp(0, sub.totalAmount);
      }

      // Payment history aggregation
      for (final payment in sub.paymentHistory) {
        final pd = payment.date;

        if (!pd.isBefore(todayStart)) {
          revenueToday += payment.amount;
        }

        if (!pd.isBefore(thisMonthStart)) {
          revenueThisMonth += payment.amount;
          newPaymentsThisMonth++;
        }

        if (!pd.isBefore(lastMonthStart) && pd.isBefore(lastMonthEnd)) {
          revenueLastMonth += payment.amount;
        }

        // Monthly trend (last 6 months)
        final key = '${pd.year}-${pd.month.toString().padLeft(2, '0')}';
        if (monthlyTrend.containsKey(key)) {
          monthlyTrend[key] = monthlyTrend[key]! + payment.amount;
        }

        // By payment method
        final method = payment.method.isEmpty ? 'other' : payment.method;
        revenueByMethod[method] = (revenueByMethod[method] ?? 0) + payment.amount;
      }
    }

    return RevenueStats(
      revenueToday: revenueToday,
      revenueThisMonth: revenueThisMonth,
      revenueLastMonth: revenueLastMonth,
      totalOutstanding: totalOutstanding,
      newPaymentsThisMonth: newPaymentsThisMonth,
      monthlyTrend: monthlyTrend,
      revenueByMethod: revenueByMethod,
      currency: currency,
    );
  }
}
