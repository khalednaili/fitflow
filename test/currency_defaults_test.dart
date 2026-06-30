import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/invoice.dart';
import 'package:fit_flow/models/membership_plan.dart';
import 'package:fit_flow/models/user_subscription.dart';
import 'package:fit_flow/utils/currency.dart';

/// Regression tests for the currency-default mismatch: every money-bearing
/// model must fall back to [Currency.defaultCode] (TND) when a document omits
/// the `currency` field — previously some defaulted to EUR.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  Future<DocumentSnapshot<Map<String, dynamic>>> writeAndRead(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final ref = db.collection(collection).doc('d1');
    await ref.set(data);
    return ref.get();
  }

  group('MembershipPlan.fromSnapshot', () {
    test('defaults currency to TND when missing', () async {
      final snap = await writeAndRead('membership_plans', {'name': 'Basic'});
      expect(MembershipPlan.fromSnapshot(snap).currency, Currency.defaultCode);
    });

    test('preserves an explicit currency', () async {
      final snap =
          await writeAndRead('membership_plans', {'currency': 'EUR'});
      expect(MembershipPlan.fromSnapshot(snap).currency, 'EUR');
    });
  });

  group('UserSubscription.fromSnapshot', () {
    test('defaults currency to TND when missing', () async {
      final snap = await writeAndRead('user_subscriptions', {
        'userId': 'u1',
        'planId': 'p1',
        'totalAmount': 100,
        'amountPaid': 0,
        'status': 'pending',
      });
      expect(UserSubscription.fromSnapshot(snap).currency, Currency.defaultCode);
    });

    test('preserves an explicit currency', () async {
      final snap = await writeAndRead('user_subscriptions', {
        'userId': 'u1',
        'planId': 'p1',
        'currency': 'USD',
        'status': 'pending',
      });
      expect(UserSubscription.fromSnapshot(snap).currency, 'USD');
    });
  });

  group('Invoice.fromSnapshot', () {
    test('defaults currency to TND when missing', () async {
      final snap = await writeAndRead('invoices', {
        'invoiceNumber': 'INV-1',
        'totalAmount': 100,
        'amountPaid': 0,
        'status': 'unpaid',
      });
      expect(Invoice.fromSnapshot(snap).currency, Currency.defaultCode);
    });

    test('preserves an explicit currency', () async {
      final snap = await writeAndRead('invoices', {
        'invoiceNumber': 'INV-1',
        'currency': 'GBP',
        'status': 'unpaid',
      });
      expect(Invoice.fromSnapshot(snap).currency, 'GBP');
    });
  });

  group('InvoiceItem.fromMap', () {
    test('defaults currency to TND when missing', () {
      final item = InvoiceItem.fromMap({'description': 'Plan', 'amount': 50});
      expect(item.currency, Currency.defaultCode);
    });

    test('preserves an explicit currency', () {
      final item = InvoiceItem.fromMap({'amount': 50, 'currency': 'EUR'});
      expect(item.currency, 'EUR');
    });
  });
}
