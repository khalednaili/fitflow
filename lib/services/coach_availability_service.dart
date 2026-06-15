import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/coach_unavailability.dart';

class CoachAvailabilityService {
  CoachAvailabilityService({required this.gymId});

  final String gymId;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('coach_unavailability');

  /// Stream all upcoming (and ongoing) unavailability entries for [coachId].
  Stream<List<CoachUnavailability>> streamUpcoming(String coachId) {
    final now = Timestamp.fromDate(DateTime.now());
    return _col
        .where('coachId', isEqualTo: coachId)
        .where('endTime', isGreaterThanOrEqualTo: now)
        .orderBy('endTime')
        .orderBy('startTime')
        .snapshots()
        .map((s) => s.docs
            .map((d) => CoachUnavailability.fromSnapshot(d))
            .toList());
  }

  /// Stream unavailability for [coachId] within [from]..[to] — used by admin.
  Stream<List<CoachUnavailability>> streamForDateRange(
    String coachId,
    DateTime from,
    DateTime to,
  ) {
    return _col
        .where('coachId', isEqualTo: coachId)
        .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .where('endTime', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .orderBy('endTime')
        .orderBy('startTime')
        .snapshots()
        .map((s) => s.docs
            .map((d) => CoachUnavailability.fromSnapshot(d))
            .toList());
  }

  /// Stream all upcoming unavailability for the whole gym — used by admin.
  Stream<List<CoachUnavailability>> streamGymUpcoming() {
    final now = Timestamp.fromDate(DateTime.now());
    return _col
        .where('gymId', isEqualTo: gymId)
        .where('endTime', isGreaterThanOrEqualTo: now)
        .orderBy('endTime')
        .orderBy('startTime')
        .snapshots()
        .map((s) => s.docs
            .map((d) => CoachUnavailability.fromSnapshot(d))
            .toList());
  }

  /// Adds a new unavailability block. Returns the created document.
  Future<CoachUnavailability> add({
    required String coachId,
    required DateTime startTime,
    required DateTime endTime,
    bool allDay = false,
    String reason = '',
  }) async {
    final now = DateTime.now();
    final data = CoachUnavailability(
      id: '',
      coachId: coachId,
      gymId: gymId,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      reason: reason,
      createdAt: now,
    ).toJson();

    final ref = await _col.add(data);
    return CoachUnavailability(
      id: ref.id,
      coachId: coachId,
      gymId: gymId,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      reason: reason,
      createdAt: now,
    );
  }

  /// Deletes an unavailability block by its document ID.
  Future<void> delete(String id) => _col.doc(id).delete();
}
