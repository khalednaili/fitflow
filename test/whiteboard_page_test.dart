import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/l10n/app_localizations.dart';
import 'package:fit_flow/screens/admin/tabs/admin_whiteboard_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps the widget under test with the minimum Material + l10n scaffolding.
/// Sets a large enough surface to prevent RenderFlex overflow in tests.
Widget _wrap(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return MaterialApp(
    localizationsDelegates: const [AppLocalizationsDelegate()],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

/// Today at the specified hour — matches the date filter used by the tab.
DateTime _todayAt(int hour, [int minute = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, hour, minute);
}

/// Seed one class document for today into [db].
Future<String> _seedClass(
  FakeFirebaseFirestore db, {
  String id = 'class1',
  String title = 'WOD',
  String classTypeId = 'wod',
  int hour = 9,
  int capacity = 12,
  int bookedCount = 0,
}) async {
  final start = _todayAt(hour);
  final end = _todayAt(hour + 1);
  await db.collection('classes').doc(id).set({
    'gymId': 'gym1',
    'title': title,
    'classTypeId': classTypeId,
    'coachName': 'Coach A',
    'description': '',
    'startTime': Timestamp.fromDate(start),
    'endTime': Timestamp.fromDate(end),
    'requiredOfferPlanId': '',
    'requiredOfferPlanIds': <String>[],
    'repeatWeekly': false,
    'repeatWeekdays': <int>[],
    'capacity': capacity,
    'bookedCount': bookedCount,
    'waitlistCount': 0,
  });
  return id;
}

/// Seed one WOD document for today into [db].
Future<void> _seedWod(
  FakeFirebaseFirestore db, {
  String id = 'wod1',
  String classTypeId = 'wod',
  String classTypeName = '',
  String warmUp = 'Jog 400m',
  String coolDown = 'Stretching',
  List<Map<String, dynamic>> parts = const [],
}) async {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  await db.collection('wods').doc(id).set({
    'gymId': 'gym1',
    'title': 'Test WOD',
    'description': '',
    'classTypeId': classTypeId,
    'classTypeName': classTypeName,
    'date': Timestamp.fromDate(day),
    'warmUp': warmUp,
    'coolDown': coolDown,
    'exercises': <Map<String, dynamic>>[],
    'parts': parts,
    'format': '',
    'timeCap': '',
    'memberNote': '',
    'coachNote': '',
  });
}

/// Seed one booking document into [db].
Future<void> _seedBooking(
  FakeFirebaseFirestore db, {
  required String classId,
  String userId = 'user1',
  String memberName = 'Alice',
  bool checkedIn = false,
}) async {
  await db.collection('bookings').add({
    'gymId': 'gym1',
    'classId': classId,
    'userId': userId,
    'memberName': memberName,
    'checkedIn': checkedIn,
    'isDropIn': false,
    'dropInPaymentStatus': 'pending',
    'guestEmail': '',
    'usedPlanId': '',
    'createdAt': Timestamp.now(),
    'classTypeId': 'wod',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  tearDown(() {
    // Reset view after each test in case tester.view was set
  });

  // ── 1. Smoke ──────────────────────────────────────────────────────────────

  testWidgets('renders without crash with empty Firestore', (tester) async {
    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    await tester.pump(); // let first StreamBuilder frame settle
    // Should render a Material background without throwing
    expect(find.byType(AdminWhiteboardTab), findsOneWidget);
  });

  // ── 2. No classes today ───────────────────────────────────────────────────

  testWidgets('shows empty-state message when no classes exist', (tester) async {
    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Empty state shows an icon and a message containing "No classes"
    expect(
      find.textContaining('No classes', findRichText: true),
      findsAtLeastNWidgets(1),
    );
  });

  // ── 3. Class pill chip appears ────────────────────────────────────────────

  testWidgets('shows class pill chip after class is seeded', (tester) async {
    await _seedClass(db, title: 'Morning WOD');

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    // Allow streams to propagate: class stream → postFrameCallback reconcile → WOD stream
    await tester.pump();                                  // initial build
    await tester.pump(const Duration(milliseconds: 50)); // class stream resolves
    await tester.pump();                                  // postFrameCallback fires (class selection)
    await tester.pump(const Duration(milliseconds: 50)); // WOD/booking streams resolve
    await tester.pump();                                  // content renders

    // The class pill label contains the title
    expect(find.textContaining('Morning WOD'), findsAtLeastNWidgets(1));
  });

  testWidgets('date chip initially shows Today label', (tester) async {
    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Today'), findsOneWidget);
  });

  // ── 5. WOD warm-up text rendered ─────────────────────────────────────────

  testWidgets('renders warm-up text from WOD', (tester) async {
    await _seedClass(db);
    await _seedWod(db, warmUp: 'Row 500m then stretch');

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    // Two pumps: first renders, second resolves streams
    // Allow streams to propagate: class stream → postFrameCallback reconcile → WOD stream
    await tester.pump();                                  // initial build
    await tester.pump(const Duration(milliseconds: 50)); // class stream resolves
    await tester.pump();                                  // postFrameCallback fires (class selection)
    await tester.pump(const Duration(milliseconds: 50)); // WOD/booking streams resolve
    await tester.pump();                                  // content renders

    expect(find.textContaining('Row 500m'), findsAtLeastNWidgets(1));
  });

  // ── 6. WOD part with description rendered ────────────────────────────────

  testWidgets('renders WOD part title and description', (tester) async {
    await _seedClass(db);
    await _seedWod(db, parts: [
      {
        'title': 'Strength',
        'format': 'For Time',
        'measure': 'Kilograms',
        'timeCap': '15 min',
        'description': '5x5 Back Squat at 80%',
        'exercises': <dynamic>[],
        'scales': <dynamic>[],
      },
    ]);

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    // Allow streams to propagate: class stream → postFrameCallback reconcile → WOD stream
    await tester.pump();                                  // initial build
    await tester.pump(const Duration(milliseconds: 50)); // class stream resolves
    await tester.pump();                                  // postFrameCallback fires (class selection)
    await tester.pump(const Duration(milliseconds: 50)); // WOD/booking streams resolve
    await tester.pump();                                  // content renders

    expect(find.textContaining('5x5 Back Squat'), findsAtLeastNWidgets(1));
    expect(find.textContaining('For Time'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Kilograms'), findsAtLeastNWidgets(1));
  });

  // ── 7. Regression: WOD scales rendered (bug a236461) ─────────────────────

  testWidgets('renders scale labels when part has only scales (regression)',
      (tester) async {
    await _seedClass(db);
    await _seedWod(db, parts: [
      {
        'title': 'AMRAP 12',
        'format': 'AMRAP',
        'measure': '',
        'timeCap': '',
        'description': '',    // intentionally empty — content is in scales
        'exercises': <dynamic>[],
        'scales': [
          {
            'label': 'Rx',
            'description': '5 Pull-ups / 10 Push-ups / 15 Squats',
            'exercises': <dynamic>[],
          },
          {
            'label': 'Scaled',
            'description': '5 Ring Rows / 10 Knee Push-ups / 15 Squats',
            'exercises': <dynamic>[],
          },
        ],
      },
    ]);

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    // Allow streams to propagate: class stream → postFrameCallback reconcile → WOD stream
    await tester.pump();                                  // initial build
    await tester.pump(const Duration(milliseconds: 50)); // class stream resolves
    await tester.pump();                                  // postFrameCallback fires (class selection)
    await tester.pump(const Duration(milliseconds: 50)); // WOD/booking streams resolve
    await tester.pump();                                  // content renders

    // Both scale pill labels must appear
    expect(find.text('— Rx —'), findsAtLeastNWidgets(1));
    expect(find.text('— Scaled —'), findsAtLeastNWidgets(1));
    // Scale content visible
    expect(find.textContaining('Pull-ups'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Ring Rows'), findsAtLeastNWidgets(1));
  });

  // ── 8. Stats bar reflects booked member count ─────────────────────────────

  testWidgets('stats bar shows correct total count', (tester) async {
    final classId = await _seedClass(db, capacity: 10);
    await _seedBooking(db, classId: classId, userId: 'u1', memberName: 'Alice');
    await _seedBooking(db, classId: classId, userId: 'u2', memberName: 'Bob',
        checkedIn: true);

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    // Allow streams to propagate: class stream → postFrameCallback reconcile → WOD stream
    await tester.pump();                                  // initial build
    await tester.pump(const Duration(milliseconds: 50)); // class stream resolves
    await tester.pump();                                  // postFrameCallback fires (class selection)
    await tester.pump(const Duration(milliseconds: 50)); // WOD/booking streams resolve
    await tester.pump();                                  // content renders

    // Stats bar shows total = 2
    expect(find.text('2'), findsAtLeastNWidgets(1));
    // Stats bar shows checked-in = 1
    expect(find.text('1'), findsAtLeastNWidgets(1));
  });

  // ── 9. Member name appears in roster ─────────────────────────────────────

  testWidgets('member name is shown in the whiteboard roster', (tester) async {
    final classId = await _seedClass(db);
    await _seedBooking(db, classId: classId, memberName: 'Charlie Brown');

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    // Allow streams to propagate: class stream → postFrameCallback reconcile → WOD stream
    await tester.pump();                                  // initial build
    await tester.pump(const Duration(milliseconds: 50)); // class stream resolves
    await tester.pump();                                  // postFrameCallback fires (class selection)
    await tester.pump(const Duration(milliseconds: 50)); // WOD/booking streams resolve
    await tester.pump();                                  // content renders

    expect(find.textContaining('Charlie Brown'), findsAtLeastNWidgets(1));
  });

  // ── 10. Multiple classes — pill selector shows all ────────────────────────

  testWidgets('all class pills shown when multiple classes exist', (tester) async {
    await _seedClass(db, id: 'c1', title: 'Morning WOD', hour: 7);
    await _seedClass(db, id: 'c2', title: 'Evening FBB', hour: 18);

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    // Allow streams to propagate: class stream → postFrameCallback reconcile → WOD stream
    await tester.pump();                                  // initial build
    await tester.pump(const Duration(milliseconds: 50)); // class stream resolves
    await tester.pump();                                  // postFrameCallback fires (class selection)
    await tester.pump(const Duration(milliseconds: 50)); // WOD/booking streams resolve
    await tester.pump();                                  // content renders

    expect(find.textContaining('Morning WOD'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Evening FBB'), findsAtLeastNWidgets(1));
  });

  // ── 11. Cool-down text rendered ───────────────────────────────────────────

  testWidgets('renders cool-down text from WOD', (tester) async {
    await _seedClass(db);
    await _seedWod(db, coolDown: 'Foam roll quads');

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    // Allow streams to propagate: class stream → postFrameCallback reconcile → WOD stream
    await tester.pump();                                  // initial build
    await tester.pump(const Duration(milliseconds: 50)); // class stream resolves
    await tester.pump();                                  // postFrameCallback fires (class selection)
    await tester.pump(const Duration(milliseconds: 50)); // WOD/booking streams resolve
    await tester.pump();                                  // content renders

    expect(find.textContaining('Foam roll quads'), findsAtLeastNWidgets(1));
  });

  // ── 12. No WOD for selected class shows empty state ──────────────────────

  testWidgets('shows no-workout placeholder when no WOD seeded', (tester) async {
    await _seedClass(db);
    // No WOD seeded

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    // Allow streams to propagate: class stream → postFrameCallback reconcile → WOD stream
    await tester.pump();                                  // initial build
    await tester.pump(const Duration(milliseconds: 50)); // class stream resolves
    await tester.pump();                                  // postFrameCallback fires (class selection)
    await tester.pump(const Duration(milliseconds: 50)); // WOD/booking streams resolve
    await tester.pump();                                  // content renders

    // The panel shows "No WOD assigned" when no WOD is seeded for the class
    expect(
      find.textContaining('No WOD', findRichText: true),
      findsAtLeastNWidgets(1),
    );
  });

  // ── 13. Regression: WOD updates when switching between classes ────────────
  //
  // Before the fix, the WOD StreamBuilder had no `key`, so Flutter reused its
  // state in-place when the class changed. The old WOD data lingered when
  // classTypeId was empty/shared, making the panel appear frozen.

  testWidgets('WOD panel updates when a different class is selected',
      (tester) async {
    // Two classes with distinct classTypeIds → distinct WODs.
    await _seedClass(db,
        id: 'c1', title: 'Morning WOD', hour: 7, classTypeId: 'type_a');
    await _seedClass(db,
        id: 'c2', title: 'Evening FBB', hour: 18, classTypeId: 'type_b');
    await _seedWod(db,
        id: 'wod_a', classTypeId: 'type_a', warmUp: 'WOD-A warm-up');
    await _seedWod(db,
        id: 'wod_b', classTypeId: 'type_b', warmUp: 'WOD-B warm-up');

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // Auto-selects the first class (Morning WOD at 07:00) — WOD-A must show.
    expect(find.textContaining('WOD-A warm-up'), findsAtLeastNWidgets(1));
    expect(find.textContaining('WOD-B warm-up'), findsNothing);

    // Tap the Evening FBB pill to switch classes.
    await tester.tap(find.textContaining('Evening FBB').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // After switching, WOD-B must show and WOD-A must be gone.
    expect(find.textContaining('WOD-B warm-up'), findsAtLeastNWidgets(1));
    expect(find.textContaining('WOD-A warm-up'), findsNothing);
  });

  // ── 14. Regression: no infinite rebuild loop on stream emission ───────────
  //
  // Before the fix, reconciled != _selectedClass used object identity. Every
  // Firestore emission produced new GymClass instances → always unequal →
  // addPostFrameCallback + setState every frame → pumpAndSettle never settles.

  testWidgets('widget settles without infinite rebuild loop', (tester) async {
    await _seedClass(db);

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));

    // pumpAndSettle will time-out (throw) if the ID-comparison fix is absent
    // and the widget keeps scheduling frames indefinitely.
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.byType(AdminWhiteboardTab), findsOneWidget);
  });

  // ── 15. Regression: WOD clears when switching to a class with no WOD ──────
  //
  // EMOM class has no classTypeId set. The new classTypeName fallback queries
  // by title — "EMOM" — which finds no WOD (WOD doc has classTypeName "WOD").

  testWidgets(
      'WOD panel shows no-WOD placeholder when class has no classTypeId (EMOM regression)',
      (tester) async {
    await _seedClass(db,
        id: 'c1', title: 'WOD', hour: 7, classTypeId: 'wod_type_id');
    await _seedClass(db,
        id: 'c2', title: 'EMOM', hour: 21, classTypeId: '');
    await _seedWod(db,
        id: 'wod_a',
        classTypeId: 'wod_type_id',
        classTypeName: 'WOD',
        warmUp: 'WOD warm-up text');
    // No WOD seeded with classTypeName='EMOM'.

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.textContaining('WOD warm-up text'), findsAtLeastNWidgets(1));

    await tester.tap(find.textContaining('EMOM').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.textContaining('WOD warm-up text'), findsNothing);
    expect(
      find.textContaining('No WOD', findRichText: true),
      findsAtLeastNWidgets(1),
    );
  });

  // ── 16. Real-world: class missing classTypeId, matched via classTypeName ───
  //
  // Firebase data shows ALL gym classes have classTypeId field ABSENT.
  // WODs carry both classTypeId (Firestore ID) and classTypeName ("WOD",
  // "EMOM"…). The fix: when classTypeId is empty, fall back to filtering by
  // classTypeName = class.title so each class sees its own workout.

  testWidgets(
      'WOD panel loads correct workout via classTypeName when class has no classTypeId',
      (tester) async {
    // Classes as they exist in real Firebase: classTypeId field absent (= '').
    await _seedClass(db, id: 'c1', title: 'WOD',  hour: 7,  classTypeId: '');
    await _seedClass(db, id: 'c2', title: 'EMOM', hour: 21, classTypeId: '');

    // WODs as they exist in real Firebase: classTypeId = real Firestore ID,
    // classTypeName = human-readable type name.
    await _seedWod(db,
        id: 'wod_real',
        classTypeId: 'SPRwqwq5ECglC3LloD1A',
        classTypeName: 'WOD',
        warmUp: 'Real WOD warm-up');
    await _seedWod(db,
        id: 'emom_real',
        classTypeId: 'ntj96UmzgaL1Pa7kUU46',
        classTypeName: 'EMOM',
        warmUp: 'Real EMOM warm-up');

    await tester.pumpWidget(_wrap(tester,
      AdminWhiteboardTab(gymId: 'gym1', firestore: db),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // WOD class auto-selected (earlier hour) → shows WOD warm-up only.
    expect(find.textContaining('Real WOD warm-up'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Real EMOM warm-up'), findsNothing);

    // Switch to EMOM → shows EMOM warm-up, WOD warm-up gone.
    await tester.tap(find.textContaining('EMOM').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.textContaining('Real EMOM warm-up'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Real WOD warm-up'), findsNothing);
  });
}
