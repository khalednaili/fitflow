import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/services/billing_service.dart';
import 'package:fit_flow/models/invoice.dart';
import 'package:fit_flow/models/user_subscription.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

BillingService _sut(FakeFirebaseFirestore db, {String gymId = 'gym1'}) =>
    BillingService(gymId: gymId, firestore: db);

/// Seed invoice settings into Firestore.
Future<void> _seedSettings(
  FakeFirebaseFirestore db, {
  String gymId = 'gym1',
  String prefix = 'INV-',
  int startNumber = 1,
  int nextSequence = 1,
  int padding = 4,
}) =>
    db.collection('settings').doc('invoiceSettings_$gymId').set({
      'prefix': prefix,
      'startNumber': startNumber,
      'nextSequence': nextSequence,
      'padding': padding,
      'gymId': gymId,
    });

UserSubscription _sub({
  String id = 'sub1',
  String gymId = 'gym1',
  String userId = 'u1',
  int totalAmount = 1000,
  String currency = 'EUR',
}) =>
    UserSubscription(
      id: id,
      gymId: gymId,
      userId: userId,
      planId: 'plan1',
      totalAmount: totalAmount,
      amountPaid: 0,
      currency: currency,
      status: 'active',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      paymentHistory: const [],
    );

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late FakeFirebaseFirestore db;
  late BillingService sut;

  setUp(() {
    db = FakeFirebaseFirestore();
    sut = _sut(db);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // InvoiceSettings model
  // ══════════════════════════════════════════════════════════════════════════

  group('InvoiceSettings.fromMap', () {
    test('reads all fields correctly', () {
      final settings = InvoiceSettings.fromMap({
        'prefix': '2026-06-',
        'startNumber': 5,
        'nextSequence': 12,
        'padding': 5,
      });

      expect(settings.prefix, '2026-06-');
      expect(settings.startNumber, 5);
      expect(settings.nextSequence, 12);
      expect(settings.padding, 5);
    });

    test('uses defaults when fields are absent', () {
      final settings = InvoiceSettings.fromMap({});

      expect(settings.prefix, 'INV-');
      expect(settings.startNumber, 1);
      expect(settings.nextSequence, 1);
      expect(settings.padding, 4);
    });

    test('nextSequence falls back to startNumber when absent', () {
      final settings = InvoiceSettings.fromMap({
        'prefix': 'GYM-',
        'startNumber': 10,
        // nextSequence absent
      });

      expect(settings.nextSequence, 10);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // saveInvoiceSettings
  // ══════════════════════════════════════════════════════════════════════════

  group('saveInvoiceSettings', () {
    test('persists prefix, startNumber, padding and gymId', () async {
      await sut.saveInvoiceSettings(
        prefix: '2026-06-',
        startNumber: 1,
        padding: 5,
      );

      final snap =
          await db.collection('settings').doc('invoiceSettings_gym1').get();
      final data = snap.data()!;

      expect(data['prefix'], '2026-06-');
      expect(data['startNumber'], 1);
      expect(data['padding'], 5);
      expect(data['gymId'], 'gym1');
    });

    test(
        'does not reset counter when resetCounter is false and startNumber unchanged',
        () async {
      await _seedSettings(db, nextSequence: 8, startNumber: 1);

      await sut.saveInvoiceSettings(
        prefix: 'INV-',
        startNumber: 1,
        padding: 4,
        resetCounter: false,
      );

      final snap =
          await db.collection('settings').doc('invoiceSettings_gym1').get();
      expect(snap.data()!['nextSequence'], 8);
    });

    test('resets counter when resetCounter is true', () async {
      await _seedSettings(db, nextSequence: 8, startNumber: 1);

      await sut.saveInvoiceSettings(
        prefix: 'INV-',
        startNumber: 1,
        padding: 4,
        resetCounter: true,
      );

      final snap =
          await db.collection('settings').doc('invoiceSettings_gym1').get();
      expect(snap.data()!['nextSequence'], 1);
    });

    test('resets counter when startNumber changes', () async {
      await _seedSettings(db, nextSequence: 8, startNumber: 1);

      await sut.saveInvoiceSettings(
        prefix: 'INV-',
        startNumber: 100,
        padding: 4,
      );

      final snap =
          await db.collection('settings').doc('invoiceSettings_gym1').get();
      expect(snap.data()!['nextSequence'], 100);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // previewNextInvoiceNumber — new format
  // ══════════════════════════════════════════════════════════════════════════

  group('previewNextInvoiceNumber', () {
    test('formats as prefix + padded sequence (no hardcoded year)', () async {
      await _seedSettings(db, prefix: 'INV-', nextSequence: 3, padding: 4);

      final result = await sut.previewNextInvoiceNumber();

      expect(result, 'INV-0003');
    });

    test('respects custom date-based prefix like 2026-06-', () async {
      await _seedSettings(db, prefix: '2026-06-', nextSequence: 1, padding: 4);

      final result = await sut.previewNextInvoiceNumber();

      expect(result, '2026-06-0001');
    });

    test('respects padding=3', () async {
      await _seedSettings(db, prefix: 'GYM-', nextSequence: 42, padding: 3);

      final result = await sut.previewNextInvoiceNumber();

      expect(result, 'GYM-042');
    });

    test('respects padding=6', () async {
      await _seedSettings(db, prefix: 'INV-', nextSequence: 1, padding: 6);

      final result = await sut.previewNextInvoiceNumber();

      expect(result, 'INV-000001');
    });

    test('uses defaults when settings doc is absent', () async {
      // No _seedSettings call — doc does not exist.
      final result = await sut.previewNextInvoiceNumber();

      expect(result, startsWith('INV-'));
      expect(result, 'INV-0001');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // createInvoice — invoice number generation
  // ══════════════════════════════════════════════════════════════════════════

  group('createInvoice — invoice number', () {
    test('auto-generates number using prefix + padding and increments counter',
        () async {
      await _seedSettings(db, prefix: '2026-06-', nextSequence: 7, padding: 4);

      final invoice = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'alice@test.com',
        subscriptions: [_sub()],
        planLabels: ['Basic'],
      );

      expect(invoice.invoiceNumber, '2026-06-0007');

      // Counter must be incremented.
      final snap =
          await db.collection('settings').doc('invoiceSettings_gym1').get();
      expect(snap.data()!['nextSequence'], 8);
    });

    test('uses customInvoiceNumber when provided and does not touch counter',
        () async {
      await _seedSettings(db, prefix: 'INV-', nextSequence: 5, padding: 4);

      final invoice = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Bob',
        memberEmail: 'bob@test.com',
        subscriptions: [_sub()],
        planLabels: ['Pro'],
        customInvoiceNumber: 'CUSTOM-999',
      );

      expect(invoice.invoiceNumber, 'CUSTOM-999');

      // Counter must NOT be incremented.
      final snap =
          await db.collection('settings').doc('invoiceSettings_gym1').get();
      expect(snap.data()!['nextSequence'], 5);
    });

    test('stores gymId on created invoice document', () async {
      await _seedSettings(db);

      final invoice = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Carol',
        memberEmail: 'carol@test.com',
        subscriptions: [_sub()],
        planLabels: ['Basic'],
      );

      final doc = await db.collection('invoices').doc(invoice.id).get();
      expect(doc.data()!['gymId'], 'gym1');
    });

    test('consecutive calls produce sequential numbers', () async {
      await _seedSettings(db, prefix: 'INV-', nextSequence: 1, padding: 4);

      final inv1 = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub()],
        planLabels: ['Basic'],
      );
      final inv2 = await sut.createInvoice(
        userId: 'u2',
        memberName: 'Bob',
        memberEmail: 'b@test.com',
        subscriptions: [_sub(id: 'sub2', userId: 'u2')],
        planLabels: ['Pro'],
      );

      expect(inv1.invoiceNumber, 'INV-0001');
      expect(inv2.invoiceNumber, 'INV-0002');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // streamInvoices — no composite-index orderBy (filters by gymId only)
  // ══════════════════════════════════════════════════════════════════════════

  group('streamInvoices', () {
    Future<void> seedInvoice(
      FakeFirebaseFirestore db, {
      required String gymId,
      required String invoiceNumber,
      required DateTime issuedAt,
      String status = 'unpaid',
    }) =>
        db.collection('invoices').add({
          'gymId': gymId,
          'invoiceNumber': invoiceNumber,
          'userId': 'u1',
          'memberName': 'Alice',
          'memberEmail': 'alice@test.com',
          'memberPhone': '',
          'subscriptionId': 'sub1',
          'planName': 'Basic',
          'currency': 'EUR',
          'totalAmount': 1000,
          'amountPaid': 0,
          'status': status,
          'issuedAt': Timestamp.fromDate(issuedAt),
          'notes': '',
          'items': [],
          'payments': [],
          'createdAt': Timestamp.fromDate(issuedAt),
          'updatedAt': Timestamp.fromDate(issuedAt),
        });

    test('returns only invoices for the correct gym', () async {
      await seedInvoice(db,
          gymId: 'gym1',
          invoiceNumber: 'INV-0001',
          issuedAt: DateTime(2026, 1, 1));
      await seedInvoice(db,
          gymId: 'other_gym',
          invoiceNumber: 'INV-9999',
          issuedAt: DateTime(2026, 1, 2));

      final invoices = await sut.streamInvoices().first;

      expect(invoices.length, 1);
      expect(invoices.first.invoiceNumber, 'INV-0001');
    });

    test('returns all invoices when gymId is empty', () async {
      final sutNoGym = BillingService(gymId: '', firestore: db);

      await seedInvoice(db,
          gymId: 'gym1',
          invoiceNumber: 'A-001',
          issuedAt: DateTime(2026, 1, 1));
      await seedInvoice(db,
          gymId: 'gym2',
          invoiceNumber: 'B-001',
          issuedAt: DateTime(2026, 1, 2));

      final invoices = await sutNoGym.streamInvoices().first;

      expect(invoices.length, 2);
    });

    test('emits updated list when a new invoice is added', () async {
      await seedInvoice(db,
          gymId: 'gym1',
          invoiceNumber: 'INV-0001',
          issuedAt: DateTime(2026, 1, 1));

      final stream = sut.streamInvoices();
      final first = await stream.first;
      expect(first.length, 1);

      await seedInvoice(db,
          gymId: 'gym1',
          invoiceNumber: 'INV-0002',
          issuedAt: DateTime(2026, 1, 2));

      final second = await stream.first;
      expect(second.length, 2);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Invoice.fromSnapshot — parsing
  // ══════════════════════════════════════════════════════════════════════════

  group('Invoice.fromSnapshot', () {
    test('parses all fields without throwing', () async {
      final ref = await db.collection('invoices').add({
        'gymId': 'gym1',
        'invoiceNumber': '2026-06-0001',
        'userId': 'u1',
        'memberName': 'Alice',
        'memberEmail': 'alice@test.com',
        'memberPhone': '+33600000000',
        'subscriptionId': 'sub1',
        'planName': 'Basic',
        'currency': 'EUR',
        'totalAmount': 1200,
        'amountPaid': 600,
        'taxAmount': 200,
        'discountAmount': 50,
        'status': 'partial',
        'issuedAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'dueDate': Timestamp.fromDate(DateTime(2026, 7, 1)),
        'notes': 'First instalment',
        'items': [
          {
            'description': 'Basic plan',
            'amount': 1000,
            'currency': 'EUR',
            'taxRate': 20
          },
        ],
        'payments': [
          {
            'amount': 600,
            'date': Timestamp.fromDate(DateTime(2026, 6, 1)),
            'method': 'cash',
            'notes': '',
          }
        ],
        'createdAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'isCreditNote': false,
      });

      final snap = await db.collection('invoices').doc(ref.id).get();
      final invoice = Invoice.fromSnapshot(snap);

      expect(invoice.invoiceNumber, '2026-06-0001');
      expect(invoice.totalAmount, 1200);
      expect(invoice.amountPaid, 600);
      expect(invoice.taxAmount, 200);
      expect(invoice.discountAmount, 50);
      expect(invoice.remainingAmount, 600);
      expect(invoice.status, 'partial');
      expect(invoice.items.length, 1);
      expect(invoice.items.first.taxRate, 20);
      expect(invoice.items.first.taxAmount, 200);
      expect(invoice.payments.length, 1);
      expect(invoice.dueDate, isNotNull);
      expect(invoice.isCreditNote, false);
    });

    test('uses safe defaults for missing optional fields', () async {
      final ref = await db.collection('invoices').add({
        'gymId': 'gym1',
        'invoiceNumber': 'INV-0001',
        'userId': 'u1',
        'memberName': 'Bob',
        'memberEmail': '',
        'totalAmount': 500,
        'amountPaid': 0,
        'status': 'unpaid',
        'issuedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      final snap = await db.collection('invoices').doc(ref.id).get();
      final invoice = Invoice.fromSnapshot(snap);

      expect(invoice.memberPhone, '');
      expect(invoice.notes, '');
      expect(invoice.items, isEmpty);
      expect(invoice.payments, isEmpty);
      expect(invoice.dueDate, isNull);
      expect(invoice.currency, 'TND'); // app-wide default (Currency.defaultCode)
      expect(invoice.taxAmount, 0);
      expect(invoice.discountAmount, 0);
      expect(invoice.isCreditNote, false);
      expect(invoice.originalInvoiceId, isNull);
    });

    test('parses isCreditNote and originalInvoiceId', () async {
      final ref = await db.collection('invoices').add({
        'gymId': 'gym1',
        'invoiceNumber': 'CR-INV-0001',
        'userId': 'u1',
        'memberName': 'Alice',
        'memberEmail': 'a@test.com',
        'totalAmount': 500,
        'amountPaid': 0,
        'status': 'unpaid',
        'issuedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'isCreditNote': true,
        'originalInvoiceId': 'orig-inv-abc',
      });

      final snap = await db.collection('invoices').doc(ref.id).get();
      final invoice = Invoice.fromSnapshot(snap);

      expect(invoice.isCreditNote, true);
      expect(invoice.originalInvoiceId, 'orig-inv-abc');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // InvoiceItem — taxRate and taxAmount
  // ══════════════════════════════════════════════════════════════════════════

  group('InvoiceItem', () {
    test('taxAmount rounds amount * taxRate / 100', () {
      const item = InvoiceItem(
        description: 'Plan',
        amount: 1000,
        currency: 'EUR',
        taxRate: 20,
      );
      expect(item.taxAmount, 200);
    });

    test('taxAmount is 0 when taxRate is 0', () {
      const item = InvoiceItem(
        description: 'Plan',
        amount: 1000,
        currency: 'EUR',
      );
      expect(item.taxAmount, 0);
    });

    test('fromMap reads taxRate', () {
      final item = InvoiceItem.fromMap({
        'description': 'Plan',
        'amount': 500,
        'currency': 'EUR',
        'taxRate': 10,
      });
      expect(item.taxRate, 10);
      expect(item.taxAmount, 50);
    });

    test('fromMap defaults taxRate to 0 when absent', () {
      final item = InvoiceItem.fromMap({
        'description': 'Plan',
        'amount': 500,
        'currency': 'EUR',
      });
      expect(item.taxRate, 0);
    });

    test('toMap includes taxRate', () {
      const item = InvoiceItem(
        description: 'Plan',
        amount: 500,
        currency: 'EUR',
        taxRate: 15,
      );
      expect(item.toMap()['taxRate'], 15);
    });

    test('taxAmount handles fractional (millime) amounts', () {
      const item = InvoiceItem(
        description: 'Drop-in',
        amount: 49.5,
        currency: 'TND',
        taxRate: 19,
      );
      // 49.5 * 19% = 9.405 (rounded to millime precision)
      expect(item.taxAmount, closeTo(9.405, 0.0001));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // InvoiceStatus — validated()
  // ══════════════════════════════════════════════════════════════════════════

  group('InvoiceStatus.validated', () {
    test('accepts all known statuses', () {
      for (final s in [
        InvoiceStatus.draft,
        InvoiceStatus.unpaid,
        InvoiceStatus.sent,
        InvoiceStatus.partial,
        InvoiceStatus.paid,
        InvoiceStatus.overdue,
        InvoiceStatus.void_,
      ]) {
        expect(InvoiceStatus.validated(s), s);
      }
    });

    test('falls back to unpaid for unknown value', () {
      expect(InvoiceStatus.validated('garbage'), InvoiceStatus.unpaid);
      expect(InvoiceStatus.validated(''), InvoiceStatus.unpaid);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Invoice computed getters
  // ══════════════════════════════════════════════════════════════════════════

  group('Invoice computed getters', () {
    Invoice makeInvoice({
      String status = InvoiceStatus.unpaid,
      DateTime? dueDate,
      int totalAmount = 1000,
      int amountPaid = 0,
      int taxAmount = 0,
      int discountAmount = 0,
    }) =>
        Invoice(
          id: 'i1',
          invoiceNumber: 'INV-0001',
          gymId: 'gym1',
          userId: 'u1',
          memberName: 'Alice',
          memberEmail: 'a@test.com',
          subscriptionId: 's1',
          planName: 'Basic',
          currency: 'EUR',
          totalAmount: totalAmount,
          amountPaid: amountPaid,
          taxAmount: taxAmount,
          discountAmount: discountAmount,
          status: status,
          issuedAt: DateTime(2026, 1, 1),
          dueDate: dueDate,
          items: const [],
          payments: const [],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('remainingAmount = totalAmount - amountPaid', () {
      final inv = makeInvoice(totalAmount: 1000, amountPaid: 400);
      expect(inv.remainingAmount, 600);
    });

    test('isPaid is true only for paid status', () {
      expect(makeInvoice(status: InvoiceStatus.paid).isPaid, true);
      expect(makeInvoice(status: InvoiceStatus.unpaid).isPaid, false);
    });

    test('isVoid is true only for void status', () {
      expect(makeInvoice(status: InvoiceStatus.void_).isVoid, true);
      expect(makeInvoice(status: InvoiceStatus.unpaid).isVoid, false);
    });

    test('isDraft is true only for draft status', () {
      expect(makeInvoice(status: InvoiceStatus.draft).isDraft, true);
      expect(makeInvoice(status: InvoiceStatus.unpaid).isDraft, false);
    });

    test(
        'isOverdue is true when dueDate is past and status is not paid/void/draft',
        () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(makeInvoice(status: InvoiceStatus.unpaid, dueDate: past).isOverdue,
          true);
      expect(makeInvoice(status: InvoiceStatus.sent, dueDate: past).isOverdue,
          true);
    });

    test('isOverdue is false when status is paid', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(makeInvoice(status: InvoiceStatus.paid, dueDate: past).isOverdue,
          false);
    });

    test('isOverdue is false when status is void', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(makeInvoice(status: InvoiceStatus.void_, dueDate: past).isOverdue,
          false);
    });

    test('isOverdue is false when dueDate is in the future', () {
      final future = DateTime.now().add(const Duration(days: 5));
      expect(
          makeInvoice(status: InvoiceStatus.unpaid, dueDate: future).isOverdue,
          false);
    });

    test('isOverdue is false when dueDate is null', () {
      expect(makeInvoice(status: InvoiceStatus.unpaid).isOverdue, false);
    });

    test('subtotal = sum of item amounts (not totalAmount)', () {
      final inv = Invoice(
        id: 'i1',
        invoiceNumber: 'INV-0001',
        gymId: 'gym1',
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptionId: 's1',
        planName: 'Basic',
        currency: 'EUR',
        totalAmount: 1320,
        amountPaid: 0,
        taxAmount: 200,
        discountAmount: 80,
        status: InvoiceStatus.unpaid,
        issuedAt: DateTime(2026, 1, 1),
        items: const [
          InvoiceItem(description: 'Plan A', amount: 600, currency: 'EUR'),
          InvoiceItem(description: 'Plan B', amount: 600, currency: 'EUR'),
        ],
        payments: const [],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(inv.subtotal, 1200); // sum of items
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // recordPayment
  // ══════════════════════════════════════════════════════════════════════════

  group('recordPayment', () {
    Future<String> createUnpaidInvoice({int total = 1000}) async {
      await _seedSettings(db);
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub(totalAmount: total)],
        planLabels: ['Basic'],
      );
      return inv.id;
    }

    test('appends payment, updates amountPaid and sets status to partial',
        () async {
      final id = await createUnpaidInvoice(total: 1000);

      await sut.recordPayment(id, amount: 400, method: 'cash');

      final doc = await db.collection('invoices').doc(id).get();
      final data = doc.data()!;
      expect(data['amountPaid'], 400);
      expect(data['status'], InvoiceStatus.partial);
      expect((data['payments'] as List).length, 1);
      expect((data['payments'] as List).first['method'], 'cash');
    });

    test('sets status to paid when full amount is covered', () async {
      final id = await createUnpaidInvoice(total: 1000);

      await sut.recordPayment(id, amount: 1000, method: 'card');

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.paid);
      expect(doc.data()!['amountPaid'], 1000);
    });

    test('accumulates multiple payments correctly', () async {
      final id = await createUnpaidInvoice(total: 900);

      await sut.recordPayment(id, amount: 300, method: 'cash');
      await sut.recordPayment(id, amount: 300, method: 'card');
      await sut.recordPayment(id, amount: 300, method: 'cash');

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['amountPaid'], 900);
      expect(doc.data()!['status'], InvoiceStatus.paid);
      expect((doc.data()!['payments'] as List).length, 3);
    });

    test('throws when invoice is voided', () async {
      final id = await createUnpaidInvoice();
      await sut.voidInvoice(id);

      expect(
        () => sut.recordPayment(id, amount: 100, method: 'cash'),
        throwsA(isA<Exception>()),
      );
    });

    test('stores payment notes and date', () async {
      final id = await createUnpaidInvoice();
      final date = DateTime(2026, 6, 15);

      await sut.recordPayment(id,
          amount: 500,
          method: 'transfer',
          notes: 'June instalment',
          date: date);

      final doc = await db.collection('invoices').doc(id).get();
      final payment = (doc.data()!['payments'] as List).first as Map;
      expect(payment['notes'], 'June instalment');
      expect(payment['method'], 'transfer');
    });

    test('throws when a payment would exceed the outstanding balance',
        () async {
      final id = await createUnpaidInvoice(total: 1000);
      await sut.recordPayment(id, amount: 600, method: 'cash');

      // 600 already paid → only 400 outstanding; 600 must be rejected.
      await expectLater(
        sut.recordPayment(id, amount: 600, method: 'card'),
        throwsA(isA<Exception>()),
      );

      // The rejected payment must not have mutated the invoice.
      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['amountPaid'], 600);
      expect((doc.data()!['payments'] as List).length, 1);
    });

    test('allows a payment that exactly settles the balance', () async {
      final id = await createUnpaidInvoice(total: 1000);
      await sut.recordPayment(id, amount: 400, method: 'cash');
      await sut.recordPayment(id, amount: 600, method: 'card');

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['amountPaid'], 1000);
      expect(doc.data()!['status'], InvoiceStatus.paid);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // createInvoice — totals invariant (subtotal + tax - discount)
  // ══════════════════════════════════════════════════════════════════════════

  group('createInvoice totals', () {
    test('totalAmount = subtotal + tax - discount', () async {
      await _seedSettings(db);
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub(totalAmount: 1000)],
        planLabels: ['Basic'],
        extraItems: const [
          InvoiceItem(
              description: 'Setup fee',
              amount: 1000,
              currency: 'EUR',
              taxRate: 20),
        ],
        discountAmount: 100,
      );

      // subtotal = 1000 (base, no tax) + 1000 (setup) = 2000
      // tax = 200 (only the setup item is taxed)
      // total = 2000 + 200 - 100 = 2100
      expect(inv.subtotal, 2000);
      expect(inv.taxAmount, 200);
      expect(inv.discountAmount, 100);
      expect(inv.totalAmount, 2100);
      // Invariant the PDF/UI rely on.
      expect(inv.totalAmount, inv.subtotal + inv.taxAmount - inv.discountAmount);
    });

    test('discount is clamped to the subtotal (never produces a negative total)',
        () async {
      await _seedSettings(db);
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub(totalAmount: 1000)],
        planLabels: ['Basic'],
        discountAmount: 5000, // larger than the subtotal
      );

      expect(inv.discountAmount, 1000);
      expect(inv.totalAmount, 0);
    });

    test('invalid status falls back to unpaid', () async {
      await _seedSettings(db);
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub()],
        planLabels: ['Basic'],
        status: 'bogus',
      );

      expect(inv.status, InvoiceStatus.unpaid);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // updateInvoiceItems — must keep totals tax/discount-consistent
  // ══════════════════════════════════════════════════════════════════════════

  group('updateInvoiceItems', () {
    Future<String> createTaxedInvoice() async {
      await _seedSettings(db);
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub(totalAmount: 1000)],
        planLabels: ['Basic'],
        extraItems: const [],
      );
      return inv.id;
    }

    test('recomputes totalAmount tax-inclusively and persists taxAmount',
        () async {
      final id = await createTaxedInvoice();

      final updated = await sut.updateInvoiceItems(
        invoiceId: id,
        items: const [
          InvoiceItem(
              description: 'Plan A', amount: 500, currency: 'EUR', taxRate: 20),
          InvoiceItem(
              description: 'Plan B', amount: 500, currency: 'EUR', taxRate: 20),
        ],
      );

      // subtotal 1000, tax 200 → total 1200 (previously dropped tax → 1000).
      expect(updated.totalAmount, 1200);
      expect(updated.taxAmount, 200);

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['totalAmount'], 1200);
      expect(doc.data()!['taxAmount'], 200);
    });

    test('preserves the existing discount, clamped to the new subtotal',
        () async {
      await _seedSettings(db);
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub(totalAmount: 1000)],
        planLabels: ['Basic'],
        discountAmount: 100,
      );

      final updated = await sut.updateInvoiceItems(
        invoiceId: inv.id,
        items: const [
          InvoiceItem(description: 'Plan A', amount: 800, currency: 'EUR'),
        ],
      );

      // subtotal 800, tax 0, discount preserved 100 → total 700.
      expect(updated.discountAmount, 100);
      expect(updated.totalAmount, 700);
    });

    test(
        'marks paid (with overpayment surfaced) when new total drops below '
        'amountPaid', () async {
      final id = await createTaxedInvoice(); // total 1000
      await sut.recordPayment(id, amount: 1000, method: 'cash'); // fully paid

      final updated = await sut.updateInvoiceItems(
        invoiceId: id,
        items: const [
          InvoiceItem(description: 'Reduced', amount: 600, currency: 'EUR'),
        ],
      );

      // amountPaid (1000) >= new total (600) → paid; remaining negative
      // surfaces the 400 overpayment for refund/credit-note handling.
      expect(updated.totalAmount, 600);
      expect(updated.status, InvoiceStatus.paid);
      expect(updated.remainingAmount, -400);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // voidInvoice / markAsSent / markOverdue
  // ══════════════════════════════════════════════════════════════════════════

  group('lifecycle transitions', () {
    Future<String> createInvoice({String status = InvoiceStatus.unpaid}) async {
      await _seedSettings(db);
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub()],
        planLabels: ['Basic'],
        status: status,
      );
      return inv.id;
    }

    test('voidInvoice sets status to void', () async {
      final id = await createInvoice();
      await sut.voidInvoice(id);

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.void_);
    });

    test('markAsSent sets status to sent for an unpaid invoice', () async {
      final id = await createInvoice();
      await sut.markAsSent(id);

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.sent);
    });

    test('markAsSent does not downgrade a paid invoice', () async {
      final id = await createInvoice();
      // Pay in full first
      await sut.recordPayment(id, amount: 1000, method: 'cash');
      await sut.markAsSent(id);

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.paid);
    });

    test('markAsSent reflects a partial payment instead of sent', () async {
      final id = await createInvoice(); // total 1000
      await sut.recordPayment(id, amount: 400, method: 'cash');
      await sut.markAsSent(id);

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.partial);
    });

    test('markAsSent is a no-op on a voided invoice', () async {
      final id = await createInvoice();
      await sut.voidInvoice(id);
      await sut.markAsSent(id);

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.void_);
    });

    test('markOverdue sets status to overdue', () async {
      final id = await createInvoice();
      await sut.markOverdue(id);

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.overdue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // checkAndUpdateOverdueInvoices
  // ══════════════════════════════════════════════════════════════════════════

  group('checkAndUpdateOverdueInvoices', () {
    Future<String> seedInvoiceWithDueDate(
      DateTime dueDate, {
      String status = InvoiceStatus.unpaid,
    }) async {
      final ref = await db.collection('invoices').add({
        'gymId': 'gym1',
        'invoiceNumber': 'INV-X',
        'userId': 'u1',
        'memberName': 'Alice',
        'memberEmail': 'a@test.com',
        'memberPhone': '',
        'subscriptionId': 'sub1',
        'planName': 'Basic',
        'currency': 'EUR',
        'totalAmount': 1000,
        'amountPaid': 0,
        'status': status,
        'issuedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'dueDate': Timestamp.fromDate(dueDate),
        'notes': '',
        'items': [],
        'payments': [],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'isCreditNote': false,
      });
      return ref.id;
    }

    test('marks past-due unpaid invoices as overdue and returns count',
        () async {
      final past = DateTime.now().subtract(const Duration(days: 3));
      final future = DateTime.now().add(const Duration(days: 10));

      final overdueId = await seedInvoiceWithDueDate(past);
      await seedInvoiceWithDueDate(future); // should not be touched

      final count = await sut.checkAndUpdateOverdueInvoices();

      expect(count, 1);
      final doc = await db.collection('invoices').doc(overdueId).get();
      expect(doc.data()!['status'], InvoiceStatus.overdue);
    });

    test('does not touch paid invoices even when past due', () async {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final id = await seedInvoiceWithDueDate(past, status: InvoiceStatus.paid);

      final count = await sut.checkAndUpdateOverdueInvoices();

      expect(count, 0);
      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.paid);
    });

    test('does not touch voided invoices', () async {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final id =
          await seedInvoiceWithDueDate(past, status: InvoiceStatus.void_);

      final count = await sut.checkAndUpdateOverdueInvoices();

      expect(count, 0);
      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.void_);
    });

    test('returns 0 when all invoices have future due dates', () async {
      final future = DateTime.now().add(const Duration(days: 30));
      await seedInvoiceWithDueDate(future);

      final count = await sut.checkAndUpdateOverdueInvoices();
      expect(count, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // streamOverdueInvoices
  // ══════════════════════════════════════════════════════════════════════════

  group('streamOverdueInvoices', () {
    Future<void> seedStatus(String gymId, String status) =>
        db.collection('invoices').add({
          'gymId': gymId,
          'invoiceNumber': 'X',
          'userId': 'u1',
          'memberName': 'A',
          'memberEmail': 'a@test.com',
          'memberPhone': '',
          'subscriptionId': '',
          'planName': '',
          'currency': 'EUR',
          'totalAmount': 100,
          'amountPaid': 0,
          'status': status,
          'issuedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'notes': '',
          'items': [],
          'payments': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'isCreditNote': false,
        });

    test('returns only overdue invoices for the gym', () async {
      await seedStatus('gym1', InvoiceStatus.overdue);
      await seedStatus('gym1', InvoiceStatus.unpaid);
      await seedStatus('gym1', InvoiceStatus.paid);
      await seedStatus('other_gym', InvoiceStatus.overdue);

      final list = await sut.streamOverdueInvoices().first;

      expect(list.length, 1);
      expect(list.first.status, InvoiceStatus.overdue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // createCreditNote
  // ══════════════════════════════════════════════════════════════════════════

  group('createCreditNote', () {
    test('creates a credit note with isCreditNote=true and originalInvoiceId',
        () async {
      await _seedSettings(db);

      const items = [
        InvoiceItem(
            description: 'Refund - Basic plan', amount: 500, currency: 'EUR'),
      ];
      final cn = await sut.createCreditNote(
        originalInvoiceId: 'orig-abc',
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        items: items,
        notes: 'Full refund',
      );

      expect(cn.isCreditNote, true);
      expect(cn.originalInvoiceId, 'orig-abc');
      expect(cn.totalAmount, 500);

      final doc = await db.collection('invoices').doc(cn.id).get();
      expect(doc.data()!['isCreditNote'], true);
      expect(doc.data()!['originalInvoiceId'], 'orig-abc');
    });

    test('credit note status starts as unpaid', () async {
      await _seedSettings(db);
      final cn = await sut.createCreditNote(
        originalInvoiceId: 'orig-abc',
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        items: const [
          InvoiceItem(description: 'Refund', amount: 200, currency: 'EUR'),
        ],
      );
      expect(cn.status, InvoiceStatus.unpaid);
    });

    test('totalAmount is tax-inclusive (subtotal + tax)', () async {
      await _seedSettings(db);
      final cn = await sut.createCreditNote(
        originalInvoiceId: 'orig-abc',
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        items: const [
          InvoiceItem(
              description: 'Refund - Basic plan',
              amount: 1000,
              currency: 'EUR',
              taxRate: 20),
        ],
      );

      // 1000 + 20% tax = 1200, mirroring how createInvoice builds totals.
      expect(cn.taxAmount, 200);
      expect(cn.totalAmount, 1200);

      final doc = await db.collection('invoices').doc(cn.id).get();
      expect(doc.data()!['totalAmount'], 1200);
      expect(doc.data()!['taxAmount'], 200);
    });

    test('uses its own CN- series, leaving the invoice counter untouched',
        () async {
      // Invoice counter at 7; credit-note counter defaults to 1.
      await _seedSettings(db, prefix: 'INV-', nextSequence: 7);
      final cn = await sut.createCreditNote(
        originalInvoiceId: 'orig-abc',
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        items: const [
          InvoiceItem(description: 'Refund', amount: 200, currency: 'EUR'),
        ],
      );

      expect(cn.invoiceNumber, 'CN-0001');

      final settings = await sut.getInvoiceSettings();
      expect(settings.nextSequence, 7); // invoice counter NOT advanced
      expect(settings.creditNoteNextSequence, 2); // CN counter advanced
    });

    test('consecutive credit notes increment the CN series', () async {
      await _seedSettings(db);
      final cn1 = await sut.createCreditNote(
        originalInvoiceId: 'orig-1',
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        items: const [
          InvoiceItem(description: 'Refund', amount: 100, currency: 'EUR'),
        ],
      );
      final cn2 = await sut.createCreditNote(
        originalInvoiceId: 'orig-2',
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        items: const [
          InvoiceItem(description: 'Refund', amount: 100, currency: 'EUR'),
        ],
      );

      expect(cn1.invoiceNumber, 'CN-0001');
      expect(cn2.invoiceNumber, 'CN-0002');
    });

    test('snapshots seller identity (matricule fiscal) and buyer address',
        () async {
      await db.collection('settings').doc('invoiceSettings_gym1').set({
        'prefix': 'INV-',
        'nextSequence': 1,
        'padding': 4,
        'gymId': 'gym1',
        'companyName': 'Carthage CrossFit',
        'matriculeFiscal': '1234567/A/M/000',
      });

      final cn = await sut.createCreditNote(
        originalInvoiceId: 'orig-abc',
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        memberAddress: '10 Rue de Carthage, Tunis',
        items: const [
          InvoiceItem(description: 'Refund', amount: 200, currency: 'TND'),
        ],
      );

      expect(cn.sellerName, 'Carthage CrossFit');
      expect(cn.sellerTaxId, '1234567/A/M/000');
      expect(cn.memberAddress, '10 Rue de Carthage, Tunis');

      final doc = await db.collection('invoices').doc(cn.id).get();
      expect(doc.data()!['sellerTaxId'], '1234567/A/M/000');
      expect(doc.data()!['memberAddress'], '10 Rue de Carthage, Tunis');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Invoice read / number / delete
  // ══════════════════════════════════════════════════════════════════════════

  group('invoice read, number and delete', () {
    Future<Invoice> create({String userId = 'u1'}) async {
      await _seedSettings(db);
      return sut.createInvoice(
        userId: userId,
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub(userId: userId)],
        planLabels: ['Basic'],
      );
    }

    test('getInvoice returns the invoice when it exists', () async {
      final inv = await create();
      final fetched = await sut.getInvoice(inv.id);
      expect(fetched, isNotNull);
      expect(fetched!.id, inv.id);
      expect(fetched.memberName, 'Alice');
    });

    test('getInvoice returns null for a missing id', () async {
      expect(await sut.getInvoice('does-not-exist'), isNull);
    });

    test('updateInvoiceNumber trims and persists the new number', () async {
      final inv = await create();
      await sut.updateInvoiceNumber(inv.id, '  CUSTOM-99  ');

      final doc = await db.collection('invoices').doc(inv.id).get();
      expect(doc.data()!['invoiceNumber'], 'CUSTOM-99');
    });

    test('deleteInvoice removes the document', () async {
      final inv = await create();
      await sut.deleteInvoice(inv.id);

      final doc = await db.collection('invoices').doc(inv.id).get();
      expect(doc.exists, isFalse);
    });

    test('streamInvoicesForUser filters by user and sorts newest first',
        () async {
      await _seedSettings(db);
      // Two invoices for u1 with different issued dates, one for u2.
      final older = await db.collection('invoices').add({
        'gymId': 'gym1',
        'invoiceNumber': 'INV-0001',
        'userId': 'u1',
        'issuedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'status': 'unpaid',
      });
      final newer = await db.collection('invoices').add({
        'gymId': 'gym1',
        'invoiceNumber': 'INV-0002',
        'userId': 'u1',
        'issuedAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'status': 'unpaid',
      });
      await db.collection('invoices').add({
        'gymId': 'gym1',
        'invoiceNumber': 'INV-0003',
        'userId': 'u2',
        'issuedAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
        'status': 'unpaid',
      });

      final list = await sut.streamInvoicesForUser('u1').first;
      expect(list.map((i) => i.id).toList(), [newer.id, older.id]);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // computeRevenueStats — date range filtering
  // ══════════════════════════════════════════════════════════════════════════

  group('computeRevenueStats — date range', () {
    final now = DateTime.now();

    Future<void> seedSubWithPayments(
      FakeFirebaseFirestore db, {
      required List<({DateTime date, int amount, String method})> payments,
    }) async {
      final paymentData = payments
          .map((p) => {
                'amount': p.amount,
                'date': Timestamp.fromDate(p.date),
                'method': p.method,
                'notes': '',
              })
          .toList();
      await db.collection('user_subscriptions').add({
        'gymId': 'gym1',
        'userId': 'u1',
        'planId': 'plan1',
        'totalAmount': 2000,
        'amountPaid': payments.fold(0, (s, p) => s + p.amount),
        'currency': 'EUR',
        'status': 'active',
        'startDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'endDate': Timestamp.fromDate(DateTime(2026, 12, 31)),
        'paymentHistory': paymentData,
        'updatedAt': Timestamp.now(),
      });
    }

    test('includes all payments when no date range is given', () async {
      await seedSubWithPayments(db, payments: [
        (
          date: now.subtract(const Duration(days: 60)),
          amount: 500,
          method: 'cash'
        ),
        // Use `now` (not a fixed offset) so the payment always lands in the
        // current month, even when the test runs early in the month.
        (date: now, amount: 300, method: 'cash'),
      ]);

      final stats = await sut.computeRevenueStats();
      expect(stats.revenueThisMonth, greaterThanOrEqualTo(300));
    });

    test('excludes payments before the from date', () async {
      final oldPaymentDate = now.subtract(const Duration(days: 90));
      // `now` is guaranteed to be within the current month and after `from`.
      final recentPaymentDate = now;

      await seedSubWithPayments(db, payments: [
        (date: oldPaymentDate, amount: 999, method: 'cash'),
        (date: recentPaymentDate, amount: 100, method: 'card'),
      ]);

      final from = now.subtract(const Duration(days: 30));
      final stats = await sut.computeRevenueStats(from: from);

      // The 999 old payment is before `from` so only 100 should be in this-month
      expect(stats.revenueThisMonth, 100);
    });

    test('excludes payments after the to date', () async {
      await seedSubWithPayments(db, payments: [
        (date: now, amount: 999, method: 'cash'), // today — excluded
      ]);

      final to = now.subtract(const Duration(days: 1));
      final stats = await sut.computeRevenueStats(to: to);

      expect(stats.revenueToday, 0);
    });

    test('currency is populated from subscriptions', () async {
      await seedSubWithPayments(db, payments: [
        (date: now, amount: 100, method: 'cash'),
      ]);

      final stats = await sut.computeRevenueStats();
      expect(stats.currency, 'EUR');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // computeRevenueStats — aggregation
  // ══════════════════════════════════════════════════════════════════════════

  group('computeRevenueStats — aggregation', () {
    final now = DateTime.now();

    Future<void> seedSub({
      required int totalAmount,
      required int amountPaid,
      String status = 'active',
      List<({DateTime date, int amount, String method})> payments = const [],
    }) async {
      await db.collection('user_subscriptions').add({
        'gymId': 'gym1',
        'userId': 'u1',
        'planId': 'plan1',
        'totalAmount': totalAmount,
        'amountPaid': amountPaid,
        'currency': 'EUR',
        'status': status,
        'startDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'endDate': Timestamp.fromDate(DateTime(2026, 12, 31)),
        'paymentHistory': payments
            .map((p) => {
                  'amount': p.amount,
                  'date': Timestamp.fromDate(p.date),
                  'method': p.method,
                  'notes': '',
                })
            .toList(),
        'updatedAt': Timestamp.now(),
      });
    }

    test('totalOutstanding sums remaining balances but excludes cancelled subs',
        () async {
      await seedSub(totalAmount: 1000, amountPaid: 400); // outstanding 600
      await seedSub(totalAmount: 500, amountPaid: 500); // outstanding 0
      await seedSub(
          totalAmount: 800, amountPaid: 0, status: 'cancelled'); // ignored

      final stats = await sut.computeRevenueStats();
      expect(stats.totalOutstanding, 600);
    });

    test('totalOutstanding clamps overpaid subscriptions to zero', () async {
      await seedSub(totalAmount: 1000, amountPaid: 1200); // remaining -200
      final stats = await sut.computeRevenueStats();
      expect(stats.totalOutstanding, 0);
    });

    test('revenueByMethod groups payment amounts by method', () async {
      await seedSub(totalAmount: 2000, amountPaid: 900, payments: [
        (date: now, amount: 400, method: 'cash'),
        (date: now, amount: 300, method: 'card'),
        (date: now, amount: 200, method: 'cash'),
      ]);

      final stats = await sut.computeRevenueStats();
      expect(stats.revenueByMethod['cash'], 600);
      expect(stats.revenueByMethod['card'], 300);
    });

    test('blank payment method is bucketed as "other"', () async {
      await seedSub(totalAmount: 1000, amountPaid: 150, payments: [
        (date: now, amount: 150, method: ''),
      ]);

      final stats = await sut.computeRevenueStats();
      expect(stats.revenueByMethod['other'], 150);
    });

    test('monthlyTrend exposes 6 buckets and includes the current month',
        () async {
      await seedSub(totalAmount: 1000, amountPaid: 250, payments: [
        (date: now, amount: 250, method: 'cash'),
      ]);

      final stats = await sut.computeRevenueStats();
      expect(stats.monthlyTrend.length, 6);
      final key =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      expect(stats.monthlyTrend[key], 250);
    });

    test('revenueToday and revenueThisMonth count a payment made today',
        () async {
      await seedSub(totalAmount: 1000, amountPaid: 500, payments: [
        (date: now, amount: 500, method: 'cash'),
      ]);

      final stats = await sut.computeRevenueStats();
      expect(stats.revenueToday, 500);
      expect(stats.revenueThisMonth, 500);
      expect(stats.newPaymentsThisMonth, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // voidInvoice — audit compliance (void, don't delete; can't void if paid)
  // ══════════════════════════════════════════════════════════════════════════

  group('voidInvoice — audit compliance', () {
    Future<String> createUnpaid({int total = 1000}) async {
      await _seedSettings(db);
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub(totalAmount: total)],
        planLabels: ['Basic'],
      );
      return inv.id;
    }

    test('voids an unpaid invoice', () async {
      final id = await createUnpaid();
      await sut.voidInvoice(id);

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.void_);
    });

    test('throws when the invoice has payments allocated', () async {
      final id = await createUnpaid(total: 1000);
      await sut.recordPayment(id, amount: 400, method: 'cash');

      await expectLater(sut.voidInvoice(id), throwsA(isA<Exception>()));

      // The invoice must be left in its prior (partial) state, not voided.
      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.partial);
    });

    test('is idempotent on an already-voided invoice', () async {
      final id = await createUnpaid();
      await sut.voidInvoice(id);
      await sut.voidInvoice(id); // must not throw

      final doc = await db.collection('invoices').doc(id).get();
      expect(doc.data()!['status'], InvoiceStatus.void_);
    });

    test('throws for a missing invoice', () async {
      await expectLater(sut.voidInvoice('nope'), throwsA(isA<Exception>()));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // createInvoice — Tunisian fiscal (timbre + seller snapshot)
  // ══════════════════════════════════════════════════════════════════════════

  group('createInvoice — Tunisian fiscal', () {
    Future<void> seedFiscal({
      num stampDuty = 1.0,
      String company = 'Carthage CrossFit',
      String address = 'Tunis',
      String matricule = '1234567/A/M/000',
    }) =>
        db.collection('settings').doc('invoiceSettings_gym1').set({
          'prefix': 'INV-',
          'startNumber': 1,
          'nextSequence': 1,
          'padding': 4,
          'gymId': 'gym1',
          'companyName': company,
          'companyAddress': address,
          'matriculeFiscal': matricule,
          'stampDuty': stampDuty,
          'defaultVatRate': 19,
        });

    Future<Invoice> create({
      num? stampDuty,
      List<InvoiceItem> extraItems = const [],
      num discountAmount = 0,
    }) =>
        sut.createInvoice(
          userId: 'u1',
          memberName: 'Alice',
          memberEmail: 'a@test.com',
          subscriptions: [_sub(totalAmount: 1000, currency: 'TND')],
          planLabels: ['Basic'],
          stampDuty: stampDuty,
          extraItems: extraItems,
          discountAmount: discountAmount,
        );

    test('applies the settings stamp and snapshots seller identity', () async {
      await seedFiscal(stampDuty: 1.0);
      final inv = await create();

      expect(inv.stampDuty, 1.0);
      expect(inv.sellerName, 'Carthage CrossFit');
      expect(inv.sellerAddress, 'Tunis');
      expect(inv.sellerTaxId, '1234567/A/M/000');
      expect(inv.totalAmount, 1001); // subtotal 1000 + stamp 1
    });

    test('explicit stampDuty overrides the settings default', () async {
      await seedFiscal(stampDuty: 1.0);
      final inv = await create(stampDuty: 0.6);

      expect(inv.stampDuty, 0.6);
      expect(inv.totalAmount, 1000.6);
    });

    test('total = subtotal + tax - discount + stamp', () async {
      await seedFiscal(stampDuty: 1.0);
      final inv = await create(
        extraItems: const [
          InvoiceItem(
              description: 'Extra',
              amount: 100,
              currency: 'TND',
              taxRate: 19),
        ],
        discountAmount: 50,
      );

      // subtotal 1100, tax 19 (19% of 100), discount 50, stamp 1 → 1070
      expect(inv.taxAmount, 19);
      expect(inv.totalAmount, 1070);
    });

    test('persists fiscal fields on the invoice document', () async {
      await seedFiscal(stampDuty: 1.0);
      final inv = await create();

      final doc = await db.collection('invoices').doc(inv.id).get();
      expect(doc.data()!['stampDuty'], 1.0);
      expect(doc.data()!['sellerTaxId'], '1234567/A/M/000');
    });

    test('auto-numbering preserves fiscal settings (merge, not overwrite)',
        () async {
      await seedFiscal(stampDuty: 1.0);
      await create(); // consumes the counter via a merged settings write

      final s =
          await db.collection('settings').doc('invoiceSettings_gym1').get();
      expect(s.data()!['companyName'], 'Carthage CrossFit');
      expect(s.data()!['matriculeFiscal'], '1234567/A/M/000');
      expect(s.data()!['nextSequence'], 2); // counter incremented
    });

    test('stamp defaults to 0 when settings have none (non-Tunisia gyms)',
        () async {
      await _seedSettings(db); // no fiscal fields
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        subscriptions: [_sub(totalAmount: 1000)],
        planLabels: ['Basic'],
      );
      expect(inv.stampDuty, 0);
      expect(inv.totalAmount, 1000); // no surprise stamp charge
    });

    test('stores the buyer address on the invoice', () async {
      await seedFiscal();
      final inv = await sut.createInvoice(
        userId: 'u1',
        memberName: 'Alice',
        memberEmail: 'a@test.com',
        memberAddress: '10 Rue de Carthage, Tunis',
        subscriptions: [_sub(totalAmount: 1000, currency: 'TND')],
        planLabels: ['Basic'],
      );

      expect(inv.memberAddress, '10 Rue de Carthage, Tunis');
      final doc = await db.collection('invoices').doc(inv.id).get();
      expect(doc.data()!['memberAddress'], '10 Rue de Carthage, Tunis');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // saveInvoiceSettings — fiscal fields
  // ══════════════════════════════════════════════════════════════════════════

  group('saveInvoiceSettings — fiscal', () {
    test('persists fiscal identity fields', () async {
      await sut.saveInvoiceSettings(
        prefix: 'INV-',
        startNumber: 1,
        padding: 4,
        companyName: 'Carthage CrossFit',
        companyAddress: 'Tunis',
        matriculeFiscal: '1234567/A/M/000',
        stampDuty: 1.0,
        defaultVatRate: 19,
      );

      final loaded = await sut.getInvoiceSettings();
      expect(loaded.companyName, 'Carthage CrossFit');
      expect(loaded.companyAddress, 'Tunis');
      expect(loaded.matriculeFiscal, '1234567/A/M/000');
      expect(loaded.stampDuty, 1.0);
      expect(loaded.defaultVatRate, 19);
    });

    test('merges fiscal fields without clobbering the counter', () async {
      await _seedSettings(db, nextSequence: 9, startNumber: 1);

      await sut.saveInvoiceSettings(
        prefix: 'INV-',
        startNumber: 1,
        padding: 4,
        companyName: 'Carthage CrossFit',
      );

      final loaded = await sut.getInvoiceSettings();
      expect(loaded.companyName, 'Carthage CrossFit');
      expect(loaded.nextSequence, 9); // preserved
    });
  });
}
