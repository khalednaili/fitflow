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
    db
        .collection('settings')
        .doc('invoiceSettings_$gymId')
        .set({
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

      final snap = await db
          .collection('settings')
          .doc('invoiceSettings_gym1')
          .get();
      final data = snap.data()!;

      expect(data['prefix'], '2026-06-');
      expect(data['startNumber'], 1);
      expect(data['padding'], 5);
      expect(data['gymId'], 'gym1');
    });

    test('does not reset counter when resetCounter is false and startNumber unchanged', () async {
      await _seedSettings(db, nextSequence: 8, startNumber: 1);

      await sut.saveInvoiceSettings(
        prefix: 'INV-',
        startNumber: 1,
        padding: 4,
        resetCounter: false,
      );

      final snap = await db
          .collection('settings')
          .doc('invoiceSettings_gym1')
          .get();
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

      final snap = await db
          .collection('settings')
          .doc('invoiceSettings_gym1')
          .get();
      expect(snap.data()!['nextSequence'], 1);
    });

    test('resets counter when startNumber changes', () async {
      await _seedSettings(db, nextSequence: 8, startNumber: 1);

      await sut.saveInvoiceSettings(
        prefix: 'INV-',
        startNumber: 100,
        padding: 4,
      );

      final snap = await db
          .collection('settings')
          .doc('invoiceSettings_gym1')
          .get();
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
      final snap = await db
          .collection('settings')
          .doc('invoiceSettings_gym1')
          .get();
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
      final snap = await db
          .collection('settings')
          .doc('invoiceSettings_gym1')
          .get();
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
    Future<void> _seedInvoice(
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
      await _seedInvoice(db,
          gymId: 'gym1',
          invoiceNumber: 'INV-0001',
          issuedAt: DateTime(2026, 1, 1));
      await _seedInvoice(db,
          gymId: 'other_gym',
          invoiceNumber: 'INV-9999',
          issuedAt: DateTime(2026, 1, 2));

      final invoices = await sut.streamInvoices().first;

      expect(invoices.length, 1);
      expect(invoices.first.invoiceNumber, 'INV-0001');
    });

    test('returns all invoices when gymId is empty', () async {
      final sutNoGym = BillingService(gymId: '', firestore: db);

      await _seedInvoice(db,
          gymId: 'gym1',
          invoiceNumber: 'A-001',
          issuedAt: DateTime(2026, 1, 1));
      await _seedInvoice(db,
          gymId: 'gym2',
          invoiceNumber: 'B-001',
          issuedAt: DateTime(2026, 1, 2));

      final invoices = await sutNoGym.streamInvoices().first;

      expect(invoices.length, 2);
    });

    test('emits updated list when a new invoice is added', () async {
      await _seedInvoice(db,
          gymId: 'gym1',
          invoiceNumber: 'INV-0001',
          issuedAt: DateTime(2026, 1, 1));

      final stream = sut.streamInvoices();
      final first = await stream.first;
      expect(first.length, 1);

      await _seedInvoice(db,
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
        'status': 'partial',
        'issuedAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'dueDate': Timestamp.fromDate(DateTime(2026, 7, 1)),
        'notes': 'First instalment',
        'items': [
          {'description': 'Basic plan', 'amount': 1200, 'currency': 'EUR'},
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
      });

      final snap =
          await db.collection('invoices').doc(ref.id).get();
      final invoice = Invoice.fromSnapshot(snap);

      expect(invoice.invoiceNumber, '2026-06-0001');
      expect(invoice.totalAmount, 1200);
      expect(invoice.amountPaid, 600);
      expect(invoice.remainingAmount, 600);
      expect(invoice.status, 'partial');
      expect(invoice.items.length, 1);
      expect(invoice.payments.length, 1);
      expect(invoice.dueDate, isNotNull);
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
    });
  });
}
