import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/app_user.dart';

class MemberService {
  MemberService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.gymId = '',
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// When non-empty, all queries are scoped to this gym.
  final String gymId;

  Query<Map<String, dynamic>> get _usersQuery {
    Query<Map<String, dynamic>> q = _firestore.collection('users');
    if (gymId.isNotEmpty) {
      q = q.where('gymId', isEqualTo: gymId);
    }
    return q;
  }

  Stream<AppUser?> streamUser(String userId) {
    if (userId.trim().isEmpty) {
      return Stream<AppUser?>.value(null);
    }

    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return AppUser.fromSnapshot(snapshot);
    });
  }

  Stream<List<AppUser>> streamMembers() {
    return _usersQuery.snapshots().map((query) {
      final users = query.docs.map((doc) => AppUser.fromSnapshot(doc)).toList();
      users.sort((a, b) {
        final aName = a.displayName.trim().isEmpty ? a.email : a.displayName;
        final bName = b.displayName.trim().isEmpty ? b.email : b.displayName;
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });
      return List<AppUser>.unmodifiable(users);
    });
  }

  /// One-time fetch of all members — avoids opening a persistent listener.
  Future<List<AppUser>> fetchMembers() async {
    final snap = await _usersQuery.get();
    final users = snap.docs.map((doc) => AppUser.fromSnapshot(doc)).toList();
    users.sort((a, b) {
      final aName = a.displayName.trim().isEmpty ? a.email : a.displayName;
      final bName = b.displayName.trim().isEmpty ? b.email : b.displayName;
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    });
    return List<AppUser>.unmodifiable(users);
  }

  Stream<List<AppUser>> streamCoaches() {
    // Filter all users to those with coach or staff in their effective roles.
    // This handles both legacy (role string) and multi-role (roles array) users.
    return streamMembers().map((users) {
      final coaches = users.where((u) {
        final roles = u.effectiveRoles;
        return roles.contains('coach') || roles.contains('staff');
      }).toList();
      coaches.sort((a, b) {
        final aName = a.displayName.trim().isEmpty ? a.email : a.displayName;
        final bName = b.displayName.trim().isEmpty ? b.email : b.displayName;
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });
      return coaches;
    });
  }

  /// Streams all users with no gym assigned (gymId is empty / missing).
  /// Only meaningful when called with super-admin permissions.
  Stream<List<AppUser>> streamUnassignedMembers() {
    return _firestore
        .collection('users')
        .where('gymId', isEqualTo: '')
        .snapshots()
        .map((query) {
      final users = query.docs
          .map(AppUser.fromSnapshot)
          .where((u) => !u.isSuperAdmin)
          .toList();
      users.sort((a, b) {
        final aName = a.displayName.trim().isEmpty ? a.email : a.displayName;
        final bName = b.displayName.trim().isEmpty ? b.email : b.displayName;
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });
      return List<AppUser>.unmodifiable(users);
    });
  }

  /// Assigns [userId] to [targetGymId]. Clears the gym if [targetGymId] is empty.
  Future<void> assignToGym(String userId, String targetGymId) async {
    await _firestore.collection('users').doc(userId).update(<String, dynamic>{
      'gymId': targetGymId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createMember({
    required String email,
    required String displayName,
    String role = 'member',
    List<String> roles = const [],
    String membershipPlanId = '',
    String subscriptionStatus = 'none',
  }) async {
    final effectiveRoles = roles.isNotEmpty ? roles : [role];
    await _firestore.collection('users').add(<String, dynamic>{
      'email': email,
      'displayName': displayName,
      'role': role,
      'roles': effectiveRoles,
      'gymId': gymId,
      'membershipPlanId': membershipPlanId,
      'subscriptionStatus': subscriptionStatus,
      'phoneNumber': '',
      'photoUrl': '',
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

  Future<String> createMemberWithPassword({
    required String email,
    required String password,
    required String displayName,
    String role = 'member',
    List<String> roles = const [],
    String membershipPlanId = '',
    String subscriptionStatus = 'none',
    String phoneNumber = '',
    String gender = '',
    DateTime? dateOfBirth,
    String fitnessLevel = '',
    String emergencyContactName = '',
    String emergencyContactPhone = '',
    String healthNotes = '',
  }) async {
    final effectiveRoles = roles.isNotEmpty ? roles : [role];
    final primaryRole = _primaryRole(effectiveRoles);
    // Use a temporary secondary app so creating a member account does not
    // replace the currently signed-in admin session.
    final appName = 'member-create-${DateTime.now().microsecondsSinceEpoch}';
    final secondaryApp = await Firebase.initializeApp(
      name: appName,
      options: Firebase.app().options,
    );

    String? createdUid;
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final createdUser = credential.user;
      if (createdUser == null) {
        throw FirebaseAuthException(
          code: 'user-creation-failed',
          message: 'Firebase Auth user creation returned no user.',
        );
      }

      createdUid = createdUser.uid;
      await createdUser.updateDisplayName(displayName);

      await _firestore
          .collection('users')
          .doc(createdUser.uid)
          .set(<String, dynamic>{
        'email': email,
        'displayName': displayName,
        'role': primaryRole,
        'roles': effectiveRoles,
        'gymId': gymId,
        'membershipPlanId': membershipPlanId,
        'subscriptionStatus': subscriptionStatus,
        'phoneNumber': phoneNumber,
        'photoUrl': '',
        'gender': gender,
        'dateOfBirth':
            dateOfBirth != null ? Timestamp.fromDate(dateOfBirth) : null,
        'fitnessLevel': fitnessLevel,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
        'healthNotes': healthNotes,
        'joinDate': Timestamp.now(),
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
    } finally {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      await secondaryAuth.signOut();
      await secondaryApp.delete();
      // Keep the current session untouched.
      await _auth.currentUser?.reload();
    }
    return createdUid;
  }

  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) async {
    await _firestore.collection('users').doc(userId).update(<String, dynamic>{
      'displayName': displayName,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> updateProfile({
    required String userId,
    required String displayName,
    required String phoneNumber,
    required String photoUrl,
    required String gender,
    DateTime? dateOfBirth,
    required String fitnessLevel,
    required String emergencyContactName,
    required String emergencyContactPhone,
    required String healthNotes,
    required String cinNumber,
    required String address,
  }) async {
    await _firestore.collection('users').doc(userId).update(<String, dynamic>{
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'photoUrl': photoUrl,
      'gender': gender,
      'dateOfBirth':
          dateOfBirth != null ? Timestamp.fromDate(dateOfBirth) : null,
      'fitnessLevel': fitnessLevel,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'healthNotes': healthNotes,
      'cinNumber': cinNumber,
      'address': address,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> updateAdminNote({
    required String userId,
    required String adminNote,
  }) async {
    await _firestore.collection('users').doc(userId).update(<String, dynamic>{
      'adminNote': adminNote,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> updateRole({
    required String userId,
    required String role,
  }) async {
    await _firestore.collection('users').doc(userId).update(<String, dynamic>{
      'role': role,
      'roles': [role],
      'updatedAt': Timestamp.now(),
    });
  }

  /// Update multiple roles. The primary `role` field is set to the
  /// highest-priority role in [roles].
  Future<void> updateRoles({
    required String userId,
    required List<String> roles,
  }) async {
    final primary = _primaryRole(roles.isNotEmpty ? roles : ['member']);
    await _firestore.collection('users').doc(userId).update(<String, dynamic>{
      'role': primary,
      'roles': roles.isNotEmpty ? roles : ['member'],
      'updatedAt': Timestamp.now(),
    });
  }

  static String _primaryRole(List<String> roles) {
    const priority = ['admin', 'owner', 'staff', 'coach', 'member'];
    for (final p in priority) {
      if (roles.contains(p)) return p;
    }
    return roles.isNotEmpty ? roles.first : 'member';
  }

  Future<void> updateMembership({
    required String userId,
    required String membershipPlanId,
    required String subscriptionStatus,
  }) async {
    await _firestore.collection('users').doc(userId).update(<String, dynamic>{
      'membershipPlanId': membershipPlanId,
      'subscriptionStatus': subscriptionStatus,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> assignOfferWithDates({
    required String userId,
    required String membershipPlanId,
    required DateTime startDate,
    required DateTime endDate,
    String subscriptionStatus = 'active',
  }) async {
    await _firestore.collection('users').doc(userId).update(<String, dynamic>{
      'membershipPlanId': membershipPlanId,
      'subscriptionStatus': subscriptionStatus,
      'offerStartAt': Timestamp.fromDate(startDate),
      'offerEndAt': Timestamp.fromDate(endDate),
      'updatedAt': Timestamp.now(),
    });
  }

  /// Sets the gym for a member who just registered and picked their gym.
  Future<void> joinGym({
    required String userId,
    required String gymId,
  }) async {
    await _firestore.collection('users').doc(userId).update(<String, dynamic>{
      'gymId': gymId,
      'updatedAt': Timestamp.now(),
    });
  }
}
