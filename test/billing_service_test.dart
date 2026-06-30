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
      expect(invoice.currency, 'EUR');
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
        (
          date: now.subtract(const Duration(days: 10)),
          amount: 300,
          method: 'cash'
        ),
      ]);

      final stats = await sut.computeRevenueStats();
      expect(stats.revenueThisMonth, greaterThanOrEqualTo(300));
    });

    test('excludes payments before the from date', () async {
      final oldPaymentDate = now.subtract(const Duration(days: 90));
      final recentPaymentDate = now.subtract(const Duration(days: 5));

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
}
