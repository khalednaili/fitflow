import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around Firebase Crashlytics.
/// Always prints to the debug console AND sends to Crashlytics (mobile/desktop).
/// On web, Crashlytics is not supported — console only.
class CrashLogger {
  CrashLogger._();

  static void _print(String label, Object error, StackTrace? stack) {
    debugPrint('╔══ [CrashLogger] $label ══');
    debugPrint('║ $error');
    if (stack != null) {
      final lines = stack.toString().trimRight().split('\n');
      for (final line in lines.take(8)) {
        debugPrint('║ $line');
      }
      if (lines.length > 8) debugPrint('║ … (${lines.length - 8} more frames)');
    }
    debugPrint('╚══════════════════════════');
  }

  /// Log a non-fatal error with its stack trace.
  static Future<void> log(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    _print(reason ?? 'ERROR', error, stack);
    if (!kIsWeb) {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
        fatal: fatal,
      );
    }
  }

  /// Log a custom message/breadcrumb.
  static Future<void> info(String message) async {
    debugPrint('[CrashLogger] ℹ $message');
    if (!kIsWeb) {
      await FirebaseCrashlytics.instance.log(message);
    }
  }

  /// Set the current user ID (call after login).
  static Future<void> setUser(String userId) async {
    debugPrint('[CrashLogger] 👤 user=$userId');
    if (!kIsWeb) {
      await FirebaseCrashlytics.instance.setUserIdentifier(userId);
    }
  }

  /// Clear user on logout.
  static Future<void> clearUser() async {
    debugPrint('[CrashLogger] 👤 user cleared');
    if (!kIsWeb) {
      await FirebaseCrashlytics.instance.setUserIdentifier('');
    }
  }
}
