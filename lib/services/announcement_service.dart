import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/gym_announcement.dart';

class AnnouncementService {
  AnnouncementService({required this.gymId})
      : _firestore = FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('gyms').doc(gymId).collection('announcements');

  /// Stream active, non-expired announcements (member-facing).
  /// Queries only `isActive=true` to avoid composite index requirement.
  /// Client-side expiry filtering applied.
  Stream<List<GymAnnouncement>> streamActiveAnnouncements() {
    return _col
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map(GymAnnouncement.fromDoc)
            .where((a) => !a.isExpired)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  /// Stream all announcements (admin-facing).
  Stream<List<GymAnnouncement>> streamAll() {
    return _col.snapshots().map((snap) {
      final list = snap.docs.map(GymAnnouncement.fromDoc).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> create({
    required String title,
    required String body,
    required AnnouncementType type,
    required AnnouncementPriority priority,
    required String createdBy,
    DateTime? expiresAt,
  }) async {
    await _col.add(<String, dynamic>{
      'gymId': gymId,
      'title': title,
      'body': body,
      'type': type.name,
      'priority': priority.name,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
      'version': 0,
    });
  }

  Future<void> update(GymAnnouncement announcement) async {
    await _col.doc(announcement.id).update(announcement.toMap());
  }

  Future<void> toggleActive(String id, bool isActive) async {
    await _col.doc(id).update({'isActive': isActive});
  }

  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }
}
