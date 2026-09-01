import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/l10n/app_localizations.dart';
import 'package:fit_flow/models/personal_record.dart';
import 'package:fit_flow/screens/home/pr_calculator_screen.dart';

const _uid = 'member-1';

/// Wraps the widget under test with the minimum Material + l10n scaffolding.
/// Uses a wide/tall viewport so the whole screen (form + calculator +
/// history) fits without needing to scroll to find widgets.
Widget _wrap(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(650, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return MaterialApp(
    localizationsDelegates: const [AppLocalizationsDelegate()],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

Future<void> _seedPr(
  FakeFirebaseFirestore db, {
  String exerciseName = 'Back Squat',
  String value = '100 kg',
  String unit = 'kg',
  DateTime? achievedAt,
}) async {
  await db.collection('personalRecords').add(
        PersonalRecord(
          id: '',
          userId: _uid,
          exerciseName: exerciseName,
          value: value,
          unit: unit,
          achievedAt: achievedAt ?? DateTime.now(),
        ).toJson(),
      );
}

void main() {
  group('PersonalRecordsScreen', () {
    testWidgets('shows an empty state when there are no PRs yet',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        tester,
        PersonalRecordsScreen(uid: _uid, firestore: db),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Log a PR to use the calculator.'), findsOneWidget);
      expect(find.text('No personal records logged yet.'), findsOneWidget);
    });

    testWidgets('displays a seeded PR in the calculator and history list',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await _seedPr(db, exerciseName: 'Back Squat', value: '100 kg');

      await tester.pumpWidget(_wrap(
        tester,
        PersonalRecordsScreen(uid: _uid, firestore: db),
      ));
      await tester.pumpAndSettle();

      // Calculator dropdown defaults to the only exercise, current PR shown.
      expect(find.text('Back Squat'), findsWidgets);
      expect(find.text('100 kg'), findsWidgets);

      // History card lists it too.
      expect(find.text('No personal records logged yet.'), findsNothing);
    });

    testWidgets(
        'saving a new PR refreshes the calculator and history immediately',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        tester,
        PersonalRecordsScreen(uid: _uid, firestore: db),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Log a PR to use the calculator.'), findsOneWidget);
      expect(find.text('No personal records logged yet.'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Exercise'), 'Deadlift');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Weight'), '150');
      await tester.tap(find.widgetWithText(FilledButton, 'Save Record'));
      // The save awaits a Firestore write, then triggers an explicit
      // one-time re-fetch (ProgressService.fetchPersonalRecords) instead of
      // only relying on the passive stream — pumpAndSettle drains both.
      await tester.pumpAndSettle();

      expect(find.text('Log a PR to use the calculator.'), findsNothing);
      expect(find.text('No personal records logged yet.'), findsNothing);
      expect(find.text('Deadlift'), findsWidgets);
      expect(find.text('150 kg'), findsWidgets);
    });

    testWidgets('deleting a PR from the history list removes it',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await _seedPr(db, exerciseName: 'Back Squat', value: '100 kg');

      await tester.pumpWidget(_wrap(
        tester,
        PersonalRecordsScreen(uid: _uid, firestore: db),
      ));
      await tester.pumpAndSettle();

      // Expand the exercise group in the history list specifically (the
      // calculator card above it also renders the same exercise name once
      // as its dropdown value).
      await tester.tap(find.widgetWithText(ExpansionTile, 'Back Squat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Confirm the deletion in the dialog.
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('No personal records logged yet.'), findsOneWidget);
      final remaining = await db.collection('personalRecords').get();
      expect(remaining.docs, isEmpty);
    });
  });
}
