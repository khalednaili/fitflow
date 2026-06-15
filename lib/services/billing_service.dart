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

  /// Streams a single invoice document in real-time.
  Stream<Invoice?> streamInvoice(String invoiceId) {
    return _firestore
        .collection('invoices')
        .doc(invoiceId)
        .snapshots()
        .map((snap) => snap.exists ? Invoice.fromSnapshot(snap) : null);
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

  /// Returns what the next auto-generated invoice number would be, WITHOUT
  /// consuming or incrementing the counter.  Use this to pre-fill the invoice
  /// number field in the UI so the admin can optionally override it.
  Future<String> previewNextInvoiceNumber() async {
    final snap = await _settingsRef.get();
    final sData = snap.data() ?? {};
    final rawPrefix = (sData['prefix'] as String? ?? 'INV').trim();
    final effectivePrefix = rawPrefix.isEmpty ? 'INV' : rawPrefix;
    final startNumber = (sData['startNumber'] as int? ?? 1);
    final nextSeq =
        snap.exists ? (sData['nextSequence'] as int? ?? startNumber) : startNumber;
    final year = DateTime.now().year;
    return '$effectivePrefix-$year-${nextSeq.toString().padLeft(4, '0')}';
  }

  /// Creates an invoice document.
  ///
  /// [subscriptions] must contain at least one entry; all must share the same
  /// currency (enforced by the caller before reaching this point).
  /// [planLabels] must have the same length as [subscriptions]; each entry is
  /// the human-readable plan name for the corresponding subscription.
  ///
  /// When [customInvoiceNumber] is provided (non-empty), it is used directly
  /// and the sequential counter is NOT incremented.  Otherwise a number is
  /// auto-generated atomically via a Firestore transaction.
  ///
  /// Format (auto): `{prefix}-{YYYY}-{sequence:04d}` e.g. `INV-2025-0001`.
  Future<Invoice> createInvoice({
    required String userId,
    required String memberName,
    required String memberEmail,
    String memberPhone = '',
    required List<UserSubscription> subscriptions,
    required List<String> planLabels,
    String notes = '',
    DateTime? dueDate,
    List<InvoiceItem> extraItems = const [],
    String? customInvoiceNumber,
  }) async {
    assert(subscriptions.isNotEmpty, 'At least one subscription required');
    assert(planLabels.length == subscriptions.length, 'planLabels length must match subscriptions');

    final now = DateTime.now();

    // Invoice always starts fresh — payments are recorded separately.
    const status = 'unpaid';

    final currency = subscriptions.first.currency;

    // One base item per subscription.
    final baseItems = List<InvoiceItem>.generate(
      subscriptions.length,
      (i) => InvoiceItem(
        description: planLabels[i],
        amount: subscriptions[i].totalAmount,
        currency: subscriptions[i].currency,
      ),
    );
    final items = [...baseItems, ...extraItems];
    final totalAmount = items.fold<int>(0, (acc, item) => acc + item.amount);

    // Legacy fields — keep first subscription for backward compatibility.
    final subscriptionId = subscriptions.first.id;
    final planName = planLabels.length == 1
        ? planLabels.first
        : '${planLabels.first} + ${planLabels.length - 1} more';

    // Pre-allocate a document reference so we can set it inside the transaction.
    final invoiceRef = _firestore.collection('invoices').doc();
    String invoiceNumber = '';

    final useCustom =
        customInvoiceNumber != null && customInvoiceNumber.trim().isNotEmpty;

    await _firestore.runTransaction((tx) async {
      if (useCustom) {
        // Custom invoice number — use it directly, skip counter.
        invoiceNumber = customInvoiceNumber.trim();
      } else {
        // Auto-generate and atomically increment the counter.
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

        tx.set(
          _settingsRef,
          <String, dynamic>{
            'prefix': rawPrefix,
            'startNumber': startNumber,
            'nextSequence': nextSeq + 1,
            if (gymId.isNotEmpty) 'gymId': gymId,
          },
        );
      }

      tx.set(invoiceRef, <String, dynamic>{
        'invoiceNumber': invoiceNumber,
        'gymId': gymId,
        'userId': userId,
        'memberName': memberName,
        'memberEmail': memberEmail,
        'memberPhone': memberPhone,
        'subscriptionId': subscriptionId,
        'planName': planName,
        'currency': currency,
        'totalAmount': totalAmount,
        'amountPaid': 0,
        'status': status,
        'issuedAt': Timestamp.fromDate(now),
        if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate),
        'notes': notes,
        'items': items.map((i) => i.toMap()).toList(),
        'payments': const <dynamic>[],
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
      subscriptionId: subscriptionId,
      planName: planName,
      currency: currency,
      totalAmount: totalAmount,
      amountPaid: 0,
      status: status,
      issuedAt: now,
      dueDate: dueDate,
      notes: notes,
      items: items,
      payments: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Replaces all line-items on an invoice and recalculates [totalAmount] and
  /// [status] atomically.  Existing [amountPaid] and [payments] are preserved.
  Future<Invoice> updateInvoiceItems({
    required String invoiceId,
    required List<InvoiceItem> items,
    String? notes,
  }) async {
    final invoiceRef = _firestore.collection('invoices').doc(invoiceId);
    final now = DateTime.now();
    late Invoice updated;

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(invoiceRef);
      if (!snap.exists) throw Exception('Invoice $invoiceId not found');

      final current = Invoice.fromSnapshot(snap);
      final newTotal = items.fold<int>(0, (acc, item) => acc + item.amount);
      final amountPaid = current.amountPaid;
      final newStatus = amountPaid >= newTotal
          ? 'paid'
          : amountPaid > 0
              ? 'partial'
              : 'unpaid';
      final updatedNotes = notes ?? current.notes;

      tx.update(invoiceRef, <String, dynamic>{
        'items': items.map((i) => i.toMap()).toList(),
        'totalAmount': newTotal,
        'status': newStatus,
        'notes': updatedNotes,
        'updatedAt': Timestamp.fromDate(now),
      });

      updated = Invoice(
        id: current.id,
        invoiceNumber: current.invoiceNumber,
        gymId: current.gymId,
        userId: current.userId,
        memberName: current.memberName,
        memberEmail: current.memberEmail,
        memberPhone: current.memberPhone,
        subscriptionId: current.subscriptionId,
        planName: current.planName,
        currency: current.currency,
        totalAmount: newTotal,
        amountPaid: amountPaid,
        status: newStatus,
        issuedAt: current.issuedAt,
        dueDate: current.dueDate,
        notes: updatedNotes,
        items: items,
        payments: current.payments,
        createdAt: current.createdAt,
        updatedAt: now,
      );
    });

    return updated;
  }

  Future<void> updateInvoiceNumber(
      String invoiceId, String newNumber) async {
    await _firestore.collection('invoices').doc(invoiceId).update(<String, dynamic>{
      'invoiceNumber': newNumber.trim(),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
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
