import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';

import '../utils/crash_logger.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      return;
    }

    await _ensureUserProfileDocument(
      uid: user.uid,
      email: user.email ?? email,
      displayName: user.displayName ?? '',
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await credential.user?.updateDisplayName(displayName);

    final uid = credential.user?.uid;
    if (uid == null) {
      return;
    }

    await _ensureUserProfileDocument(
      uid: uid,
      email: email,
      displayName: displayName,
    );
  }

  Future<void> signInWithGoogle() async {
    UserCredential credential;

    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      credential = await _auth.signInWithPopup(provider);
    } else {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final authCredential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      credential = await _auth.signInWithCredential(authCredential);
    }

    final user = credential.user;
    if (user == null) return;

    await _ensureUserProfileDocument(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
      photoUrl: user.photoURL ?? '',
    );
  }

  Future<void> _ensureUserProfileDocument({
    required String uid,
    required String email,
    required String displayName,
    String photoUrl = '',
  }) async {
    final userRef = _firestore.collection('users').doc(uid);
    final existing = await userRef.get();
    if (existing.exists) {
      // Update photo/displayName if Google sign-in provided them and they're missing
      final data = existing.data() ?? {};
      final updates = <String, dynamic>{};
      if ((data['photoUrl'] as String? ?? '').isEmpty && photoUrl.isNotEmpty) {
        updates['photoUrl'] = photoUrl;
      }
      if ((data['displayName'] as String? ?? '').isEmpty &&
          displayName.isNotEmpty) {
        updates['displayName'] = displayName;
      }
      if (updates.isNotEmpty) {
        updates['updatedAt'] = Timestamp.now();
        await userRef.update(updates);
      }
      return;
    }

    await userRef.set(<String, dynamic>{
      'email': email,
      'displayName': displayName,
      'role': 'member',
      'roles': ['member'],
      'gymId': '',
      'membershipPlanId': '',
      'subscriptionStatus': 'none',
      'phoneNumber': '',
      'photoUrl': photoUrl,
      'gender': '',
      'dateOfBirth': null,
      'fitnessLevel': '',
      'emergencyContactName': '',
      'emergencyContactPhone': '',
      'healthNotes': '',
      'joinDate': Timestamp.now(),
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
  }

  /// Signs out and scrubs every trace of the previous account from this
  /// device: the Google Sign-In session, Firestore's local cache, and the
  /// crash-reporting user id. Without this, a stale cached session/UID from
  /// a previous account can linger and be picked back up on next launch —
  /// which is exactly what caused web and mobile to show different data for
  /// what looked like "the same" account.
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (e, st) {
      // Not signed in via Google, or platform doesn't support it — fine.
      debugPrint('AuthService.signOut: GoogleSignIn.signOut ignored: $e\n$st');
    }

    await _auth.signOut();

    try {
      // Fails if a Firestore listener is still active; best-effort only —
      // any lingering data is harmless once there's no signed-in user to
      // scope it to, and the next sign-in reads fresh from the server.
      await _firestore.clearPersistence();
    } catch (e, st) {
      debugPrint('AuthService.signOut: clearPersistence ignored: $e\n$st');
    }

    await CrashLogger.clearUser();
  }
}
