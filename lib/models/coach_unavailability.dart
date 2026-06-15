import 'package:cloud_firestore/cloud_firestore.dart';

/// A time block during which a coach is unavailable.
/// Stored in the `coach_unavailability` Firestore collection.
class CoachUnavailability {
  const CoachUnavailability({
    required this.id,
    required this.coachId,
    required this.gymId,
    required this.startTime,
    required this.endTime,
    this.allDay = false,
    this.reason = '',
    required this.createdAt,
  });

  final String id;
  final String coachId;
  final String gymId;
  final DateTime startTime;
  final DateTime endTime;

  /// When true the block covers the full day(s); times are ignored in display.
  final bool allDay;

  /// Free-text reason: e.g. "Sick", "Vacation", "Personal", "Other".
  final String reason;
  final DateTime createdAt;

  factory CoachUnavailability.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data() ?? {};
    return CoachUnavailability(
      id: snap.id,
      coachId: (d['coachId'] ?? '') as String,
      gymId: (d['gymId'] ?? '') as String,
      startTime:
          (d['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (d['endTime'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(hours: 1)),
      allDay: (d['allDay'] ?? false) as bool,
      reason: (d['reason'] ?? '') as String,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'coachId': coachId,
        'gymId': gymId,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'allDay': allDay,
        'reason': reason,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
