import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/services/booking_service.dart';

// ────────────────────────────────────────────────────────────────────────────
// Shared date constants
// ────────────────────────────────────────────────────────────────────────────

/// Far-future Monday (2099-06-01). Use with bypassDailyLimit: true.
final _futureClass = DateTime(2099, 6, 1, 10, 0);

/// Tomorrow — safe for bypassDailyLimit: false (class hasn't started).
DateTime get _tomorrow => DateTime.now().add(const Duration(days: 1));

/// Class in the past — triggers "already started" error.
DateTime get _pastClass => DateTime.now().subtract(const Duration(hours: 1));

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

extension _Setup on FakeFirebaseFirestore {
  Future<void> createPlan({
    required String planId,
    required String offerType,
    int checkinsPerWeek = 0,
    int checkinsPerMonth = 0,
    int totalCheckins = 0,
  }) =>
      collection('membership_plans').doc(planId).set({
        'name': planId,
        'offerType': offerType,
        'checkinsPerWeek': checkinsPerWeek,
        'checkinsPerMonth': checkinsPerMonth,
        'totalCheckins': totalCheckins,
        'price': 0,
        'currency': 'EUR',
        'active': true,
      });

  Future<void> createClass({
    required String classId,
    required DateTime startTime,
    DateTime? endTime,
    List<String> requiredOfferPlanIds = const [],
    String legacyRequiredOfferPlanId = '',
    int capacity = 10,
    int bookedCount = 0,
    int waitlistCount = 0,
    String classTypeId = '',
    bool dropInEnabled = false,
    double dropInPrice = 0.0,
  }) =>
      collection('classes').doc(classId).set({
        'title': classId,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(
            endTime ?? startTime.add(const Duration(hours: 1))),
        'capacity': capacity,
        'bookedCount': bookedCount,
        'waitlistCount': waitlistCount,
        'requiredOfferPlanIds': requiredOfferPlanIds,
        if (legacyRequiredOfferPlanId.isNotEmpty)
          'requiredOfferPlanId': legacyRequiredOfferPlanId,
        if (classTypeId.isNotEmpty) 'classTypeId': classTypeId,
        'dropInEnabled': dropInEnabled,
        'dropInPrice': dropInPrice,
      });

  Future<void> createUser({
    required String userId,
    String displayName = 'Test User',
    // Legacy offer fields
    String membershipPlanId = '',
    String subscriptionStatus = '',
    DateTime? offerStartAt,
    DateTime? offerEndAt,
  }) =>
      collection('users').doc(userId).set({
        'displayName': displayName,
        'email': '$userId@example.com',
        if (membershipPlanId.isNotEmpty) 'membershipPlanId': membershipPlanId,
        if (subscriptionStatus.isNotEmpty)
          'subscriptionStatus': subscriptionStatus,
        if (offerStartAt != null)
          'offerStartAt': Timestamp.fromDate(offerStartAt),
        if (offerEndAt != null) 'offerEndAt': Timestamp.fromDate(offerEndAt),
      });

  Future<void> createSubscription({
    required String userId,
    required String planId,
    String status = 'active',
    DateTime? startDate,
    DateTime? endDate,
  }) =>
      collection('user_subscriptions').doc('${userId}_$planId').set({
        'userId': userId,
        'planId': planId,
        'status': status,
        'startDate': Timestamp.fromDate(startDate ?? DateTime(2000)),
        if (endDate != null) 'endDate': Timestamp.fromDate(endDate),
        'totalAmount': 0,
        'amountPaid': 0,
        'currency': 'EUR',
      });

  Future<DocumentReference<Map<String, dynamic>>> createBookingDoc({
    required String userId,
    required String classId,
    required DateTime bookingDate,
    String usedPlanId = '',
    bool isDropIn = false,
    String dropInPaymentStatus = 'pending',
    double dropInPrice = 0.0,
    DateTime? classStartTime,
    DateTime? classEndTime,
    String classTypeId = '',
  }) =>
      collection('bookings').add({
        'userId': userId,
        'classId': classId,
        'gymId': '',
        'createdAt': Timestamp.now(),
        'bookingDate': Timestamp.fromDate(
            DateTime(bookingDate.year, bookingDate.month, bookingDate.day)),
        'memberName': 'Test User',
        'isDropIn': isDropIn,
        'dropInPaymentStatus': dropInPaymentStatus,
        'dropInPrice': dropInPrice,
        'usedPlanId': usedPlanId,
        if (classStartTime != null)
          'classStartTime': Timestamp.fromDate(classStartTime),
        if (classEndTime != null)
          'classEndTime': Timestamp.fromDate(classEndTime),
        if (classTypeId.isNotEmpty) 'classTypeId': classTypeId,
      });

  Future<void> createWaitlistEntry({
    required String userId,
    required String classId,
    DateTime? createdAt,
    bool isDropIn = false,
    String dropInPaymentStatus = 'pending',
    double dropInPrice = 0.0,
  }) =>
      collection('waitlists').add({
        'userId': userId,
        'classId': classId,
        'gymId': '',
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt)
            : Timestamp.now(),
        'memberName': 'Test User',
        if (isDropIn) ...{
          'isDropIn': true,
          'dropInPaymentStatus': dropInPaymentStatus,
          'dropInPrice': dropInPrice,
        },
      });

  Future<void> setBookingRules({
    int maxBookingsPerDay = 0,
    int minAdvanceBookingMinutes = 0,
    int lateCancellationMinutes = 0,
    bool preventOverlappingBookings = false,
    bool preventSameClassTypePerDay = false,
    bool hideClassesWithoutSubscription = false,
  }) =>
      collection('settings').doc('bookingRules').set({
        'maxBookingsPerDay': maxBookingsPerDay,
        'minAdvanceBookingMinutes': minAdvanceBookingMinutes,
        'lateCancellationMinutes': lateCancellationMinutes,
        'preventOverlappingBookings': preventOverlappingBookings,
        'preventSameClassTypePerDay': preventSameClassTypePerDay,
        'hideClassesWithoutSubscription': hideClassesWithoutSubscription,
      });
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

