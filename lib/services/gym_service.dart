import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/gym.dart';

class GymService {
  GymService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (address != null) updates['address'] = address;
    if (logoUrl != null) updates['logoUrl'] = logoUrl;
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
