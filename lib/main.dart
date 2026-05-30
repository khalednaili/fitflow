import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'utils/crash_logger.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);

      // Disable Firestore's multi-tab persistence on web and force long-polling
      // to avoid internal assertion failures (IDs b815/ca9) in Firebase JS SDK
      // 11.9.1 caused by a bug in the WebChannel-based watch stream.
      if (kIsWeb) {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: false,
          webExperimentalForceLongPolling: true,
        );
      }

      // Route all uncaught Flutter/platform errors through CrashLogger so they
      // are always printed to the console. On non-web they are also forwarded
      // to Firebase Crashlytics.
      FlutterError.onError = (details) {
        CrashLogger.log(
          details.exception,
          details.stack,
          reason: 'FlutterError',
          fatal: true,
        );
        if (!kIsWeb) {
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        }
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        CrashLogger.log(error, stack, reason: 'PlatformDispatcher', fatal: true);
        if (!kIsWeb) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        }
        return true;
      };

      runApp(const FitFlowApp());
    },
    // Catches errors thrown inside runZonedGuarded that are not caught above.
    (error, stack) => CrashLogger.log(error, stack, reason: 'ZonedGuarded'),
  );
}
