import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'services/fcm_service.dart';
import 'utils/crash_logger.dart';

Future<void> main() async {
  // Background handler is mobile-only; web has no background isolate.
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await initializeFirebase();
      runApp(const FitFlowApp());
    },
    (error, stack) => CrashLogger.log(error, stack, reason: 'ZonedGuarded'),
  );
}
