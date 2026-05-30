import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/personal_record.dart';

class WorkoutTrackerService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('personalRecords');

  /// Stream all PRs for [userId], ordered by achievedAt descending.
  ///
  /// Requires a Firestore composite index on `personalRecords`:
  ///   (userId ASC, achievedAt DESC)
  Stream<List<PersonalRecord>> streamPRsForUser(String userId) => _col
      .where('userId', isEqualTo: userId)
      .orderBy('achievedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(PersonalRecord.fromSnapshot).toList());

  /// Add a new PR if [pr.id] is empty, otherwise update the existing document.
  Future<void> savePR(PersonalRecord pr) async {
    if (pr.id.isEmpty) {
      await _col.add(pr.toJson());
    } else {
      await _col.doc(pr.id).update(pr.toJson());
    }
  }

  Future<void> deletePR(String id) => _col.doc(id).delete();
}
