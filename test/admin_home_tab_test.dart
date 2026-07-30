import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/l10n/app_localizations.dart';
import 'package:fit_flow/screens/admin/tabs/admin_home_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps the widget under test with the minimum Material + l10n scaffolding.
/// Sets a wide surface so the desktop 3-column layout renders.
Widget _wrap(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return MaterialApp(
    localizationsDelegates: const [AppLocalizationsDelegate()],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

DateTime _todayAt(int hour, [int minute = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, hour, minute);
}

Future<void> _seedClass(
  FakeFirebaseFirestore db, {
  String id = 'class1',
  String title = 'WOD',
  String coachName = 'Coach A',
  int hour = 9,
  int capacity = 12,
  int bookedCount = 3,
  String gymId = 'gym1',
}) =>
    db.collection('classes').doc(id).set({
      'gymId': gymId,
      'title': title,
      'coachName': coachName,
      'description': '',
      'startTime': Timestamp.fromDate(_todayAt(hour)),
      'endTime': Timestamp.fromDate(_todayAt(hour + 1)),
      'requiredOfferPlanId': '',
      'requiredOfferPlanIds': <String>[],
      'repeatWeekly': false,
      'repeatWeekdays': <int>[],
      'capacity': capacity,
      'bookedCount': bookedCount,
      'waitlistCount': 0,
    });

Future<void> _seedMember(
  FakeFirebaseFirestore db, {
  required String id,
  String displayName = 'Test Member',
  String gymId = 'gym1',
  String subscriptionStatus = 'active',
  DateTime? dateOfBirth,
  DateTime? joinDate,
  String healthNotes = '',
}) =>
    db.collection('users').doc(id).set({
      'gymId': gymId,
      'displayName': displayName,
      'email': '$id@test.com',
      'role': 'member',
      'roles': <String>['member'],
      'membershipPlanId': '',
      'subscriptionStatus': subscriptionStatus,
      'healthNotes': healthNotes,
      if (dateOfBirth != null) 'dateOfBirth': Timestamp.fromDate(dateOfBirth),
      if (joinDate != null) 'joinDate': Timestamp.fromDate(joinDate),
    });

Future<void> _seedSubscription(
  FakeFirebaseFirestore db, {
  required String userId,
  required String planId,
  String status = 'active',
  DateTime? endDate,
  String gymId = 'gym1',
}) =>
    db.collection('user_subscriptions').add({
      'userId': userId,
      'planId': planId,
      'totalAmount': 100,
      'amountPaid': 100,
      'currency': 'EUR',
      'status': status,
      'gymId': gymId,
      if (endDate != null) 'endDate': Timestamp.fromDate(endDate),
    });

Future<void> _seedBooking(
  FakeFirebaseFirestore db, {
  required String userId,
  required String classId,
  DateTime? classStartTime,
  DateTime? classEndTime,
  bool checkedIn = false,
  String gymId = 'gym1',
}) =>
    db.collection('bookings').add({
      'gymId': gymId,
      'userId': userId,
      'classId': classId,
      'memberName': 'Test Member',
      'checkedIn': checkedIn,
      'isDropIn': false,
      'dropInPaymentStatus': 'pending',
      'guestEmail': '',
      'usedPlanId': '',
      'createdAt': Timestamp.now(),
      if (classStartTime != null)
        'classStartTime': Timestamp.fromDate(classStartTime),
      if (classEndTime != null)
        'classEndTime': Timestamp.fromDate(classEndTime),
    });

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  testWidgets('renders without crashing on an empty gym', (tester) async {
    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AdminHomeTab), findsOneWidget);
    expect(find.text('Class Stats'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('Upcoming Birthdays'), findsOneWidget);
    expect(find.text('Non-Attendance'), findsOneWidget);
    expect(find.text('New Sign Ups'), findsOneWidget);
    expect(find.text('Contracts Expiring'), findsOneWidget);
    expect(find.text('Recent Health Notes'), findsOneWidget);
  });

  testWidgets('Class Stats reflects a booking scoped to today', (tester) async {
    // Class runs in the future today so it can't yet count as a no-show.
    final now = DateTime.now();
    final start = now.add(const Duration(hours: 2));
    final end = now.add(const Duration(hours: 3));
    await _seedBooking(
      db,
      userId: 'u1',
      classId: 'c1',
      classStartTime: start,
      classEndTime: end,
    );

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // One booking today, none checked-out yet → "Bookings" is 1, the other
    // two stat blocks ("Cancellations", "No Shows") stay at 0.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));
  });

  testWidgets('Class Stats does not count another gym\'s bookings',
      (tester) async {
    await _seedBooking(
      db,
      userId: 'u1',
      classId: 'other-class',
      classStartTime: _todayAt(9),
      classEndTime: _todayAt(10),
      gymId: 'other-gym',
    );

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // No bookings for gym1 → stat blocks all show "0".
    expect(find.text('0'), findsNWidgets(3));
  });

  testWidgets('Schedule lists today\'s class with coach and capacity',
      (tester) async {
    await _seedClass(
        db, id: 'c1', title: 'Morning WOD', coachName: 'Coach Sam', hour: 8,
        capacity: 15, bookedCount: 5);

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Morning WOD'), findsOneWidget);
    expect(find.text('Coach Sam'), findsOneWidget);
    expect(find.text('5 / 15'), findsOneWidget);
  });

  testWidgets('Schedule shows empty state when no classes exist today',
      (tester) async {
    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No classes scheduled'), findsOneWidget);
  });

  testWidgets('Upcoming Birthdays lists a member with a birthday next week',
      (tester) async {
    final now = DateTime.now();
    final soonBirthday = DateTime(1990, now.month, now.day)
        .add(const Duration(days: 5));
    await _seedMember(db,
        id: 'm1',
        displayName: 'Birthday Bob',
        subscriptionStatus: 'none',
        dateOfBirth: soonBirthday);

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Birthday Bob'), findsOneWidget);
  });

  testWidgets(
      'Upcoming Birthdays shows empty state when no birthdays are near',
      (tester) async {
    await _seedMember(db,
        id: 'm1',
        displayName: 'No Birthday Soon',
        dateOfBirth: DateTime(1990, 1, 1)); // unlikely to be within 30 days

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Only assert the empty-state text when today isn't actually within
    // 30 days of Jan 1st, to keep this test stable year-round.
    final now = DateTime.now();
    final daysUntilJan1 =
        DateTime(now.year + (now.month == 1 && now.day == 1 ? 0 : 1), 1, 1)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
    if (daysUntilJan1 > 30) {
      expect(find.text('No birthdays in the next 30 days'), findsOneWidget);
    }
  });

  testWidgets('Recent Health Notes lists members with a non-empty note',
      (tester) async {
    await _seedMember(db,
        id: 'm1',
        displayName: 'Injured Ivy',
        subscriptionStatus: 'none',
        healthNotes: 'Twisted ankle');
    await _seedMember(db,
        id: 'm2', displayName: 'Healthy Hank', subscriptionStatus: 'none');

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Injured Ivy'), findsOneWidget);
    expect(find.text('Twisted ankle'), findsOneWidget);
    expect(find.text('Healthy Hank'), findsNothing);
  });

  testWidgets('New Sign Ups lists a member who joined within the last week',
      (tester) async {
    await _seedMember(db,
        id: 'm1',
        displayName: 'Newbie Nora',
        subscriptionStatus: 'none',
        joinDate: DateTime.now().subtract(const Duration(days: 2)));
    await _seedMember(db,
        id: 'm2',
        displayName: 'Veteran Vic',
        subscriptionStatus: 'none',
        joinDate: DateTime.now().subtract(const Duration(days: 90)));

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Newbie Nora'), findsOneWidget);
    expect(find.text('Veteran Vic'), findsNothing);
  });

  testWidgets('Contracts Expiring lists an active subscription ending soon',
      (tester) async {
    await _seedMember(db,
        id: 'm1', displayName: 'Expiring Emma', subscriptionStatus: 'none');
    await _seedSubscription(db,
        userId: 'm1',
        planId: 'plan1',
        endDate: DateTime.now().add(const Duration(days: 3)));

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Expiring Emma'), findsOneWidget);
  });

  testWidgets(
      'Contracts Expiring ignores subscriptions expiring outside the selected window',
      (tester) async {
    await _seedMember(db,
        id: 'm1', displayName: 'Far Future Fred', subscriptionStatus: 'none');
    await _seedSubscription(db,
        userId: 'm1',
        planId: 'plan1',
        endDate: DateTime.now().add(const Duration(days: 60)));

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Default tab is "1 Week" — a subscription expiring in 60 days shouldn't
    // show up until a wider window is selected.
    expect(find.text('Far Future Fred'), findsNothing);
    expect(find.text('No contracts expiring in this period'), findsOneWidget);
  });

  testWidgets('Non-Attendance lists an active member with no recent bookings',
      (tester) async {
    await _seedMember(db, id: 'm1', displayName: 'Absent Amy');

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Absent Amy'), findsOneWidget);
    expect(find.text('No recorded attendance'), findsOneWidget);
  });

  testWidgets(
      'Non-Attendance excludes a member who attended within the selected window',
      (tester) async {
    await _seedMember(db, id: 'm1', displayName: 'Regular Rita');
    await _seedBooking(
      db,
      userId: 'm1',
      classId: 'c1',
      classStartTime: DateTime.now().subtract(const Duration(hours: 2)),
      classEndTime: DateTime.now().subtract(const Duration(hours: 1)),
      checkedIn: true,
    );

    await tester.pumpWidget(
        _wrap(tester, AdminHomeTab(gymId: 'gym1', firestore: db)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Regular Rita'), findsNothing);
  });
}
