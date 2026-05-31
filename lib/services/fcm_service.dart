import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Obtain this from Firebase Console → Project Settings →
// Cloud Messaging → Web Push certificates → Key pair.
const _webVapidKey =
    'BNS4qgiOFKo_6rUBVgAmYq8fWEHarbOAztTrQJ2CKkvR-i2VSVtJ-FU9TtGEr0FSVXv4WOJnkxCjrSaGyeqQdLw';

/// Top-level background message handler — runs in a separate isolate.
/// Firebase is already initialized by the plugin before this is called.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM automatically displays the notification for background/terminated
  // messages that have a notification payload. Nothing extra needed here
  // unless you need to process data-only messages.
  debugPrint('[FCM] Background message: ${message.messageId}');
}

/// Notification channel used for high-importance push notifications.
const _androidChannel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'Push notifications from FitFlow.',
  importance: Importance.high,
);

class FcmService {
  FcmService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  // Keep subscription references so we can cancel before re-attaching,
  // preventing duplicate listeners if initialize() is called more than once.
  static StreamSubscription<RemoteMessage>? _foregroundSub;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<User?>? _authSub;

  /// Call once after [Firebase.initializeApp].
  /// Requests permission, wires up foreground message display, and saves the
  /// FCM token to Firestore whenever the signed-in user changes.
  static Future<void> initialize({String? userId}) async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    if (!kIsWeb) {
      // Set up flutter_local_notifications to display foreground messages.
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit),
      );

      // Create the Android notification channel.
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }

    // Cancel any previous listener before attaching a new one.
    await _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;

      if (kIsWeb) {
        // The browser suppresses OS notifications while the tab is in focus.
        // Real-time Firestore streams (e.g. NotificationBell) update the UI
        // instead — no extra pop-up needed here.
        debugPrint('[FCM] Foreground web message: ${notification.title}');
        return;
      }

      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    });

    // Subscribe to auth-state changes so the FCM token is always saved under
    // the correct user, including after sign-in / sign-out.
    await _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      await _refreshTokenFor(user.uid);
    });

    // Eagerly save the token if a user is already signed in (or was provided).
    final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _saveToken(uid);
  }

  /// Call when the authenticated user changes so tokens are attributed correctly.
  static Future<void> onUserChanged(String? userId) async {
    if (userId == null) return;
    await _refreshTokenFor(userId);
  }

  static Future<void> _refreshTokenFor(String userId) async {
    await _saveToken(userId);
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _messaging.onTokenRefresh
        .listen((token) => _saveToken(userId, token: token));
  }

  static Future<void> _saveToken(String userId, {String? token}) async {
    final fcmToken = token ??
        await _messaging.getToken(
          vapidKey: kIsWeb ? _webVapidKey : null,
        );
    if (fcmToken == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set(
        {'fcmTokens': FieldValue.arrayUnion([fcmToken])},
        SetOptions(merge: true),
      );
      debugPrint('[FCM] Token saved for $userId');
    } catch (e) {
      debugPrint('[FCM] Failed to save token: $e');
    }
  }

  /// Returns the current FCM registration token (all platforms).
  static Future<String?> getToken() async {
    return _messaging.getToken(vapidKey: kIsWeb ? _webVapidKey : null);
  }
}
