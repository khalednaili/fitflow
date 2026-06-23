import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/user_subscription.dart';
import 'package:fit_flow/services/subscription_service.dart';

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

extension _Setup on FakeFirebaseFirestore {
  Future<void> createUserDoc(String userId) =>
      collection('users').doc(userId).set({
        'displayName': userId,
        'email': '$userId@test.com',
      });

  Future<void> createSubDoc({
    required String userId,
    required String planId,
    required String status,
    int totalAmount = 100,
    int amountPaid = 0,
    List<Map<String, dynamic>> paymentHistory = const [],
  }) {
    final docId = '${userId}_$planId';
    return collection('user_subscriptions').doc(docId).set({
      'gymId': '',
      'userId': userId,
      'planId': planId,
      'totalAmount': totalAmount,
      'amountPaid': amountPaid,
      'currency': 'EUR',
      'status': status,
      'startDate': Timestamp.fromDate(DateTime(2025)),
      'endDate': Timestamp.fromDate(DateTime(2025, 12, 31)),
      'paymentHistory': paymentHistory,
      'updatedAt': Timestamp.now(),
    });
  }
}

SubscriptionService _sut(FakeFirebaseFirestore db) =>
    SubscriptionService(gymId: 'gym1', firestore: db);

final _start = DateTime(2025, 1, 1);
final _end = DateTime(2025, 12, 31);

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

