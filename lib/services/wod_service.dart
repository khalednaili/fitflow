import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/wod_entry.dart';

class WodService {
  WodService({this.gymId = '', FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('wods');

  CollectionReference<Map<String, dynamic>> get _scores =>
      _db.collection('wodScores');

  Query<Map<String, dynamic>> get _wodQuery => _col;

  bool _matchesGymId(String scopedGymId) {
    return gymId.isEmpty || scopedGymId.isEmpty || scopedGymId == gymId;
  }

  Query<Map<String, dynamic>> get _scoreQuery {
    Query<Map<String, dynamic>> query = _scores;
    if (gymId.isNotEmpty) {
      query = query.where('gymId', isEqualTo: gymId);
    }
    return query;
  }

  // ── WOD streams ────────────────────────────────────────────────────────────

  /// Stream WODs for a given date, optionally filtered by [classTypeId].
  /// When [classTypeId] is empty/null all WODs for that day are returned.
  Stream<List<WodEntry>> streamForDate(DateTime date,
      {String classTypeId = ''}) {
    final day = DateTime(date.year, date.month, date.day);
    var query = _wodQuery.where('date', isEqualTo: Timestamp.fromDate(day));
    if (classTypeId.isNotEmpty) {
      query = query.where('classTypeId', isEqualTo: classTypeId);
    }
    return query.snapshots().map((s) {
      final list = s.docs
          .map(WodEntry.fromSnapshot)
          .where((entry) => _matchesGymId(entry.gymId))
          .toList();
      list.sort((a, b) => a.date.compareTo(b.date));
      return List<WodEntry>.unmodifiable(list);
    });
  }

  Stream<List<WodEntry>> streamRecent(int limit) => _wodQuery.snapshots().map((s) {
        final list = s.docs
            .map(WodEntry.fromSnapshot)
            .where((entry) => _matchesGymId(entry.gymId))
            .toList();
        list.sort((a, b) => b.date.compareTo(a.date));
        return List<WodEntry>.unmodifiable(list.take(limit).toList());
      });

  // ── CRUD ───────────────────────────────────────────────────────────────────

  /// Returns true if a WOD already exists for [date] + [classTypeId].
  /// Pass [excludeId] when editing so the current document is not counted.
  Future<bool> existsForDateAndType(DateTime date, String classTypeId,
      {String excludeId = ''}) async {
    final day = DateTime(date.year, date.month, date.day);
    final snap = await _wodQuery
        .where('date', isEqualTo: Timestamp.fromDate(day))
        .where('classTypeId', isEqualTo: classTypeId)
        .get();
    final docs = excludeId.isEmpty
        ? snap.docs
        : snap.docs.where((d) => d.id != excludeId);
    return docs.any((doc) {
      final entry = WodEntry.fromSnapshot(doc);
      return _matchesGymId(entry.gymId);
    });
  }

  Future<void> create(WodEntry w) => _col.add(<String, dynamic>{
        ...w.toJson(),
        'gymId': gymId,
      });

  Future<void> update(WodEntry w) => _col.doc(w.id).update(<String, dynamic>{
        ...w.toJson(),
        if (gymId.isNotEmpty) 'gymId': gymId,
      });

  Future<void> delete(String id) => _col.doc(id).delete();

  // ── Scores ─────────────────────────────────────────────────────────────────

  Stream<List<WodScore>> streamScoresForWod(String wodId) => _scoreQuery
      .where('wodId', isEqualTo: wodId)
      .snapshots()
      .map((s) => s.docs.map(WodScore.fromSnapshot).toList());

  Stream<WodScore?> streamMyScore(String wodId, String userId) => _scoreQuery
      .where('wodId', isEqualTo: wodId)
      .where('userId', isEqualTo: userId)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : WodScore.fromSnapshot(s.docs.first));

  Future<void> saveScore(WodScore score) async {
    if (score.id.isEmpty) {
      await _scores.add(<String, dynamic>{
        ...score.toJson(),
        'gymId': gymId,
      });
    } else {
      await _scores.doc(score.id).update(<String, dynamic>{
        ...score.toJson(),
        if (gymId.isNotEmpty) 'gymId': gymId,
      });
    }
  }

  /// Stream all scores for [userId], sorted client-side by loggedAt descending.
  Stream<List<WodScore>> streamScoresForUser(String userId) => _scoreQuery
      .where('userId', isEqualTo: userId)
      .snapshots()
      .map((s) {
        final list = s.docs.map(WodScore.fromSnapshot).toList();
        list.sort((a, b) {
          final aLoggedAt = a.loggedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bLoggedAt = b.loggedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bLoggedAt.compareTo(aLoggedAt);
        });
        return List<WodScore>.unmodifiable(list);
      });

  Future<void> deleteScore(String id) => _scores.doc(id).delete();
}
