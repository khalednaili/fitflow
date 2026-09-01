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

  // `GoogleSignIn.instance.initialize()` must be called exactly once, and
  // awaited, before any other method on it — otherwise both authenticate()
  // and signOut() throw "Bad state: ...must be called before any other
  // method". Memoized statically so it only actually runs once per app
  // process, no matter how many AuthService instances are created.
  static Future<void>? _googleSignInInit;

  static Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInInit ??= GoogleSignIn.instance.initialize();
  }

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
      await _ensureGoogleSignInInitialized();
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
    // GoogleSignIn.instance is only ever used on non-web (see
    // signInWithGoogle above; web signs in via Firebase's own popup flow
    // instead), and initialize() must be called at least once before
    // signOut() will work — otherwise this always throws "Bad state".
    if (!kIsWeb) {
      try {
        await _ensureGoogleSignInInitialized();
        await GoogleSignIn.instance.signOut();
      } catch (e, st) {
        // Not signed in via Google — fine.
        debugPrint(
            'AuthService.signOut: GoogleSignIn.signOut ignored: $e\n$st');
      }
    }

    await _auth.signOut();

    // Web never has offline persistence enabled (see app.dart), so there is
    // nothing to clear there — and terminating the shared web Firestore
    // instance would risk breaking any Firestore usage for the rest of this
    // browser session. Only mobile needs its on-disk cache wiped so a
    // previous account's cached documents can't linger.
    if (!kIsWeb) {
      try {
        // clearPersistence() only succeeds while the instance has never been
        // used, or right after terminate() — calling it directly (without
        // terminating first) always throws failed-precondition once any
        // query/listener has touched this instance, which is the normal
        // case here. Terminating first is the documented way to actually
        // clear the on-disk cache; the SDK transparently re-initializes the
        // instance the next time it's used (e.g. after the next sign-in).
        await _firestore.terminate();
        await _firestore.clearPersistence();
      } catch (e, st) {
        debugPrint('AuthService.signOut: clearPersistence ignored: $e\n$st');
      }
    }

    await CrashLogger.clearUser();
  }
}
