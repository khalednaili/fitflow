// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fit_flow/firebase_options.dart';

const _authHost = 'localhost';
const _authPort = 9099;
const _firestoreHost = 'localhost';
const _firestorePort = 8080;

/// Initialise Firebase and point it at the local emulators.
/// Must be called once before [runApp] in your test main.
Future<void> setupEmulators() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAuth.instance.useAuthEmulator(_authHost, _authPort);
  FirebaseFirestore.instance.useFirestoreEmulator(_firestoreHost, _firestorePort);

  print('[emulator] Auth      → $_authHost:$_authPort');
  print('[emulator] Firestore → $_firestoreHost:$_firestorePort');
}

/// Creates a Firebase Auth user and returns their UID.
Future<String> createTestUser(String email, String password) async {
  final cred = await FirebaseAuth.instance
      .createUserWithEmailAndPassword(email: email, password: password);
  return cred.user!.uid;
}

/// Seeds an admin user document in Firestore.
Future<void> seedAdminUser(String uid, String email) async {
  await FirebaseFirestore.instance.collection('users').doc(uid).set({
    'uid': uid,
    'email': email,
    'displayName': 'Test Admin',
    'roles': ['admin'],
    'subscriptionStatus': 'none',
    'joinDate': Timestamp.now(),
    'createdAt': Timestamp.now(),
  });
}

/// Seeds a member user + an open-ended active subscription.
Future<void> seedMemberUser(String uid, String email) async {
  final db = FirebaseFirestore.instance;

  await db.collection('users').doc(uid).set({
    'uid': uid,
    'email': email,
    'displayName': 'Test Member',
    'roles': ['member'],
    'subscriptionStatus': 'active',
    'joinDate': Timestamp.now(),
    'createdAt': Timestamp.now(),
  });

  // Unlimited active subscription so member can book any class.
  await db.collection('user_subscriptions').add({
    'userId': uid,
    'planId': '',
    'status': 'active',
    'startDate': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 1))),
    'endDate': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 365))),
    'createdAt': Timestamp.now(),
  });
}

/// Signs the current user out (no-op if not signed in).
Future<void> signOutQuietly() async {
  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}
}
