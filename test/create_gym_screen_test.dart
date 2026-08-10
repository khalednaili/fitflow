import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/l10n/app_localizations.dart';
import 'package:fit_flow/screens/super_admin/create_gym_screen.dart';

/// Wraps the widget under test with the minimum Material + l10n scaffolding.
/// Uses a tall viewport so the whole form fits without needing to scroll
/// (the screen embeds a map widget, which makes precise scroll-to-widget
/// unreliable due to multiple nested Scrollables).
Widget _wrap(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return MaterialApp(
    localizationsDelegates: const [AppLocalizationsDelegate()],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  group('CreateGymScreen validation', () {
    testWidgets('shows required-field errors when submitting an empty form',
        (tester) async {
      await tester.pumpWidget(
          _wrap(tester, CreateGymScreen(firestore: FakeFirebaseFirestore())));
      await tester.pump();

      await tester.tap(find.text('Create Gym'));
      await tester.pump();

      expect(find.text('Required'), findsWidgets);
    });

    testWidgets(
        'shows an email validation error for a malformed admin email',
        (tester) async {
      await tester.pumpWidget(
          _wrap(tester, CreateGymScreen(firestore: FakeFirebaseFirestore())));
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Gym Name *'), 'Iron Gym');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Admin Full Name *'),
          'Admin One');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Admin Email *'), 'not-an-email');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Admin Password *'), 'secret1');

      await tester.tap(find.text('Create Gym'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('shows a minimum-length error for a short admin password',
        (tester) async {
      await tester.pumpWidget(
          _wrap(tester, CreateGymScreen(firestore: FakeFirebaseFirestore())));
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Gym Name *'), 'Iron Gym');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Admin Full Name *'),
          'Admin One');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Admin Email *'),
          'admin@iron.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Admin Password *'), '123');

      await tester.tap(find.text('Create Gym'));
      await tester.pump();

      expect(find.text('Minimum 6 characters'), findsOneWidget);
    });

    testWidgets('toggling the password visibility icon does not throw',
        (tester) async {
      await tester.pumpWidget(
          _wrap(tester, CreateGymScreen(firestore: FakeFirebaseFirestore())));
      await tester.pump();

      final toggle = find.byIcon(Icons.visibility_outlined);
      expect(toggle, findsOneWidget);

      await tester.tap(toggle);
      await tester.pump();

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });
}
