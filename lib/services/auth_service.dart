import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

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

  Future<void> signOut() => _auth.signOut();
}
