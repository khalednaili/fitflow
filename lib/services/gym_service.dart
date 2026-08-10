import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';

import '../models/gym.dart';

class GymService {
  GymService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _authOverride = auth;

  final FirebaseFirestore _firestore;

  /// Explicit override passed by callers (e.g. tests). When null, resolved
  /// lazily via [_auth] so constructing a [GymService] never touches
  /// [FirebaseAuth.instance] unless auth is actually needed.
  final FirebaseAuth? _authOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _gyms =>
      _firestore.collection('gyms');

  /// Stream of active gyms only — used for the member gym picker.
  Stream<List<Gym>> streamActiveGyms() {
    return _gyms.snapshots().map((snap) {
      final list = snap.docs
          .map(Gym.fromSnapshot)
          .where((g) => g.isActive)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  /// Stream of all gyms — super admin use only.
  Stream<List<Gym>> watchAllGyms() {
    return _gyms
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Gym.fromSnapshot).toList());
  }

  /// Fetch a single gym by ID.
  Future<Gym?> getGym(String gymId) async {
    final doc = await _gyms.doc(gymId).get();
    if (!doc.exists) return null;
    return Gym.fromSnapshot(doc);
  }

  /// Fetch several gyms by ID at once (e.g. gyms a multi-gym member joined).
  /// Ignores IDs that don't exist. Firestore `whereIn` supports up to 30
  /// values per query, so batches are chunked defensively.
  Future<List<Gym>> getGymsByIds(List<String> gymIds) async {
    final ids = gymIds.toSet().toList();
    if (ids.isEmpty) return [];

    final results = <Gym>[];
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await _gyms
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(snap.docs.map(Gym.fromSnapshot));
    }
    return results;
  }

