import 'package:cloud_firestore/cloud_firestore.dart';

class PersonalRecord {
  const PersonalRecord({
    required this.id,
    required this.userId,
    required this.exerciseName,
    required this.value,
    required this.unit,
    this.notes = '',
    required this.achievedAt,
  });

  final String id;
  final String userId;
  final String exerciseName;

  /// e.g. "100kg", "3:45", "50 reps"
  final String value;

  /// One of: 'kg', 'lbs', 'time', 'reps', 'other'
  final String unit;

  final String notes;
  final DateTime achievedAt;

  factory PersonalRecord.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return PersonalRecord(
      id: snap.id,
      userId: (d['userId'] ?? '') as String,
      exerciseName: (d['exerciseName'] ?? '') as String,
      value: (d['value'] ?? '') as String,
      unit: (d['unit'] ?? 'other') as String,
      notes: (d['notes'] ?? '') as String,
      achievedAt: (d['achievedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'exerciseName': exerciseName,
        'value': value,
        'unit': unit,
        'notes': notes,
        'achievedAt': Timestamp.fromDate(achievedAt),
      };
}