void main() {
  late FakeFirebaseFirestore db;
  late BookingService sut;

  setUp(() {
    db = FakeFirebaseFirestore();
    sut = BookingService(gymId: '', firestore: db);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 1. DUAL-OFFER ISOLATION (Bug fixes)
  // ══════════════════════════════════════════════════════════════════════════
  group('1 • dual-offer isolation', () {
    const userId = 'u1';
    const skillsPlan = 'plan_skills';
    const punicPlan = 'plan_punic';
    const skillsClass = 'class_skills';
    const wodClass = 'class_wod';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: skillsPlan, offerType: 'limited_sessions', totalCheckins: 10);
      await db.createPlan(
          planId: punicPlan,
          offerType: 'weekly_recurring',
          checkinsPerWeek: 3);
      await db.createClass(
          classId: skillsClass,
          startTime: _futureClass,
          requiredOfferPlanIds: [skillsPlan]);
      await db.createClass(
          classId: wodClass,
          startTime: _futureClass,
          requiredOfferPlanIds: [punicPlan]);
      await db.createSubscription(userId: userId, planId: skillsPlan);
      await db.createSubscription(userId: userId, planId: punicPlan);
    });

    test('skills class booking stores usedPlanId = skillsPlan', () async {
      await sut.bookClass(
          userId: userId, classId: skillsClass, bypassDailyLimit: true);
      final snap = await db
          .collection('bookings')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: skillsClass)
          .get();
      expect(snap.docs.first.data()['usedPlanId'], skillsPlan);
    });

    test('WOD class booking stores usedPlanId = punicPlan', () async {
      await sut.bookClass(
          userId: userId, classId: wodClass, bypassDailyLimit: true);
      final snap = await db
          .collection('bookings')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: wodClass)
          .get();
      expect(snap.docs.first.data()['usedPlanId'], punicPlan);
    });

    test(
        '3 skills bookings this week do not consume punic quota — '
        '1st WOD is still allowed',
        () async {
      for (var i = 1; i <= 3; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'sk_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: skillsPlan);
      }
      final result = await sut.bookClass(
          userId: userId, classId: wodClass, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test(
        'mixed week (2 WOD + 3 skills) — 3rd WOD allowed because skills '
        'bookings do not eat into punic quota',
        () async {
      for (var i = 1; i <= 2; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'wod_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: punicPlan);
      }
      for (var i = 1; i <= 3; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'sk_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: skillsPlan);
      }
      final result = await sut.bookClass(
          userId: userId, classId: wodClass, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test('punic weekly limit enforced after 3 WOD bookings', () async {
      for (var i = 1; i <= 3; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'wod_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: punicPlan);
      }
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: wodClass, bypassDailyLimit: true),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), '', contains('Weekly limit reached'))),
      );
    });

    test(
        'skills pack exhausted (10/10) blocks skills class — '
        'WOD through punic still works',
        () async {
      for (var i = 1; i <= 10; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'sk_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: skillsPlan);
      }
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: skillsClass, bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('Session pack exhausted'))),
      );
      final result = await sut.bookClass(
          userId: userId, classId: wodClass, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test('a drop-in does not consume the weekly (punic) quota', () async {
      // 2 punic bookings + 1 drop-in this week → 3rd punic still allowed
      // because the drop-in must not count against the weekly limit.
      for (var i = 1; i <= 2; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'wod_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: punicPlan);
      }
      await db.createBookingDoc(
          userId: userId,
          classId: 'wod_dropin',
          bookingDate: _futureClass,
          isDropIn: true);
      final result = await sut.bookClass(
          userId: userId, classId: wodClass, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test('a drop-in does not consume the pack (skills) quota', () async {
      // 9 skills bookings + 1 drop-in → 10th skills still allowed.
      for (var i = 1; i <= 9; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'sk_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: skillsPlan);
      }
      await db.createBookingDoc(
          userId: userId,
          classId: 'sk_dropin',
          bookingDate: _futureClass,
          isDropIn: true);
      final result = await sut.bookClass(
          userId: userId, classId: skillsClass, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 2. ACCESS CONTROL
  // ══════════════════════════════════════════════════════════════════════════
  group('2 • access control', () {
    const userId = 'u2';
    const punicPlan = 'plan_punic2';
    const wodClass = 'class_wod2';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: punicPlan,
          offerType: 'weekly_recurring',
          checkinsPerWeek: 3);
      await db.createClass(
          classId: wodClass,
          startTime: _futureClass,
          requiredOfferPlanIds: [punicPlan]);
    });

    test('member with no subscription is blocked', () async {
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: wodClass, bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('active assigned offer'))),
      );
    });

    test('member with cancelled offer is blocked', () async {
      await db.createSubscription(
          userId: userId, planId: punicPlan, status: 'cancelled');
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: wodClass, bypassDailyLimit: true),
        throwsA(isA<Exception>()),
      );
    });

    test('member with wrong offer (not in requiredOfferPlanIds) is blocked',
        () async {
      await db.createPlan(planId: 'other_plan', offerType: 'limited_sessions');
      await db.createSubscription(userId: userId, planId: 'other_plan');
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: wodClass, bypassDailyLimit: true),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), '', contains('specific offers'))),
      );
    });

    test('member with correct offer is allowed', () async {
      await db.createSubscription(userId: userId, planId: punicPlan);
      final result = await sut.bookClass(
          userId: userId, classId: wodClass, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3. CLASS NOT FOUND
  // ══════════════════════════════════════════════════════════════════════════
  group('3 • class not found', () {
    test('throws when class document does not exist', () async {
      await db.createUser(userId: 'u3');
      await expectLater(
        () => sut.bookClass(
            userId: 'u3',
            classId: 'nonexistent',
            bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('does not exist anymore'))),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 4. DUPLICATE BOOKING
  // ══════════════════════════════════════════════════════════════════════════
  group('4 • duplicate booking prevention', () {
    const userId = 'u4';
    const planId = 'plan_dup';
    const classId = 'class_dup';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'weekly_recurring', checkinsPerWeek: 5);
      await db.createClass(classId: classId, startTime: _futureClass);
      await db.createSubscription(userId: userId, planId: planId);
    });

    test('booking the same class twice throws "already booked"', () async {
      await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: classId, bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('already booked this class'))),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 5. CAPACITY AND WAITLIST
  // ══════════════════════════════════════════════════════════════════════════
  group('5 • capacity and waitlist', () {
    const userId = 'u5';
    const planId = 'plan_cap';
    const classId = 'class_cap';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'weekly_recurring', checkinsPerWeek: 5);
      await db.createSubscription(userId: userId, planId: planId);
    });

    test('bookedCount incremented to 1 after successful booking', () async {
      await db.createClass(
          classId: classId, startTime: _futureClass, capacity: 10);
      await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      final snap = await db.collection('classes').doc(classId).get();
      expect(snap.data()!['bookedCount'], 1);
    });

    test('full class returns waitlisted and creates waitlist doc', () async {
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 1,
          bookedCount: 1);
      final result = await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      expect(result, BookingResult.waitlisted);
      final waitSnap = await db
          .collection('waitlists')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: classId)
          .get();
      expect(waitSnap.docs, hasLength(1));
    });

    test('full class increments waitlistCount', () async {
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 1,
          bookedCount: 1,
          waitlistCount: 2);
      await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      final snap = await db.collection('classes').doc(classId).get();
      expect(snap.data()!['waitlistCount'], 3);
    });

    test('already on waitlist throws error', () async {
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 1,
          bookedCount: 1);
      await db.createWaitlistEntry(userId: userId, classId: classId);
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: classId, bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('already on the waitlist'))),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 6. OFFER DATE BOUNDARIES
  // ══════════════════════════════════════════════════════════════════════════
  group('6 • offer date boundaries', () {
    const userId = 'u6';
    const planId = 'plan_dates';
    const classId = 'class_dates';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'weekly_recurring', checkinsPerWeek: 5);
      await db.createClass(classId: classId, startTime: _futureClass);
    });

    test('expired offer (endDate before class) blocks booking', () async {
      await db.createSubscription(
          userId: userId,
          planId: planId,
          endDate: DateTime(2020)); // well before _futureClass (2099)
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: classId, bypassDailyLimit: true),
        throwsA(isA<Exception>()),
      );
    });

    test('offer not yet started (startDate after class) blocks booking',
        () async {
      await db.createSubscription(
          userId: userId,
          planId: planId,
          startDate: DateTime(2199)); // after _futureClass (2099)
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: classId, bypassDailyLimit: true),
        throwsA(isA<Exception>()),
      );
    });

    test('class date exactly on offer startDate is allowed', () async {
      await db.createSubscription(
          userId: userId,
          planId: planId,
          startDate: _futureClass); // same day as class
      final result = await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test('class date exactly on offer endDate is allowed', () async {
      await db.createSubscription(
          userId: userId,
          planId: planId,
          endDate: _futureClass); // same day as class
      final result = await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 7. LEGACY BACKWARD-COMPAT FIELDS
  // ══════════════════════════════════════════════════════════════════════════
  group('7 • legacy backward-compat', () {
    const userId = 'u7';
    const planId = 'plan_legacy';

    test(
        'class with legacy single requiredOfferPlanId (not array) '
        'is correctly enforced', () async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'weekly_recurring', checkinsPerWeek: 5);
      // Only the old singular field — no requiredOfferPlanIds array
      await db.createClass(
          classId: 'legacy_class',
          startTime: _futureClass,
          legacyRequiredOfferPlanId: planId);
      await db.createSubscription(userId: userId, planId: planId);

      final result = await sut.bookClass(
          userId: userId, classId: 'legacy_class', bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test(
        'class with legacy requiredOfferPlanId blocks member '
        'who has a different offer', () async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'weekly_recurring', checkinsPerWeek: 5);
      await db.createClass(
          classId: 'legacy_class2',
          startTime: _futureClass,
          legacyRequiredOfferPlanId: planId);
      await db.createSubscription(userId: userId, planId: 'wrong_plan');

      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: 'legacy_class2', bypassDailyLimit: true),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), '', contains('specific offers'))),
      );
    });

    test(
        'user with legacy membershipPlanId fields (no user_subscriptions doc) '
        'is allowed to book unrestricted class', () async {
      await db.createUser(
        userId: userId,
        membershipPlanId: planId,
        subscriptionStatus: 'active',
        offerStartAt: DateTime(2000),
        offerEndAt: DateTime(2200),
      );
      // No user_subscriptions doc — purely legacy fields
      await db.createClass(
          classId: 'legacy_open', startTime: _futureClass);

      final result = await sut.bookClass(
          userId: userId, classId: 'legacy_open', bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 8. BOOKING RULES  (bypassDailyLimit: false)
  // ══════════════════════════════════════════════════════════════════════════
  group('8 • booking rules', () {
    const userId = 'u8';
    const planId = 'plan_rules';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'weekly_recurring', checkinsPerWeek: 10);
      await db.createSubscription(userId: userId, planId: planId);
    });

    test('booking a class that has already started throws', () async {
      await db.createClass(classId: 'past_class', startTime: _pastClass);
      await expectLater(
        () => sut.bookClass(
            userId: userId,
            classId: 'past_class',
            bypassDailyLimit: false),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('already started'))),
      );
    });

    test('minAdvanceBookingMinutes blocks booking too far in advance', () async {
      await db.setBookingRules(minAdvanceBookingMinutes: 60);
      // _futureClass is in 2099 — way more than 60 minutes away
      await db.createClass(classId: 'advance_class', startTime: _futureClass);
      await expectLater(
        () => sut.bookClass(
            userId: userId,
            classId: 'advance_class',
            bypassDailyLimit: false),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), '', contains('Booking opens'))),
      );
    });

    test('minAdvanceBookingMinutes = 0 (disabled) allows booking far in advance',
        () async {
      await db.setBookingRules(minAdvanceBookingMinutes: 0);
      await db.createClass(classId: 'open_advance', startTime: _tomorrow);
      final result = await sut.bookClass(
          userId: userId, classId: 'open_advance', bypassDailyLimit: false);
      expect(result, BookingResult.booked);
    });

    test('daily limit reached blocks booking', () async {
      await db.setBookingRules(maxBookingsPerDay: 2);
      await db.createClass(classId: 'daily_class', startTime: _tomorrow);
      // Two bookings already exist for tomorrow
      for (var i = 1; i <= 2; i++) {
        await db.createBookingDoc(
            userId: userId, classId: 'other_$i', bookingDate: _tomorrow);
      }
      await expectLater(
        () => sut.bookClass(
            userId: userId,
            classId: 'daily_class',
            bypassDailyLimit: false),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('Daily booking limit reached'))),
      );
    });

    test('daily limit = 0 (disabled) does not cap bookings', () async {
      await db.setBookingRules(maxBookingsPerDay: 0);
      await db.createClass(classId: 'no_cap_class', startTime: _tomorrow);
      for (var i = 1; i <= 5; i++) {
        await db.createBookingDoc(
            userId: userId, classId: 'other_$i', bookingDate: _tomorrow);
      }
      final result = await sut.bookClass(
          userId: userId,
          classId: 'no_cap_class',
          bypassDailyLimit: false);
      expect(result, BookingResult.booked);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 9. MONTHLY RECURRING LIMIT
  // ══════════════════════════════════════════════════════════════════════════
  group('9 • monthly recurring limit', () {
    const userId = 'u9';
    const planId = 'plan_monthly';
    const classId = 'class_monthly';
    // Fixed month: June 2099
    final june = DateTime(2099, 6, 15, 10, 0);
    final may = DateTime(2099, 5, 20, 10, 0);

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId,
          offerType: 'monthly_recurring',
          checkinsPerMonth: 8);
      await db.createClass(classId: classId, startTime: june);
      await db.createSubscription(userId: userId, planId: planId);
    });

    test('monthly limit enforced after 8 bookings in same month', () async {
      for (var i = 1; i <= 8; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'june_prev_$i',
            bookingDate: june,
            usedPlanId: planId);
      }
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: classId, bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('Monthly limit reached'))),
      );
    });

    test('bookings in a previous month do not count toward current month limit',
        () async {
      // 8 bookings in May — should not affect June quota
      for (var i = 1; i <= 8; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'may_prev_$i',
            bookingDate: may,
            usedPlanId: planId);
      }
      final result = await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test('7 bookings this month still allows one more', () async {
      for (var i = 1; i <= 7; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'june_prev_$i',
            bookingDate: june,
            usedPlanId: planId);
      }
      final result = await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test('a drop-in this month does NOT count toward the offer limit',
        () async {
      // A paid drop-in (empty usedPlanId, isDropIn=true) must not consume an
      // offer slot. 7 real offer bookings + 1 drop-in = 8 docs this month, but
      // only the 7 offer bookings count, so an 8th offer booking is allowed.
      await db.createBookingDoc(
          userId: userId,
          classId: 'june_dropin',
          bookingDate: june,
          isDropIn: true);
      for (var i = 1; i <= 7; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'june_offer_$i',
            bookingDate: june,
            usedPlanId: planId);
      }
      final result = await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 10. DROP-IN BOOKINGS
  // ══════════════════════════════════════════════════════════════════════════
  group('10 • drop-in bookings', () {
    const userId = 'u10';
    const classId = 'class_dropin';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          requiredOfferPlanIds: ['some_exclusive_plan'],
          dropInEnabled: true,
          dropInPrice: 15.0);
    });

    test('drop-in bypasses offer requirement — no subscription needed',
        () async {
      // User has NO subscription at all
      final result = await sut.bookClass(
          userId: userId,
          classId: classId,
          isDropIn: true,
          bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test('drop-in booking stores isDropIn = true and empty usedPlanId',
        () async {
      await sut.bookClass(
          userId: userId,
          classId: classId,
          isDropIn: true,
          dropInPaymentStatus: 'paid',
          bypassDailyLimit: true);
      final snap = await db
          .collection('bookings')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: classId)
          .get();
      expect(snap.docs.first.data()['isDropIn'], isTrue);
      expect(snap.docs.first.data()['usedPlanId'], '');
      expect(snap.docs.first.data()['dropInPaymentStatus'], 'paid');
    });

    test('drop-in booking snapshots the class price onto the booking',
        () async {
      await sut.bookClass(
          userId: userId,
          classId: classId,
          isDropIn: true,
          bypassDailyLimit: true);
      final snap = await db
          .collection('bookings')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: classId)
          .get();
      expect((snap.docs.first.data()['dropInPrice'] as num).toDouble(), 15.0);
    });

    test('drop-in is rejected when the class has drop-ins disabled', () async {
      await db.createClass(
          classId: 'no_dropin',
          startTime: _futureClass,
          dropInEnabled: false,
          dropInPrice: 15.0);
      await expectLater(
        sut.bookClass(
            userId: userId,
            classId: 'no_dropin',
            isDropIn: true,
            bypassDailyLimit: true),
        throwsA(isA<Exception>()),
      );
    });

    test('drop-in is rejected when the class has no price set', () async {
      await db.createClass(
          classId: 'free_dropin',
          startTime: _futureClass,
          dropInEnabled: true,
          dropInPrice: 0.0);
      await expectLater(
        sut.bookClass(
            userId: userId,
            classId: 'free_dropin',
            isDropIn: true,
            bypassDailyLimit: true),
        throwsA(isA<Exception>()),
      );
    });

    test('drop-in into a full class waitlists and preserves drop-in fields',
        () async {
      await db.createClass(
          classId: 'full_dropin',
          startTime: _futureClass,
          capacity: 1,
          bookedCount: 1,
          dropInEnabled: true,
          dropInPrice: 15.0);

      final result = await sut.bookClass(
          userId: userId,
          classId: 'full_dropin',
          isDropIn: true,
          bypassDailyLimit: true);
      expect(result, BookingResult.waitlisted);

      final wl = await db
          .collection('waitlists')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: 'full_dropin')
          .get();
      expect(wl.docs, hasLength(1));
      expect(wl.docs.first.data()['isDropIn'], isTrue);
      expect((wl.docs.first.data()['dropInPrice'] as num).toDouble(), 15.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 11. UNRESTRICTED CLASS — usedPlanId stored
  // ══════════════════════════════════════════════════════════════════════════
  group('11 • unrestricted class — usedPlanId stored', () {
    const userId = 'u11';
    const planId = 'plan_open';
    const classId = 'class_open';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'weekly_recurring', checkinsPerWeek: 5);
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          requiredOfferPlanIds: []);
      await db.createSubscription(userId: userId, planId: planId);
    });

    test('usedPlanId is persisted even for unrestricted classes', () async {
      await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      final snap = await db
          .collection('bookings')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: classId)
          .get();
      expect(snap.docs.first.data()['usedPlanId'], planId);
    });

    test('weekly limit on open class counts only same-plan bookings', () async {
      // 4 bookings with same plan → 1 slot remaining
      for (var i = 1; i <= 4; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'open_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: planId);
      }
      final result = await sut.bookClass(
          userId: userId, classId: classId, bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test('weekly limit is enforced after 5 same-plan bookings', () async {
      for (var i = 1; i <= 5; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'open_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: planId);
      }
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: classId, bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('Weekly limit reached'))),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 12. CANCEL BOOKING
  // ══════════════════════════════════════════════════════════════════════════
  group('12 • cancel booking', () {
    const userId = 'u12';
    const planId = 'plan_cancel';
    const classId = 'class_cancel';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'weekly_recurring', checkinsPerWeek: 5);
      await db.createSubscription(userId: userId, planId: planId);
    });

    test('cancelling deletes booking doc and decrements bookedCount', () async {
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 10,
          bookedCount: 1);
      await db.createBookingDoc(
          userId: userId, classId: classId, bookingDate: _futureClass);

      await sut.cancelBooking(userId: userId, classId: classId);

      final bookings = await db
          .collection('bookings')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: classId)
          .get();
      expect(bookings.docs, isEmpty);

      final classSnap = await db.collection('classes').doc(classId).get();
      expect(classSnap.data()!['bookedCount'], 0);
    });

    test('cancelling a non-existent booking throws', () async {
      await db.createClass(classId: classId, startTime: _futureClass);
      await expectLater(
        () => sut.cancelBooking(userId: userId, classId: classId),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('No active booking found'))),
      );
    });

    test('cancelling far-future class does not create late-penalty record',
        () async {
      // lateCancellationMinutes = 60 but class is in 2099 (millions of mins away)
      await db.setBookingRules(lateCancellationMinutes: 60);
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 10,
          bookedCount: 1);
      await db.createBookingDoc(
          userId: userId, classId: classId, bookingDate: _futureClass);

      await sut.cancelBooking(userId: userId, classId: classId);

      final penalties =
          await db.collection('late_cancellations').get();
      expect(penalties.docs, isEmpty);
    });

    test('cancelling a PAID drop-in records a refund trace', () async {
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 10,
          bookedCount: 1);
      await db.createBookingDoc(
        userId: userId,
        classId: classId,
        bookingDate: _futureClass,
        isDropIn: true,
        dropInPaymentStatus: 'paid',
        dropInPrice: 15.0,
      );

      await sut.cancelBooking(userId: userId, classId: classId);

      final refunds = await db.collection('dropInRefunds').get();
      expect(refunds.docs, hasLength(1));
      final r = refunds.docs.first.data();
      expect(r['userId'], userId);
      expect(r['classId'], classId);
      expect((r['amount'] as num).toDouble(), 15.0);
      expect(r['status'], 'pending');
    });

    test('cancelling an UNPAID drop-in records no refund', () async {
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 10,
          bookedCount: 1);
      await db.createBookingDoc(
        userId: userId,
        classId: classId,
        bookingDate: _futureClass,
        isDropIn: true,
        dropInPaymentStatus: 'pending',
        dropInPrice: 15.0,
      );

      await sut.cancelBooking(userId: userId, classId: classId);

      final refunds = await db.collection('dropInRefunds').get();
      expect(refunds.docs, isEmpty);
    });

    test('cancelling a regular (non-drop-in) booking records no refund',
        () async {
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 10,
          bookedCount: 1);
      await db.createBookingDoc(
          userId: userId, classId: classId, bookingDate: _futureClass);

      await sut.cancelBooking(userId: userId, classId: classId);

      final refunds = await db.collection('dropInRefunds').get();
      expect(refunds.docs, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 13. CANCEL WITH WAITLIST PROMOTION
  // ══════════════════════════════════════════════════════════════════════════
  group('13 • cancel with waitlist promotion', () {
    const booker = 'u13a';
    const waiter = 'u13b';
    const classId = 'class_waitprom';

    setUp(() async {
      await db.createUser(userId: booker);
      await db.createUser(userId: waiter);
    });

    test(
        'cancelling promotes first waitlister: '
        'booking created, waitlist doc deleted, counts updated',
        () async {
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 1,
          bookedCount: 1,
          waitlistCount: 1);
      await db.createBookingDoc(
          userId: booker, classId: classId, bookingDate: _futureClass);
      await db.createWaitlistEntry(userId: waiter, classId: classId);

      await sut.cancelBooking(userId: booker, classId: classId);

      // Original booking deleted
      final bookerBookings = await db
          .collection('bookings')
          .where('userId', isEqualTo: booker)
          .where('classId', isEqualTo: classId)
          .get();
      expect(bookerBookings.docs, isEmpty);

      // Promoted user now has a booking
      final waiterBookings = await db
          .collection('bookings')
          .where('userId', isEqualTo: waiter)
          .where('classId', isEqualTo: classId)
          .get();
      expect(waiterBookings.docs, hasLength(1));

      // Waitlist entry deleted
      final waitlistSnap = await db
          .collection('waitlists')
          .where('userId', isEqualTo: waiter)
          .get();
      expect(waitlistSnap.docs, isEmpty);

      // bookedCount stays at 1 (removed 1, added promoted 1)
      final classSnap =
          await db.collection('classes').doc(classId).get();
      expect(classSnap.data()!['bookedCount'], 1);
      expect(classSnap.data()!['waitlistCount'], 0);
    });

    test('promoting a drop-in waitlister preserves its drop-in fields',
        () async {
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 1,
          bookedCount: 1,
          waitlistCount: 1);
      await db.createBookingDoc(
          userId: booker, classId: classId, bookingDate: _futureClass);
      await db.createWaitlistEntry(
        userId: waiter,
        classId: classId,
        isDropIn: true,
        dropInPaymentStatus: 'pending',
        dropInPrice: 15.0,
      );

      await sut.cancelBooking(userId: booker, classId: classId);

      final waiterBookings = await db
          .collection('bookings')
          .where('userId', isEqualTo: waiter)
          .where('classId', isEqualTo: classId)
          .get();
      expect(waiterBookings.docs, hasLength(1));
      final b = waiterBookings.docs.first.data();
      // Without the fix this would default to a free regular booking.
      expect(b['isDropIn'], isTrue);
      expect(b['dropInPaymentStatus'], 'pending');
      expect((b['dropInPrice'] as num).toDouble(), 15.0);
    });

    test('when multiple waitlisters exist, the earliest-joined is promoted',
        () async {
      const waiter2 = 'u13c';
      await db.createUser(userId: waiter2);
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 1,
          bookedCount: 1,
          waitlistCount: 2);
      await db.createBookingDoc(
          userId: booker, classId: classId, bookingDate: _futureClass);

      final t1 = DateTime(2099, 1, 1, 9, 0);
      final t2 = DateTime(2099, 1, 1, 10, 0);
      await db.createWaitlistEntry(
          userId: waiter2, classId: classId, createdAt: t2); // joined later
      await db.createWaitlistEntry(
          userId: waiter, classId: classId, createdAt: t1); // joined first

      await sut.cancelBooking(userId: booker, classId: classId);

      // The earliest-joined waiter (t1) should be promoted
      final promotedSnap = await db
          .collection('bookings')
          .where('userId', isEqualTo: waiter)
          .where('classId', isEqualTo: classId)
          .get();
      expect(promotedSnap.docs, hasLength(1));

      // The later waiter remains on waitlist
      final notPromotedSnap = await db
          .collection('bookings')
          .where('userId', isEqualTo: waiter2)
          .where('classId', isEqualTo: classId)
          .get();
      expect(notPromotedSnap.docs, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 13b. WAITLIST PROMOTION SAFETY & ORDERING
  // ══════════════════════════════════════════════════════════════════════════
  group('13b • waitlist promotion safety & ordering', () {
    const a = 'u13b_a';
    const b = 'u13b_b';
    const waiter = 'u13b_w';
    const classId = 'class_wlsafe';

    setUp(() async {
      await db.createUser(userId: a);
      await db.createUser(userId: b);
      await db.createUser(userId: waiter);
    });

    test('the same waitlister is never promoted twice on two cancellations',
        () async {
      // Capacity 2, both seats taken, one waitlister.
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 2,
          bookedCount: 2,
          waitlistCount: 1);
      await db.createBookingDoc(
          userId: a, classId: classId, bookingDate: _futureClass);
      await db.createBookingDoc(
          userId: b, classId: classId, bookingDate: _futureClass);
      await db.createWaitlistEntry(userId: waiter, classId: classId);

      // Cancel both booked members.
      await sut.cancelBooking(userId: a, classId: classId);
      await sut.cancelBooking(userId: b, classId: classId);

      // The waitlister must hold exactly ONE booking — not two.
      final waiterBookings = await db
          .collection('bookings')
          .where('userId', isEqualTo: waiter)
          .where('classId', isEqualTo: classId)
          .get();
      expect(waiterBookings.docs, hasLength(1));

      // Waitlist drained; class not overfilled.
      final wl = await db
          .collection('waitlists')
          .where('classId', isEqualTo: classId)
          .get();
      expect(wl.docs, isEmpty);
      final classSnap = await db.collection('classes').doc(classId).get();
      expect(classSnap.data()!['bookedCount'], lessThanOrEqualTo(2));
      expect(classSnap.data()!['waitlistCount'], 0);
    });

    // NOTE: the true concurrency case (two simultaneous cancels both
    // pre-reading the same first entry) can't be exercised here —
    // fake_cloud_firestore doesn't model Firestore's optimistic-concurrency
    // retry. The fix (re-reading the waitlist entry inside the transaction)
    // relies on that retry on real Firestore: the loser re-runs, sees the
    // entry already deleted, and skips the duplicate promotion.

    test('an entry with no createdAt sorts earliest (FIFO sentinel)', () async {
      await db.createClass(
          classId: classId, startTime: _futureClass, waitlistCount: 2);
      // Raw entry WITHOUT createdAt (legacy/corrupted), plus a normal one.
      await db.collection('waitlists').add(<String, dynamic>{
        'userId': waiter,
        'classId': classId,
        'gymId': '',
        'memberName': 'No Timestamp',
      });
      await db.createWaitlistEntry(
          userId: a, classId: classId, createdAt: _futureClass);

      final entries = await sut.streamWaitlistForClass(classId).first;
      expect(entries.first.userId, waiter); // missing createdAt → position 1
      final pos =
          await sut.streamUserWaitlistPosition(waiter, classId).first;
      expect(pos, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 14. LATE CANCELLATION PENALTY
  // ══════════════════════════════════════════════════════════════════════════
  group('14 • late cancellation penalty', () {
    const userId = 'u14';
    const classId = 'class_late';

    setUp(() async {
      await db.createUser(userId: userId);
    });

    test('cancelling within penalty window creates a late_cancellations record',
        () async {
      // Class in ~2 hours, lateCancellationMinutes = 180 (3 h) → within window
      final nearFuture = DateTime.now().add(const Duration(hours: 2));
      await db.createClass(
          classId: classId,
          startTime: nearFuture,
          capacity: 10,
          bookedCount: 1);
      await db.createBookingDoc(
          userId: userId, classId: classId, bookingDate: nearFuture);
      await db.setBookingRules(lateCancellationMinutes: 180);

      await sut.cancelBooking(userId: userId, classId: classId);

      final penalties = await db
          .collection('late_cancellations')
          .where('userId', isEqualTo: userId)
          .get();
      expect(penalties.docs, hasLength(1));
      expect(penalties.docs.first.data()['classId'], classId);
    });

    test(
        'cancelling outside penalty window does not create a penalty record',
        () async {
      // Class in 5 hours, lateCancellationMinutes = 60 (1 h) → outside window
      final farFuture = DateTime.now().add(const Duration(hours: 5));
      await db.createClass(
          classId: classId,
          startTime: farFuture,
          capacity: 10,
          bookedCount: 1);
      await db.createBookingDoc(
          userId: userId, classId: classId, bookingDate: farFuture);
      await db.setBookingRules(lateCancellationMinutes: 60);

      await sut.cancelBooking(userId: userId, classId: classId);

      final penalties = await db.collection('late_cancellations').get();
      expect(penalties.docs, isEmpty);
    });

    test('lateCancellationMinutes = 0 (disabled) never creates a penalty',
        () async {
      final nearFuture = DateTime.now().add(const Duration(minutes: 10));
      await db.createClass(
          classId: classId,
          startTime: nearFuture,
          capacity: 10,
          bookedCount: 1);
      await db.createBookingDoc(
          userId: userId, classId: classId, bookingDate: nearFuture);
      await db.setBookingRules(lateCancellationMinutes: 0);

      await sut.cancelBooking(userId: userId, classId: classId);

      final penalties = await db.collection('late_cancellations').get();
      expect(penalties.docs, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 15. PREVENT OVERLAPPING BOOKINGS
  // ══════════════════════════════════════════════════════════════════════════
  group('14b • promoteFirstWaitlisted preserves drop-in fields', () {
    test('admin promotion of a drop-in waitlister keeps the drop-in fields',
        () async {
      const classId = 'class_promo_dropin';
      const waiter = 'u14b';
      await db.createUser(userId: waiter);
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          capacity: 1,
          bookedCount: 0,
          waitlistCount: 1);
      await db.createWaitlistEntry(
        userId: waiter,
        classId: classId,
        isDropIn: true,
        dropInPaymentStatus: 'pending',
        dropInPrice: 20.0,
      );

      await sut.promoteFirstWaitlisted(classId);

      final bookings = await db
          .collection('bookings')
          .where('userId', isEqualTo: waiter)
          .where('classId', isEqualTo: classId)
          .get();
      expect(bookings.docs, hasLength(1));
      final b = bookings.docs.first.data();
      expect(b['isDropIn'], isTrue);
      expect((b['dropInPrice'] as num).toDouble(), 20.0);
    });
  });

  group('15 • prevent overlapping bookings', () {
    const userId = 'u15';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(planId: 'plan15', offerType: 'unlimited');
      await db.createSubscription(userId: userId, planId: 'plan15');
    });

    test('blocks booking when time slot overlaps existing booking', () async {
      final base = _tomorrow.copyWith(hour: 10, minute: 0, second: 0,
          microsecond: 0, millisecond: 0);
      final existStart = base;
      final existEnd = base.add(const Duration(hours: 1)); // 10:00–11:00

      // Existing booking 10:00–11:00
      await db.createBookingDoc(
        userId: userId,
        classId: 'existing_class',
        bookingDate: existStart,
        classStartTime: existStart,
        classEndTime: existEnd,
      );

      // New class 10:30–11:30 — overlaps
      final newStart = base.add(const Duration(minutes: 30));
      final newEnd = newStart.add(const Duration(hours: 1));
      await db.createClass(
        classId: 'class15a',
        startTime: newStart,
        endTime: newEnd,
        capacity: 10,
      );
      await db.setBookingRules(preventOverlappingBookings: true);

      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class15a',
          bypassDailyLimit: true,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('time slot'),
        )),
      );
    });

    test('allows booking when slots are adjacent (not overlapping)', () async {
      final base = _tomorrow.copyWith(hour: 10, minute: 0, second: 0,
          microsecond: 0, millisecond: 0);
      final existStart = base;
      final existEnd = base.add(const Duration(hours: 1)); // 10:00–11:00

      await db.createBookingDoc(
        userId: userId,
        classId: 'existing_class2',
        bookingDate: existStart,
        classStartTime: existStart,
        classEndTime: existEnd,
      );

      // New class 11:00–12:00 — adjacent, not overlapping
      final newStart = existEnd;
      final newEnd = newStart.add(const Duration(hours: 1));
      await db.createClass(
        classId: 'class15b',
        startTime: newStart,
        endTime: newEnd,
        capacity: 10,
      );
      await db.setBookingRules(preventOverlappingBookings: true);

      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class15b',
          bypassDailyLimit: true,
        ),
        completes,
      );
    });

    test('allows overlap when setting is disabled', () async {
      final base = _tomorrow.copyWith(hour: 10, minute: 0, second: 0,
          microsecond: 0, millisecond: 0);
      final existStart = base;
      final existEnd = base.add(const Duration(hours: 1));

      await db.createBookingDoc(
        userId: userId,
        classId: 'existing_class3',
        bookingDate: existStart,
        classStartTime: existStart,
        classEndTime: existEnd,
      );

      final newStart = base.add(const Duration(minutes: 30));
      final newEnd = newStart.add(const Duration(hours: 1));
      await db.createClass(
        classId: 'class15c',
        startTime: newStart,
        endTime: newEnd,
        capacity: 10,
      );
      await db.setBookingRules(preventOverlappingBookings: false);

      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class15c',
          bypassDailyLimit: true,
        ),
        completes,
      );
    });

    test('legacy bookings without classStartTime/classEndTime are skipped',
        () async {
      final base = _tomorrow.copyWith(hour: 10, minute: 0, second: 0,
          microsecond: 0, millisecond: 0);

      // Existing booking with no time fields (legacy)
      await db.createBookingDoc(
        userId: userId,
        classId: 'existing_legacy',
        bookingDate: base,
        // no classStartTime / classEndTime
      );

      final newStart = base;
      final newEnd = newStart.add(const Duration(hours: 1));
      await db.createClass(
        classId: 'class15d',
        startTime: newStart,
        endTime: newEnd,
        capacity: 10,
      );
      await db.setBookingRules(preventOverlappingBookings: true);

      // Should succeed — legacy booking has no time fields to compare
      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class15d',
          bypassDailyLimit: true,
        ),
        completes,
      );
    });

    test('overlap rule also blocks a drop-in booking', () async {
      final base = _tomorrow.copyWith(
          hour: 10, minute: 0, second: 0, microsecond: 0, millisecond: 0);
      final existStart = base;
      final existEnd = base.add(const Duration(hours: 1)); // 10:00–11:00

      await db.createBookingDoc(
        userId: userId,
        classId: 'existing_class15e',
        bookingDate: existStart,
        classStartTime: existStart,
        classEndTime: existEnd,
      );

      // Overlapping class, drop-in enabled and priced.
      final newStart = base.add(const Duration(minutes: 30));
      await db.createClass(
        classId: 'class15e',
        startTime: newStart,
        endTime: newStart.add(const Duration(hours: 1)),
        capacity: 10,
        dropInEnabled: true,
        dropInPrice: 15.0,
      );
      await db.setBookingRules(preventOverlappingBookings: true);

      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class15e',
          isDropIn: true,
          bypassDailyLimit: true,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('time slot'),
        )),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 15b. MARK DROP-IN PAID
  // ══════════════════════════════════════════════════════════════════════════
  group('15b • markDropInPaid', () {
    test('marks an existing drop-in booking as paid', () async {
      final ref = await db.createBookingDoc(
        userId: 'u1',
        classId: 'c1',
        bookingDate: DateTime(2026, 6, 1),
        isDropIn: true,
      );
      await sut.markDropInPaid(ref.id);
      final snap = await db.collection('bookings').doc(ref.id).get();
      expect(snap.data()!['dropInPaymentStatus'], 'paid');
    });

    test('throws when the booking does not exist', () async {
      await expectLater(
        sut.markDropInPaid('missing'),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when the booking is not a drop-in', () async {
      final ref = await db.createBookingDoc(
        userId: 'u1',
        classId: 'c1',
        bookingDate: DateTime(2026, 6, 1),
        isDropIn: false,
      );
      await expectLater(
        sut.markDropInPaid(ref.id),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 16. PREVENT SAME CLASS TYPE PER DAY
  // ══════════════════════════════════════════════════════════════════════════
  group('16 • prevent same class type per day', () {
    const userId = 'u16';
    const wodTypeId = 'type_wod';
    const fbbTypeId = 'type_fbb';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(planId: 'plan16', offerType: 'unlimited');
      await db.createSubscription(userId: userId, planId: 'plan16');
    });

    test('blocks second booking of same class type on same day', () async {
      final classDay = _tomorrow.copyWith(
          hour: 9, minute: 0, second: 0, microsecond: 0, millisecond: 0);

      // Existing booking of WOD at 09:00
      await db.createBookingDoc(
        userId: userId,
        classId: 'wod_morning',
        bookingDate: classDay,
        classTypeId: wodTypeId,
      );

      // Second WOD at 18:00 same day — should be blocked
      final wodEvening = classDay.copyWith(hour: 18);
      await db.createClass(
        classId: 'class16a',
        startTime: wodEvening,
        endTime: wodEvening.add(const Duration(hours: 1)),
        capacity: 10,
        classTypeId: wodTypeId,
      );
      await db.setBookingRules(preventSameClassTypePerDay: true);

      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class16a',
          bypassDailyLimit: true,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('type booked for today'),
        )),
      );
    });

    test('allows different class type on the same day', () async {
      final classDay = _tomorrow.copyWith(
          hour: 9, minute: 0, second: 0, microsecond: 0, millisecond: 0);

      // Existing WOD booking
      await db.createBookingDoc(
        userId: userId,
        classId: 'wod_morning2',
        bookingDate: classDay,
        classTypeId: wodTypeId,
      );

      // FBB at same day — different type, should succeed
      final fbbEvening = classDay.copyWith(hour: 18);
      await db.createClass(
        classId: 'class16b',
        startTime: fbbEvening,
        endTime: fbbEvening.add(const Duration(hours: 1)),
        capacity: 10,
        classTypeId: fbbTypeId,
      );
      await db.setBookingRules(preventSameClassTypePerDay: true);

      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class16b',
          bypassDailyLimit: true,
        ),
        completes,
      );
    });

    test('allows same class type on a different day', () async {
      final day1 = _tomorrow.copyWith(
          hour: 9, minute: 0, second: 0, microsecond: 0, millisecond: 0);
      final day2 = day1.add(const Duration(days: 1));

      // Existing WOD on day1
      await db.createBookingDoc(
        userId: userId,
        classId: 'wod_day1',
        bookingDate: day1,
        classTypeId: wodTypeId,
      );

      // WOD on day2 — should succeed
      await db.createClass(
        classId: 'class16c',
        startTime: day2,
        endTime: day2.add(const Duration(hours: 1)),
        capacity: 10,
        classTypeId: wodTypeId,
      );
      await db.setBookingRules(preventSameClassTypePerDay: true);

      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class16c',
          bypassDailyLimit: true,
        ),
        completes,
      );
    });

    test('skips check when classTypeId is empty on new class', () async {
      final classDay = _tomorrow.copyWith(
          hour: 9, minute: 0, second: 0, microsecond: 0, millisecond: 0);

      await db.createBookingDoc(
        userId: userId,
        classId: 'wod_existing',
        bookingDate: classDay,
        classTypeId: wodTypeId,
      );

      // New class has no classTypeId — check should be skipped
      final evening = classDay.copyWith(hour: 18);
      await db.createClass(
        classId: 'class16d',
        startTime: evening,
        endTime: evening.add(const Duration(hours: 1)),
        capacity: 10,
        // no classTypeId
      );
      await db.setBookingRules(preventSameClassTypePerDay: true);

      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class16d',
          bypassDailyLimit: true,
        ),
        completes,
      );
    });

    test('allows same type per day when setting is disabled', () async {
      final classDay = _tomorrow.copyWith(
          hour: 9, minute: 0, second: 0, microsecond: 0, millisecond: 0);

      await db.createBookingDoc(
        userId: userId,
        classId: 'wod_disabled',
        bookingDate: classDay,
        classTypeId: wodTypeId,
      );

      final evening = classDay.copyWith(hour: 18);
      await db.createClass(
        classId: 'class16e',
        startTime: evening,
        endTime: evening.add(const Duration(hours: 1)),
        capacity: 10,
        classTypeId: wodTypeId,
      );
      await db.setBookingRules(preventSameClassTypePerDay: false);

      await expectLater(
        sut.bookClass(
          userId: userId,
          classId: 'class16e',
          bypassDailyLimit: true,
        ),
        completes,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 17. HIDE CLASSES WITHOUT SUBSCRIPTION — setting getter/setter
  // ══════════════════════════════════════════════════════════════════════════
  group('17 • hideClassesWithoutSubscription setting', () {
    test('returns false by default when no rule document exists', () async {
      final result = await sut.getHideClassesWithoutSubscription();
      expect(result, isFalse);
    });

    test('returns false when stored value is false', () async {
      await db.setBookingRules(hideClassesWithoutSubscription: false);
      final result = await sut.getHideClassesWithoutSubscription();
      expect(result, isFalse);
    });

    test('returns true when stored value is true', () async {
      await db.setBookingRules(hideClassesWithoutSubscription: true);
      final result = await sut.getHideClassesWithoutSubscription();
      expect(result, isTrue);
    });

    test('setHideClassesWithoutSubscription(true) persists to Firestore',
        () async {
      await sut.setHideClassesWithoutSubscription(true);

      final snap = await db
          .collection('settings')
          .doc('bookingRules')
          .get();
      expect(snap.data()!['hideClassesWithoutSubscription'], isTrue);
    });

    test('setHideClassesWithoutSubscription(false) persists to Firestore',
        () async {
      // First set to true, then disable
      await sut.setHideClassesWithoutSubscription(true);
      await sut.setHideClassesWithoutSubscription(false);

      final snap = await db
          .collection('settings')
          .doc('bookingRules')
          .get();
      expect(snap.data()!['hideClassesWithoutSubscription'], isFalse);
    });

    test('set does not overwrite unrelated rules (merge behaviour)', () async {
      // Store an existing rule first
      await db.setBookingRules(maxBookingsPerDay: 5);

      // Set the new flag — should not wipe maxBookingsPerDay
      await sut.setHideClassesWithoutSubscription(true);

      final snap = await db
          .collection('settings')
          .doc('bookingRules')
          .get();
      expect(snap.data()!['hideClassesWithoutSubscription'], isTrue);
      expect(snap.data()!['maxBookingsPerDay'], 5);
    });

    test('cache is invalidated after set — subsequent get reads new value',
        () async {
      // Prime the cache with false
      final before = await sut.getHideClassesWithoutSubscription();
      expect(before, isFalse);

      // Update — should invalidate cache
      await sut.setHideClassesWithoutSubscription(true);

      // Next get must return the updated value
      final after = await sut.getHideClassesWithoutSubscription();
      expect(after, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 18. PACK SESSION REFUNDED ON CANCEL
  // ══════════════════════════════════════════════════════════════════════════
  group('18 • pack session refunded on cancel', () {
    const userId = 'u18';
    const planId = 'plan_pack1';

    setUp(() async {
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'limited_sessions', totalCheckins: 1);
      await db.createSubscription(userId: userId, planId: planId);
      await db.createClass(
          classId: 'packA',
          startTime: _futureClass,
          requiredOfferPlanIds: [planId]);
      await db.createClass(
          classId: 'packB',
          startTime: _futureClass,
          requiredOfferPlanIds: [planId]);
    });

    test('cancelling a pack booking frees the consumed session', () async {
      // 1-session pack: book A → pack exhausted, B blocked.
      await sut.bookClass(
          userId: userId, classId: 'packA', bypassDailyLimit: true);
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: 'packB', bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('Session pack exhausted'))),
      );

      // Cancel A → the session is returned (booking is deleted).
      await sut.cancelBooking(userId: userId, classId: 'packA');

      final result = await sut.bookClass(
          userId: userId, classId: 'packB', bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 19. PENDING SUBSCRIPTION CAN BOOK (intentional)
  // ══════════════════════════════════════════════════════════════════════════
  group('19 • pending subscription can book', () {
    const userId = 'u19';
    const planId = 'plan_pending';

    test('a member with a pending subscription can book a required class',
        () async {
      // 'pending' (e.g. assigned, paying in instalments) is intentionally
      // allowed to book — only 'cancelled'/'paused' are blocked.
      await db.createUser(userId: userId);
      await db.createPlan(
          planId: planId, offerType: 'weekly_recurring', checkinsPerWeek: 3);
      await db.createSubscription(
          userId: userId, planId: planId, status: 'pending');
      await db.createClass(
          classId: 'pendingClass',
          startTime: _futureClass,
          requiredOfferPlanIds: [planId]);

      final result = await sut.bookClass(
          userId: userId, classId: 'pendingClass', bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test('a cancelled subscription cannot book', () async {
      await db.createUser(userId: 'u19b');
      await db.createPlan(
          planId: 'plan_cancelled', offerType: 'weekly_recurring',
          checkinsPerWeek: 3);
      await db.createSubscription(
          userId: 'u19b', planId: 'plan_cancelled', status: 'cancelled');
      await db.createClass(
          classId: 'cancelledClass',
          startTime: _futureClass,
          requiredOfferPlanIds: ['plan_cancelled']);

      await expectLater(
        () => sut.bookClass(
            userId: 'u19b', classId: 'cancelledClass', bypassDailyLimit: true),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 20. OFFER-TYPE LIMIT BEHAVIOR
  // ══════════════════════════════════════════════════════════════════════════
  group('20 • offer-type limit behavior', () {
    const userId = 'u20';

    Future<void> seed({
      required String planId,
      required String offerType,
      int checkinsPerWeek = 0,
      int totalCheckins = 0,
      required String classId,
    }) async {
      await db.createPlan(
        planId: planId,
        offerType: offerType,
        checkinsPerWeek: checkinsPerWeek,
        totalCheckins: totalCheckins,
      );
      await db.createSubscription(userId: userId, planId: planId);
      await db.createClass(
          classId: classId,
          startTime: _futureClass,
          requiredOfferPlanIds: [planId]);
    }

    setUp(() => db.createUser(userId: userId));

    test("'weekly' alias enforces the weekly limit like weekly_recurring",
        () async {
      await seed(
          planId: 'p_weekly',
          offerType: 'weekly',
          checkinsPerWeek: 2,
          classId: 'c_weekly');
      for (var i = 1; i <= 2; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'w_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: 'p_weekly');
      }
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: 'c_weekly', bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('Weekly limit reached'))),
      );
    });

    test("'pack' alias is exhausted like limited_sessions", () async {
      await seed(
          planId: 'p_pack',
          offerType: 'pack',
          totalCheckins: 2,
          classId: 'c_pack');
      for (var i = 1; i <= 2; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'pk_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: 'p_pack');
      }
      await expectLater(
        () => sut.bookClass(
            userId: userId, classId: 'c_pack', bypassDailyLimit: true),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), '', contains('Session pack exhausted'))),
      );
    });

    test('a weekly offer with checkinsPerWeek = 0 has no limit', () async {
      await seed(
          planId: 'p_unl',
          offerType: 'weekly_recurring',
          checkinsPerWeek: 0,
          classId: 'c_unl');
      // Far more bookings than any cap — must still be allowed.
      for (var i = 1; i <= 12; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'unl_prev_$i',
            bookingDate: _futureClass,
            usedPlanId: 'p_unl');
      }
      final result = await sut.bookClass(
          userId: userId, classId: 'c_unl', bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });

    test("previous week's bookings don't count toward this week's limit",
        () async {
      await seed(
          planId: 'p_wk2',
          offerType: 'weekly_recurring',
          checkinsPerWeek: 2,
          classId: 'c_wk2');
      // 2 bookings last week — should not block this week's first booking.
      final lastWeek = _futureClass.subtract(const Duration(days: 7));
      for (var i = 1; i <= 2; i++) {
        await db.createBookingDoc(
            userId: userId,
            classId: 'lw_prev_$i',
            bookingDate: lastWeek,
            usedPlanId: 'p_wk2');
      }
      final result = await sut.bookClass(
          userId: userId, classId: 'c_wk2', bypassDailyLimit: true);
      expect(result, BookingResult.booked);
    });
  });
}
