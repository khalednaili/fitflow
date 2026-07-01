import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/invoice.dart';
import '../models/user_subscription.dart';
import '../utils/currency.dart';

/// Settings stored in Firestore for invoice numbering and Tunisian fiscal
/// identity (seller company info, matricule fiscal, stamp duty, default TVA).
class InvoiceSettings {
  const InvoiceSettings({
    this.prefix = 'INV-',
    this.startNumber = 1,
    this.nextSequence = 1,
    this.padding = 4,
    this.companyName = '',
    this.companyAddress = '',
    this.matriculeFiscal = '',
    this.stampDuty = 0,
    this.defaultVatRate = 19,
    this.creditNotePrefix = 'CN-',
    this.creditNoteNextSequence = 1,
  });

  /// Suggested Tunisian fiscal stamp (droit de timbre) offered as a default in
  /// the settings UI. Not applied automatically — the stamp is only charged
  /// once an admin saves a non-zero [stampDuty].
  static const num suggestedStampDutyTND = 1.0;

  final String prefix;
  final int startNumber;

  /// The next sequence number that will be used when creating an invoice.
  final int nextSequence;

  /// How many digits to pad the sequence number to (e.g. 4 → 0001).
  final int padding;

  // ── Tunisian fiscal identity ───────────────────────────────────────────────

  /// Seller company / gym legal name shown on the invoice.
  final String companyName;

  /// Seller postal address shown on the invoice.
  final String companyAddress;

  /// Tunisian tax identification number (matricule fiscal).
  final String matriculeFiscal;

  /// Fixed fiscal stamp (droit de timbre) applied per invoice. As of recent
  /// years this is 1.000 TND.
  final num stampDuty;

  /// Default TVA rate (%) pre-filled for new line items (19 % standard rate).
  final int defaultVatRate;

  /// Prefix for credit-note numbers — kept as its own legally-required series
  /// (e.g. `CN-000001`), independent of the invoice counter.
  final String creditNotePrefix;

  /// Next sequence number for credit notes (separate from [nextSequence]).
  final int creditNoteNextSequence;

