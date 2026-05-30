import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/personal_training.dart';

class PersonalTrainingService {
  PersonalTrainingService({this.gymId = '', FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _db;

  Query<Map<String, dynamic>> get _sessionsQuery =>
      _db.collection('personal_trainings');

  bool _matchesGymId(String scopedGymId) {
    return gymId.isEmpty || scopedGymId.isEmpty || scopedGymId == gymId;
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  /// All upcoming PT sessions visible to the admin/coach.
  Stream<List<PersonalTraining>> streamAll() {
    return _sessionsQuery.snapshots().map((s) {
      final list = s.docs
          .map(PersonalTraining.fromSnapshot)
          .where((session) => _matchesGymId(session.gymId))
          .toList();
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
      return List<PersonalTraining>.unmodifiable(list);
    });
  }

  /// PT sessions assigned to a specific member.
  Stream<List<PersonalTraining>> streamForMember(String userId) {
    return _sessionsQuery
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map(PersonalTraining.fromSnapshot)
          .where((session) => _matchesGymId(session.gymId))
          .toList();
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
      return List<PersonalTraining>.unmodifiable(list);
    });
  }

  /// PT sessions created by a specific coach.
  Stream<List<PersonalTraining>> streamForCoach(String coachId) {
    return _sessionsQuery
        .where('coachId', isEqualTo: coachId)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map(PersonalTraining.fromSnapshot)
          .where((session) => _matchesGymId(session.gymId))
          .toList();
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
      return List<PersonalTraining>.unmodifiable(list);
    });
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> create({
    required String title,
    required String coachId,
    required String coachName,
    required List<String> memberIds,
    required List<String> memberNames,
    required DateTime startTime,
    required DateTime endTime,
    String notes = '',
    String location = '',
  }) async {
    await _db.collection('personal_trainings').add(<String, dynamic>{
      'gymId': gymId,
      'title': title,
      'coachId': coachId,
      'coachName': coachName,
      'memberIds': memberIds,
      'memberNames': memberNames,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'notes': notes,
      'location': location,
      'createdAt': Timestamp.now(),
    });
  }

  Future<void> update({
    required String id,
    required String title,
    required List<String> memberIds,
    required List<String> memberNames,
    required DateTime startTime,
    required DateTime endTime,
    String notes = '',
    String location = '',
  }) async {
    await _db.collection('personal_trainings').doc(id).update(<String, dynamic>{
      if (gymId.isNotEmpty) 'gymId': gymId,
      'title': title,
      'memberIds': memberIds,
      'memberNames': memberNames,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'notes': notes,
      'location': location,
    });
  }

  Future<void> delete(String id) async {
    await _db.collection('personal_trainings').doc(id).delete();
  }
}