void main() {
  late FakeFirebaseFirestore db;
  late SubscriptionService sut;

  setUp(() {
    db = FakeFirebaseFirestore();
    sut = _sut(db);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 1. assignOfferAtomic — happy path
  // ══════════════════════════════════════════════════════════════════════════
  group('1 • assignOfferAtomic — happy path', () {
    const userId = 'u1';
    const planId = 'plan_a';

    setUp(() => db.createUserDoc(userId));

    test('creates user_subscriptions doc with correct fields', () async {
      await sut.assignOfferAtomic(
        userId: userId,
        planId: planId,
        totalAmount: 120,
        currency: 'EUR',
        startDate: _start,
        endDate: _end,
        initialAmountPaid: 60,
        initialPaymentMethod: 'card',
        initialPaymentNotes: 'first instalment',
      );

      final snap = await db
          .collection('user_subscriptions')
          .doc('${userId}_$planId')
          .get();
      expect(snap.exists, isTrue);

      final data = snap.data()!;
      expect(data['userId'], userId);
      expect(data['planId'], planId);
      expect(data['totalAmount'], 120);
      expect(data['amountPaid'], 60);
      expect(data['currency'], 'EUR');
      expect(data['status'], 'active');
      expect((data['startDate'] as Timestamp).toDate(), _start);
      expect((data['endDate'] as Timestamp).toDate(), _end);
      expect(data['gymId'], 'gym1');

      final history = data['paymentHistory'] as List;
      expect(history, hasLength(1));
      expect(history.first['amount'], 60);
      expect(history.first['method'], 'card');
      expect(history.first['notes'], 'first instalment');
    });

    test('updates users doc with planId, status and dates', () async {
      await sut.assignOfferAtomic(
        userId: userId,
        planId: planId,
        totalAmount: 100,
        currency: 'EUR',
        startDate: _start,
        endDate: _end,
      );

      final userSnap = await db.collection('users').doc(userId).get();
      final data = userSnap.data()!;
      expect(data['membershipPlanId'], planId);
      expect(data['subscriptionStatus'], 'active');
      expect((data['offerStartAt'] as Timestamp).toDate(), _start);
      expect((data['offerEndAt'] as Timestamp).toDate(), _end);
    });

    test('no initial payment → paymentHistory is empty', () async {
      await sut.assignOfferAtomic(
        userId: userId,
        planId: planId,
        totalAmount: 100,
        currency: 'EUR',
        startDate: _start,
        endDate: _end,
        initialAmountPaid: 0,
      );

      final snap = await db
          .collection('user_subscriptions')
          .doc('${userId}_$planId')
          .get();
      final history = snap.data()!['paymentHistory'] as List;
      expect(history, isEmpty);
    });

    test('initialAmountPaid is clamped to totalAmount', () async {
      await sut.assignOfferAtomic(
        userId: userId,
        planId: planId,
        totalAmount: 100,
        currency: 'EUR',
        startDate: _start,
        endDate: _end,
        initialAmountPaid: 999, // over total
      );

      final snap = await db
          .collection('user_subscriptions')
          .doc('${userId}_$planId')
          .get();
      expect(snap.data()!['amountPaid'], 100);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 2. assignOfferAtomic — duplicate-offer guard
  // ══════════════════════════════════════════════════════════════════════════
  group('2 • assignOfferAtomic — duplicate-offer guard', () {
    const userId = 'u2';
    const planId = 'plan_b';

    setUp(() async {
      await db.createUserDoc(userId);
    });

    test('throws when member already has an active subscription', () async {
      await db.createSubDoc(
          userId: userId, planId: planId, status: 'active');

      await expectLater(
        sut.assignOfferAtomic(
          userId: userId,
          planId: planId,
          totalAmount: 100,
          currency: 'EUR',
          startDate: _start,
          endDate: _end,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('already has an active subscription'),
        )),
      );
    });

    test('allows re-assigning a cancelled subscription', () async {
      await db.createSubDoc(
          userId: userId, planId: planId, status: 'cancelled');

      await expectLater(
        sut.assignOfferAtomic(
          userId: userId,
          planId: planId,
          totalAmount: 100,
          currency: 'EUR',
          startDate: _start,
          endDate: _end,
        ),
        completes,
      );
    });

    test('allows assigning a different plan when one is already active',
        () async {
      await db.createSubDoc(
          userId: userId, planId: 'plan_other', status: 'active');

      await expectLater(
        sut.assignOfferAtomic(
          userId: userId,
          planId: planId, // different plan
          totalAmount: 100,
          currency: 'EUR',
          startDate: _start,
          endDate: _end,
        ),
        completes,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3. recordPayment — validations
  // ══════════════════════════════════════════════════════════════════════════
  group('3 • recordPayment — validations', () {
    const userId = 'u3';
    const planId = 'plan_c';
    final subId = '${userId}_$planId';

    setUp(() => db.createSubDoc(
        userId: userId, planId: planId, status: 'active',
        totalAmount: 200, amountPaid: 50));

    test('throws when subscription does not exist', () async {
      await expectLater(
        sut.recordPayment(
            subscriptionId: 'nonexistent',
            amount: 50,
            method: 'cash',
            notes: ''),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('not found'))),
      );
    });

    test('throws when amount is zero', () async {
      await expectLater(
        sut.recordPayment(
            subscriptionId: subId, amount: 0, method: 'cash', notes: ''),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('greater than zero'))),
      );
    });

    test('throws when amount is negative', () async {
      await expectLater(
        sut.recordPayment(
            subscriptionId: subId, amount: -10, method: 'cash', notes: ''),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('greater than zero'))),
      );
    });

    test('throws when payment exceeds remaining amount', () async {
      // remaining = 200 - 50 = 150; paying 200 → error
      await expectLater(
        sut.recordPayment(
            subscriptionId: subId, amount: 200, method: 'cash', notes: ''),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('exceeds'))),
      );
    });

    test('throws when subscription is already fully paid', () async {
      await db.createSubDoc(
          userId: 'u3_full', planId: 'plan_full', status: 'active',
          totalAmount: 100, amountPaid: 100);

      await expectLater(
        sut.recordPayment(
            subscriptionId: 'u3_full_plan_full',
            amount: 1,
            method: 'cash',
            notes: ''),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('fully paid'))),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 4. recordPayment — correct state updates
  // ══════════════════════════════════════════════════════════════════════════
  group('4 • recordPayment — state updates', () {
    const userId = 'u4';
    const planId = 'plan_d';
    final subId = '${userId}_$planId';

    setUp(() => db.createSubDoc(
        userId: userId, planId: planId, status: 'active',
        totalAmount: 300, amountPaid: 100));

    test('increments amountPaid correctly', () async {
      await sut.recordPayment(
          subscriptionId: subId, amount: 80, method: 'cash', notes: '');

      final snap = await db
          .collection('user_subscriptions')
          .doc(subId)
          .get();
      expect(snap.data()!['amountPaid'], 180);
    });

    test('appends entry to paymentHistory', () async {
      await sut.recordPayment(
          subscriptionId: subId,
          amount: 50,
          method: 'transfer',
          notes: 'monthly');

      final snap = await db
          .collection('user_subscriptions')
          .doc(subId)
          .get();
      final history = snap.data()!['paymentHistory'] as List;
      expect(history, hasLength(1));
      expect(history.first['amount'], 50);
      expect(history.first['method'], 'transfer');
      expect(history.first['notes'], 'monthly');
    });

    test('two sequential payments accumulate correctly', () async {
      await sut.recordPayment(
          subscriptionId: subId, amount: 50, method: 'cash', notes: 'p1');
      await sut.recordPayment(
          subscriptionId: subId, amount: 70, method: 'card', notes: 'p2');

      final snap = await db
          .collection('user_subscriptions')
          .doc(subId)
          .get();
      expect(snap.data()!['amountPaid'], 220); // 100 + 50 + 70
      final history = snap.data()!['paymentHistory'] as List;
      expect(history, hasLength(2));
    });

    test('exact remaining amount completes payment successfully', () async {
      // remaining = 300 - 100 = 200; pay exactly 200
      await expectLater(
        sut.recordPayment(
            subscriptionId: subId, amount: 200, method: 'cash', notes: ''),
        completes,
      );
      final snap = await db
          .collection('user_subscriptions')
          .doc(subId)
          .get();
      expect(snap.data()!['amountPaid'], 300);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 5. paymentStatus computed getter
  // ══════════════════════════════════════════════════════════════════════════
  group('5 • paymentStatus getter', () {
    UserSubscription _sub({required int total, required int paid}) =>
        UserSubscription(
          id: 'x',
          userId: 'u',
          planId: 'p',
          totalAmount: total,
          amountPaid: paid,
          currency: 'EUR',
          status: 'active',
          startDate: _start,
          endDate: _end,
          paymentHistory: const [],
        );

    test('returns "paid" when amountPaid == totalAmount', () {
      expect(_sub(total: 100, paid: 100).paymentStatus, 'paid');
    });

    test('returns "paid" when totalAmount is zero', () {
      expect(_sub(total: 0, paid: 0).paymentStatus, 'paid');
    });

    test('returns "partial" when 0 < amountPaid < totalAmount', () {
      expect(_sub(total: 100, paid: 50).paymentStatus, 'partial');
      expect(_sub(total: 100, paid: 1).paymentStatus, 'partial');
      expect(_sub(total: 100, paid: 99).paymentStatus, 'partial');
    });

    test('returns "unpaid" when amountPaid is zero', () {
      expect(_sub(total: 100, paid: 0).paymentStatus, 'unpaid');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 6. assignOfferAtomic — atomicity verification
  // ══════════════════════════════════════════════════════════════════════════
  group('6 • assignOfferAtomic — both docs written', () {
    const userId = 'u6';
    const planId = 'plan_e';

    test('subscription doc AND user doc are both written', () async {
      await db.createUserDoc(userId);

      await sut.assignOfferAtomic(
        userId: userId,
        planId: planId,
        totalAmount: 150,
        currency: 'EUR',
        startDate: _start,
        endDate: _end,
        initialAmountPaid: 75,
      );

      // subscription doc exists
      final subSnap = await db
          .collection('user_subscriptions')
          .doc('${userId}_$planId')
          .get();
      expect(subSnap.exists, isTrue);
      expect(subSnap.data()!['status'], 'active');

      // user doc updated
      final userSnap = await db.collection('users').doc(userId).get();
      expect(userSnap.data()!['membershipPlanId'], planId);
      expect(userSnap.data()!['subscriptionStatus'], 'active');
      expect((userSnap.data()!['offerStartAt'] as Timestamp).toDate(), _start);
      expect((userSnap.data()!['offerEndAt'] as Timestamp).toDate(), _end);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 7. updateSubscriptionStatus
  // ══════════════════════════════════════════════════════════════════════════
  group('7 • updateSubscriptionStatus', () {
    const userId = 'u7';
    const planId = 'plan_f';
    final subId = '${userId}_$planId';

    setUp(() =>
        db.createSubDoc(userId: userId, planId: planId, status: 'active'));

    test('changes status to cancelled', () async {
      await sut.updateSubscriptionStatus(
          subscriptionId: subId, status: 'cancelled');

      final snap = await db
          .collection('user_subscriptions')
          .doc(subId)
          .get();
      expect(snap.data()!['status'], 'cancelled');
    });

    test('re-activates a cancelled subscription', () async {
      await db.createSubDoc(
          userId: 'u7b', planId: planId, status: 'cancelled');
      await sut.updateSubscriptionStatus(
          subscriptionId: 'u7b_$planId', status: 'active');

      final snap = await db
          .collection('user_subscriptions')
          .doc('u7b_$planId')
          .get();
      expect(snap.data()!['status'], 'active');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 8. unassignOffer — atomic batch
  // ══════════════════════════════════════════════════════════════════════════
  group('8 • unassignOffer', () {
    const userId = 'u8';
    const planId = 'plan_g';
    final subId = '${userId}_$planId';

    setUp(() async {
      await db.createUserDoc(userId);
      await db.createSubDoc(userId: userId, planId: planId, status: 'active');
    });

    test('deletes subscription doc', () async {
      await sut.unassignOffer(subscriptionId: subId, userId: userId);

      final snap = await db
          .collection('user_subscriptions')
          .doc(subId)
          .get();
      expect(snap.exists, isFalse);
    });

    test('resets user subscriptionStatus to none', () async {
      await sut.unassignOffer(subscriptionId: subId, userId: userId);

      final userSnap = await db.collection('users').doc(userId).get();
      expect(userSnap.data()!['subscriptionStatus'], 'none');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 9. extendOffer
  // ══════════════════════════════════════════════════════════════════════════
  group('9 • extendOffer', () {
    const userId = 'u9';
    const planId = 'plan_h';
    final subId = '${userId}_$planId';

    setUp(() => db.createSubDoc(
        userId: userId, planId: planId, status: 'cancelled'));

    test('updates endDate and re-activates', () async {
      final newEnd = DateTime(2026, 6, 30);
      await sut.extendOffer(subscriptionId: subId, newEndDate: newEnd);

      final snap = await db
          .collection('user_subscriptions')
          .doc(subId)
          .get();
      expect((snap.data()!['endDate'] as Timestamp).toDate(), newEnd);
      expect(snap.data()!['status'], 'active');
    });
  });
}