  factory InvoiceSettings.fromMap(Map<String, dynamic> map) => InvoiceSettings(
        prefix: (map['prefix'] ?? 'INV-') as String,
        startNumber: (map['startNumber'] ?? 1) as int,
        nextSequence: (map['nextSequence'] ?? map['startNumber'] ?? 1) as int,
        padding: (map['padding'] ?? 4) as int,
        companyName: (map['companyName'] ?? '') as String,
        companyAddress: (map['companyAddress'] ?? '') as String,
        matriculeFiscal: (map['matriculeFiscal'] ?? '') as String,
        stampDuty: (map['stampDuty'] as num? ?? 0),
        defaultVatRate: (map['defaultVatRate'] as num? ?? 19).toInt(),
        creditNotePrefix: (map['creditNotePrefix'] ?? 'CN-') as String,
        creditNoteNextSequence:
            (map['creditNoteNextSequence'] as num? ?? 1).toInt(),
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
    int padding = 4,
    bool resetCounter = false,
    String? companyName,
    String? companyAddress,
    String? matriculeFiscal,
    num? stampDuty,
    int? defaultVatRate,
  }) async {
    final current = await getInvoiceSettings();
    final nextSeq =
        resetCounter || startNumber != current.startNumber
            ? startNumber
            : current.nextSequence;

    await _settingsRef.set(
      <String, dynamic>{
        'prefix': prefix,
        'startNumber': startNumber,
        'nextSequence': nextSeq,
        'padding': padding,
        if (companyName != null) 'companyName': companyName,
        if (companyAddress != null) 'companyAddress': companyAddress,
        if (matriculeFiscal != null) 'matriculeFiscal': matriculeFiscal,
        if (stampDuty != null) 'stampDuty': stampDuty,
        if (defaultVatRate != null) 'defaultVatRate': defaultVatRate,
        if (gymId.isNotEmpty) 'gymId': gymId,
      },
      SetOptions(merge: true),
    );
  }

  // ── Create invoice ────────────────────────────────────────────────────────

  /// Returns what the next auto-generated invoice number would be, WITHOUT
  /// consuming or incrementing the counter.  Use this to pre-fill the invoice
  /// number field in the UI so the admin can optionally override it.
  Future<String> previewNextInvoiceNumber() async {
    final snap = await _settingsRef.get();
    final sData = snap.data() ?? {};
    final prefix = ((sData['prefix'] as String?) ?? 'INV-');
    final effectivePrefix = prefix.isEmpty ? 'INV-' : prefix;
    final startNumber = (sData['startNumber'] as int? ?? 1);
    final nextSeq =
        snap.exists ? (sData['nextSequence'] as int? ?? startNumber) : startNumber;
    final padding = (sData['padding'] as int? ?? 4);
    return '$effectivePrefix${nextSeq.toString().padLeft(padding, '0')}';
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
    String memberAddress = '',
    required List<UserSubscription> subscriptions,
    required List<String> planLabels,
    String notes = '',
    DateTime? dueDate,
    List<InvoiceItem> extraItems = const [],
    String? customInvoiceNumber,
    num discountAmount = 0,
    num? stampDuty,
    String status = InvoiceStatus.unpaid,
  }) async {
    assert(subscriptions.isNotEmpty, 'At least one subscription required');
    assert(planLabels.length == subscriptions.length, 'planLabels length must match subscriptions');

    final now = DateTime.now();
    final effectiveStatus = InvoiceStatus.validated(status);
    final currency = subscriptions.first.currency;

    // Seller identity + stamp default come from gym settings; snapshotted onto
    // the invoice so it stays accurate if settings change later.
    final settings = await getInvoiceSettings();
    final effectiveStamp =
        Currency.roundMillimes(stampDuty ?? settings.stampDuty);

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
    final subtotalAmount =
        items.fold<num>(0, (acc, item) => acc + item.amount + item.taxAmount);
    final effectiveDiscount = discountAmount.clamp(0, subtotalAmount);
    final totalAmount = Currency.roundMillimes(
        (subtotalAmount - effectiveDiscount + effectiveStamp)
            .clamp(0, 999999999));

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
        final rawPrefix = ((sData['prefix'] as String?) ?? 'INV-');
        final effectivePrefix = rawPrefix.isEmpty ? 'INV-' : rawPrefix;
        final startNumber = (sData['startNumber'] as int? ?? 1);
        final nextSeq = settingsSnap.exists
            ? (sData['nextSequence'] as int? ?? startNumber)
            : startNumber;
        final padding = (sData['padding'] as int? ?? 4);

        invoiceNumber =
            '$effectivePrefix${nextSeq.toString().padLeft(padding, '0')}';

        final counterUpdate = <String, dynamic>{
          'prefix': rawPrefix,
          'startNumber': startNumber,
          'nextSequence': nextSeq + 1,
          'padding': padding,
          if (gymId.isNotEmpty) 'gymId': gymId,
        };
        // Update (not set) when the doc exists so fiscal fields — companyName,
        // matriculeFiscal, stampDuty, etc. — are preserved; set only creates it.
        if (settingsSnap.exists) {
          tx.update(_settingsRef, counterUpdate);
        } else {
          tx.set(_settingsRef, counterUpdate);
        }
      }

      tx.set(invoiceRef, <String, dynamic>{
        'invoiceNumber': invoiceNumber,
        'gymId': gymId,
        'userId': userId,
        'memberName': memberName,
        'memberEmail': memberEmail,
        'memberPhone': memberPhone,
        'memberAddress': memberAddress,
        'subscriptionId': subscriptionId,
        'planName': planName,
        'currency': currency,
        'totalAmount': totalAmount,
        'amountPaid': 0,
        'taxAmount': items.fold<num>(0, (s, i) => s + i.taxAmount),
        'discountAmount': effectiveDiscount,
        'stampDuty': effectiveStamp,
        'sellerName': settings.companyName,
        'sellerAddress': settings.companyAddress,
        'sellerTaxId': settings.matriculeFiscal,
        'status': effectiveStatus,
        'issuedAt': Timestamp.fromDate(now),
        if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate),
        'notes': notes,
        'items': items.map((i) => i.toMap()).toList(),
        'payments': const <dynamic>[],
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'isCreditNote': false,
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
      memberAddress: memberAddress,
      subscriptionId: subscriptionId,
      planName: planName,
      currency: currency,
      totalAmount: totalAmount,
      amountPaid: 0,
      taxAmount: items.fold<num>(0, (s, i) => s + i.taxAmount),
      discountAmount: effectiveDiscount,
      stampDuty: effectiveStamp,
      sellerName: settings.companyName,
      sellerAddress: settings.companyAddress,
      sellerTaxId: settings.matriculeFiscal,
      status: effectiveStatus,
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
      // Recompute totals tax-inclusively and preserve the existing flat
      // discount (clamped to the new subtotal), mirroring createInvoice so the
      // stored values keep the invariant
      // totalAmount == subtotal + taxAmount - discountAmount.
      final newSubtotal = items.fold<num>(0, (acc, item) => acc + item.amount);
      final newTax = items.fold<num>(0, (acc, item) => acc + item.taxAmount);
      final newDiscount =
          current.discountAmount.clamp(0, newSubtotal + newTax);
      // Preserve the invoice's existing fiscal stamp in the recomputed total.
      final newTotal = Currency.roundMillimes(
          (newSubtotal + newTax - newDiscount + current.stampDuty)
              .clamp(0, 999999999));
      final amountPaid = current.amountPaid;
      final newStatus = amountPaid >= newTotal
          ? InvoiceStatus.paid
          : amountPaid > 0
              ? InvoiceStatus.partial
              : current.status == InvoiceStatus.sent
                  ? InvoiceStatus.sent
                  : InvoiceStatus.unpaid;
      final updatedNotes = notes ?? current.notes;

      tx.update(invoiceRef, <String, dynamic>{
        'items': items.map((i) => i.toMap()).toList(),
        'totalAmount': newTotal,
        'taxAmount': newTax,
        'discountAmount': newDiscount,
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
        memberAddress: current.memberAddress,
        subscriptionId: current.subscriptionId,
        planName: current.planName,
        currency: current.currency,
        totalAmount: newTotal,
        amountPaid: amountPaid,
        taxAmount: newTax,
        discountAmount: newDiscount,
        stampDuty: current.stampDuty,
        sellerName: current.sellerName,
        sellerAddress: current.sellerAddress,
        sellerTaxId: current.sellerTaxId,
        status: newStatus,
        issuedAt: current.issuedAt,
        dueDate: current.dueDate,
        notes: updatedNotes,
        items: items,
        payments: current.payments,
        createdAt: current.createdAt,
        updatedAt: now,
        isCreditNote: current.isCreditNote,
        originalInvoiceId: current.originalInvoiceId,
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

  // ── Payment recording ─────────────────────────────────────────────────────

  /// Atomically appends [payment] to the invoice's payments list, updates
  /// [amountPaid], and recalculates [status].
  ///
  /// Throws if the invoice is voided or if the payment would exceed [totalAmount].
  Future<Invoice> recordPayment(
    String invoiceId, {
    required num amount,
    required String method,
    String notes = '',
    DateTime? date,
  }) async {
    assert(amount > 0, 'Payment amount must be positive');
    // Runtime guard (asserts are stripped in release builds).
    if (amount <= 0) {
      throw ArgumentError.value(
          amount, 'amount', 'Payment amount must be positive');
    }
    final invoiceRef = _firestore.collection('invoices').doc(invoiceId);
    final paymentDate = date ?? DateTime.now();
    late Invoice updated;

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(invoiceRef);
      if (!snap.exists) throw Exception('Invoice $invoiceId not found');

      final current = Invoice.fromSnapshot(snap);
      if (current.isVoid) throw Exception('Cannot record payment on a voided invoice');

      final newAmountPaid = current.amountPaid + amount;
      if (newAmountPaid > current.totalAmount) {
        throw Exception(
            'Payment of $amount exceeds the outstanding balance '
            '(${current.remainingAmount})');
      }
      final newStatus = newAmountPaid >= current.totalAmount
          ? InvoiceStatus.paid
          : InvoiceStatus.partial;

      final newPayment = InvoicePayment(
        amount: amount,
        date: paymentDate,
        method: method,
        notes: notes,
      );
      final updatedPayments = [...current.payments, newPayment];

      tx.update(invoiceRef, <String, dynamic>{
        'amountPaid': newAmountPaid,
        'status': newStatus,
        'payments': updatedPayments.map((p) => p.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      updated = Invoice(
        id: current.id,
        invoiceNumber: current.invoiceNumber,
        gymId: current.gymId,
        userId: current.userId,
        memberName: current.memberName,
        memberEmail: current.memberEmail,
        memberPhone: current.memberPhone,
        memberAddress: current.memberAddress,
        subscriptionId: current.subscriptionId,
        planName: current.planName,
        currency: current.currency,
        totalAmount: current.totalAmount,
        amountPaid: newAmountPaid,
        taxAmount: current.taxAmount,
        discountAmount: current.discountAmount,
        status: newStatus,
        issuedAt: current.issuedAt,
        dueDate: current.dueDate,
        notes: current.notes,
        items: current.items,
        payments: updatedPayments,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        isCreditNote: current.isCreditNote,
        originalInvoiceId: current.originalInvoiceId,
      );
    });

    return updated;
  }

  // ── Invoice lifecycle ─────────────────────────────────────────────────────

  /// Marks an invoice as sent (admin dispatched it to the member).
  Future<void> markAsSent(String invoiceId) async {
    final ref = _firestore.collection('invoices').doc(invoiceId);
    final snap = await ref.get();
    final current = Invoice.fromSnapshot(snap);
    // Only draft/unpaid → sent
    if (current.isVoid) return;
    final newStatus = current.amountPaid >= current.totalAmount
        ? InvoiceStatus.paid
        : current.amountPaid > 0
            ? InvoiceStatus.partial
            : InvoiceStatus.sent;
    await ref.update(<String, dynamic>{
      'status': newStatus,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Voids an invoice. Voided invoices are kept for audit purposes.
  ///
  /// For invoicing compliance, an invoice that already has payments allocated
  /// cannot be voided — it must be credited instead (see [createCreditNote]).
  /// Voiding an already-voided invoice is a no-op.
  Future<void> voidInvoice(String invoiceId) async {
    final ref = _firestore.collection('invoices').doc(invoiceId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Invoice $invoiceId not found');
    final current = Invoice.fromSnapshot(snap);
    if (current.isVoid) return;
    if (current.amountPaid > 0) {
      throw Exception(
          'Cannot void an invoice with payments allocated — issue a credit '
          'note instead.');
    }
    await ref.update(<String, dynamic>{
      'status': InvoiceStatus.void_,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Marks a single invoice as overdue.
  Future<void> markOverdue(String invoiceId) async {
    await _firestore.collection('invoices').doc(invoiceId).update(<String, dynamic>{
      'status': InvoiceStatus.overdue,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Scans all non-terminal invoices for this gym and marks as overdue any
  /// whose [dueDate] is in the past.  Returns the count of updated invoices.
  Future<int> checkAndUpdateOverdueInvoices() async {
    final now = DateTime.now();
    final snap = await _invoicesQuery.get();
    final toUpdate = snap.docs
        .map((d) => Invoice.fromSnapshot(d))
        .where((inv) =>
            inv.dueDate != null &&
            inv.dueDate!.isBefore(now) &&
            inv.status != InvoiceStatus.paid &&
            inv.status != InvoiceStatus.void_ &&
            inv.status != InvoiceStatus.overdue &&
            inv.status != InvoiceStatus.draft)
        .toList();

    final batch = _firestore.batch();
    final ts = Timestamp.fromDate(now);
    for (final inv in toUpdate) {
      batch.update(
        _firestore.collection('invoices').doc(inv.id),
        {'status': InvoiceStatus.overdue, 'updatedAt': ts},
      );
    }
    if (toUpdate.isNotEmpty) await batch.commit();
    return toUpdate.length;
  }

  /// Streams invoices that are currently overdue (status == 'overdue').
  Stream<List<Invoice>> streamOverdueInvoices() {
    Query<Map<String, dynamic>> q =
        _firestore.collection('invoices').where('status', isEqualTo: InvoiceStatus.overdue);
    if (gymId.isNotEmpty) q = q.where('gymId', isEqualTo: gymId);
    return q.snapshots().map(
        (snap) => snap.docs.map((d) => Invoice.fromSnapshot(d)).toList());
  }

  // ── Credit notes ──────────────────────────────────────────────────────────

  /// Creates a credit note linked to [originalInvoiceId].
  ///
  /// A credit note has [isCreditNote] == true and carries the original invoice
  /// reference.  The amounts are stored as positive integers; callers should
  /// treat the credit note's [totalAmount] as a negative adjustment to the
  /// original invoice balance.
  Future<Invoice> createCreditNote({
    required String originalInvoiceId,
    required String userId,
    required String memberName,
    required String memberEmail,
    String memberPhone = '',
    String memberAddress = '',
    required List<InvoiceItem> items,
    String notes = '',
    DateTime? dueDate,
    String? customInvoiceNumber,
  }) async {
    assert(items.isNotEmpty, 'Credit note must have at least one item');

    // Seller identity snapshot (matricule fiscal etc.) so the credit note is
    // as compliant as the invoice it credits.
    final settings = await getInvoiceSettings();

    final now = DateTime.now();
    final taxAmount = items.fold<num>(0, (s, i) => s + i.taxAmount);
    // Tax-inclusive total, mirroring createInvoice so the credit note nets off
    // cleanly against the original invoice (totalAmount == subtotal + tax).
    final totalAmount =
        items.fold<num>(0, (s, i) => s + i.amount) + taxAmount;
    final invoiceRef = _firestore.collection('invoices').doc();
    String invoiceNumber = '';

    final useCustom =
        customInvoiceNumber != null && customInvoiceNumber.trim().isNotEmpty;

    await _firestore.runTransaction((tx) async {
      if (useCustom) {
        invoiceNumber = customInvoiceNumber.trim();
      } else {
        // Credit notes use their OWN sequential series (creditNoteNextSequence),
        // independent of the invoice counter, per invoicing regulations.
        final settingsSnap = await tx.get(_settingsRef);
        final sData = settingsSnap.data() ?? {};
        final rawPrefix = (sData['creditNotePrefix'] as String?) ?? 'CN-';
        final effectivePrefix = rawPrefix.isEmpty ? 'CN-' : rawPrefix;
        final cnSeq = (sData['creditNoteNextSequence'] as int? ?? 1);
        final padding = (sData['padding'] as int? ?? 4);
        invoiceNumber =
            '$effectivePrefix${cnSeq.toString().padLeft(padding, '0')}';
        // Advance only the credit-note counter; leave the invoice counter and
        // fiscal fields untouched.
        final counterUpdate = <String, dynamic>{
          'creditNoteNextSequence': cnSeq + 1,
          if (gymId.isNotEmpty) 'gymId': gymId,
        };
        if (settingsSnap.exists) {
          tx.update(_settingsRef, counterUpdate);
        } else {
          tx.set(_settingsRef, counterUpdate);
        }
      }

      tx.set(invoiceRef, <String, dynamic>{
        'invoiceNumber': invoiceNumber,
        'gymId': gymId,
        'userId': userId,
        'memberName': memberName,
        'memberEmail': memberEmail,
        'memberPhone': memberPhone,
        'memberAddress': memberAddress,
        'subscriptionId': '',
        'planName': '',
        'currency': items.first.currency,
        'totalAmount': totalAmount,
        'amountPaid': 0,
        'taxAmount': taxAmount,
        'discountAmount': 0,
        'sellerName': settings.companyName,
        'sellerAddress': settings.companyAddress,
        'sellerTaxId': settings.matriculeFiscal,
        'status': InvoiceStatus.unpaid,
        'issuedAt': Timestamp.fromDate(now),
        if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate),
        'notes': notes,
        'items': items.map((i) => i.toMap()).toList(),
        'payments': const <dynamic>[],
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'isCreditNote': true,
        'originalInvoiceId': originalInvoiceId,
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
      memberAddress: memberAddress,
      subscriptionId: '',
      planName: '',
      currency: items.first.currency,
      totalAmount: totalAmount,
      amountPaid: 0,
      taxAmount: taxAmount,
      sellerName: settings.companyName,
      sellerAddress: settings.companyAddress,
      sellerTaxId: settings.matriculeFiscal,
      status: InvoiceStatus.unpaid,
      issuedAt: now,
      dueDate: dueDate,
      notes: notes,
      items: items,
      payments: const [],
      createdAt: now,
      updatedAt: now,
      isCreditNote: true,
      originalInvoiceId: originalInvoiceId,
    );
  }

  // ── Revenue analytics ─────────────────────────────────────────────────────

  /// Computes revenue stats by scanning all gym subscriptions client-side.
  ///
  /// Optionally pass [from] and [to] to restrict the date range used for
  /// today/this-month/last-month buckets and the monthly trend.
  Future<RevenueStats> computeRevenueStats({
    DateTime? from,
    DateTime? to,
  }) async {
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
    final rangeFrom = from;
    final rangeTo = to;
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

        // Apply date range filter when provided
        if (rangeFrom != null && pd.isBefore(rangeFrom)) continue;
        if (rangeTo != null && pd.isAfter(rangeTo)) continue;

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