  /// Update gym status: 'active' | 'suspended'.
  Future<void> setGymStatus(String gymId, String status) async {
    await _gyms.doc(gymId).update(<String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update basic gym info.
  Future<void> updateGym(
    String gymId, {
    String? name,
    String? description,
    String? address,
    String? logoUrl,
    double? latitude,
    double? longitude,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (address != null) updates['address'] = address;
    if (logoUrl != null) updates['logoUrl'] = logoUrl;
    if (latitude != null) updates['latitude'] = latitude;
    if (longitude != null) updates['longitude'] = longitude;
    await _gyms.doc(gymId).update(updates);
  }

  /// Count of members belonging to a gym.
  Future<int> getMemberCount(String gymId) async {
    final snap = await _firestore
        .collection('users')
        .where('gymId', isEqualTo: gymId)
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Count of classes belonging to a gym.
  Future<int> getClassCount(String gymId) async {
    final snap = await _firestore
        .collection('classes')
        .where('gymId', isEqualTo: gymId)
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Creates a new gym and its admin account entirely client-side (no Cloud
  /// Function dependency — this app's Firebase project is on the free Spark
  /// plan, which does not support Cloud Functions). Uses a temporary
  /// secondary Firebase app to create the admin's Auth account so the
  /// currently signed-in super admin session is left untouched, mirroring
  /// [MemberService.createMember].
  ///
  /// Returns the new gym's ID. Throws [FirebaseAuthException] if the admin
  /// email is already in use, or rethrows any Firestore error after rolling
  /// back the created Auth account so no orphaned account is left behind.
  Future<String> createGymWithAdmin({
    required String gymName,
    required String adminEmail,
    required String adminPassword,
    String gymAddress = '',
    String gymDescription = '',
    double? gymLatitude,
    double? gymLongitude,
    String adminName = '',
  }) async {
    final createdBy = _auth.currentUser?.uid ?? '';

    // Use a temporary secondary app so creating the gym admin's Auth account
    // does not sign out (replace) the currently signed-in super admin.
    final appName = 'gym-create-${DateTime.now().microsecondsSinceEpoch}';
    final secondaryApp = await Firebase.initializeApp(
      name: appName,
      options: Firebase.app().options,
    );

    String? adminUid;
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: adminEmail,
        password: adminPassword,
      );

      final createdUser = credential.user;
      if (createdUser == null) {
        throw FirebaseAuthException(
          code: 'user-creation-failed',
          message: 'Firebase Auth user creation returned no user.',
        );
      }
      adminUid = createdUser.uid;
      if (adminName.isNotEmpty) {
        await createdUser.updateDisplayName(adminName);
      }

      try {
        return await writeGymAndAdminDocs(
          gymName: gymName,
          adminEmail: adminEmail,
          adminUid: adminUid,
          createdBy: createdBy,
          gymAddress: gymAddress,
          gymDescription: gymDescription,
          gymLatitude: gymLatitude,
          gymLongitude: gymLongitude,
          adminName: adminName,
        );
      } catch (_) {
        // Roll back the Auth account so no orphaned admin login is left.
        try {
          await createdUser.delete();
        } catch (_) {}
        rethrow;
      }
    } finally {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      await secondaryAuth.signOut();
      await secondaryApp.delete();
    }
  }

  /// Writes the gym document + its admin's `users` document in a single
  /// batch. Split out from [createGymWithAdmin] so the pure Firestore-write
  /// logic (gym/user document shape) can be unit-tested without needing a
  /// real Firebase Auth account — [adminUid] is assumed to already exist.
  Future<String> writeGymAndAdminDocs({
    required String gymName,
    required String adminEmail,
    required String adminUid,
    required String createdBy,
    String gymAddress = '',
    String gymDescription = '',
    double? gymLatitude,
    double? gymLongitude,
    String adminName = '',
  }) async {
    final gymRef = _gyms.doc();
    final batch = _firestore.batch();

    batch.set(gymRef, <String, dynamic>{
      'name': gymName,
      'address': gymAddress,
      'description': gymDescription,
      'logoUrl': '',
      if (gymLatitude != null) 'latitude': gymLatitude,
      if (gymLongitude != null) 'longitude': gymLongitude,
      'adminUid': adminUid,
      'adminEmail': adminEmail,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    });

    batch.set(_firestore.collection('users').doc(adminUid), <String, dynamic>{
      'email': adminEmail,
      'displayName': adminName,
      'role': 'admin',
      'roles': ['admin'],
      'gymId': gymRef.id,
      'gymIds': [gymRef.id],
      'membershipPlanId': '',
      'subscriptionStatus': 'none',
      'phoneNumber': '',
      'photoUrl': '',
      'gender': '',
      'dateOfBirth': null,
      'fitnessLevel': '',
      'emergencyContactName': '',
      'emergencyContactPhone': '',
      'healthNotes': '',
      'joinDate': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return gymRef.id;
  }

  /// Distance in kilometers between two coordinates (haversine formula).
  /// Pure/static so it's trivially unit-testable without location services.
  static double distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000.0;
  }

  /// Sorts [gyms] by distance from ([fromLat], [fromLon]) ascending. Gyms
  /// without coordinates are placed at the end, in their original relative
  /// order.
  static List<Gym> sortByDistance(
    List<Gym> gyms,
    double fromLat,
    double fromLon,
  ) {
    final located = gyms.where((g) => g.hasLocation).toList()
      ..sort((a, b) {
        final da = distanceKm(fromLat, fromLon, a.latitude!, a.longitude!);
        final db = distanceKm(fromLat, fromLon, b.latitude!, b.longitude!);
        return da.compareTo(db);
      });
    final unlocated = gyms.where((g) => !g.hasLocation).toList();
    return [...located, ...unlocated];
  }

  /// Requests (if needed) and returns the device's current position.
  /// Returns null when permission is denied or location services are off —
  /// callers should fall back to unsorted / alphabetical order in that case.
  Future<Position?> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
    } catch (_) {
      return null;
    }
  }

  /// Permanently deletes a gym and all Firestore data scoped to it.
  /// Documents are removed in 400-doc batches to stay under Firestore limits.
  /// Note: Firebase Auth accounts for gym users are not removed here —
  /// those orphaned accounts lose all meaningful data access.
  Future<void> deleteGym(String gymId) async {
    const collections = <String>[
      'classes',
      'bookings',
      'waitlists',
      'attendance',
      'membership_plans',
      'subscriptions',
      'user_subscriptions',
      'classTypes',
      'classTemplates',
      'wods',
      'wodScores',
      'personal_trainings',
      'late_cancellations',
      'notifications',
      'settings',
      'users',
    ];

    for (final col in collections) {
      await _deleteCollectionByGymId(col, gymId);
    }

    await _gyms.doc(gymId).delete();
  }

  Future<void> _deleteCollectionByGymId(
      String collectionName, String gymId) async {
    while (true) {
      final snap = await _firestore
          .collection(collectionName)
          .where('gymId', isEqualTo: gymId)
          .limit(400)
          .get();
      if (snap.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) break;
    }
  }
}
