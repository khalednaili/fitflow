import 'package:cloud_firestore/cloud_firestore.dart';

class PersonalTraining {
  const PersonalTraining({
    required this.id,
    required this.title,
    required this.coachId,
    required this.coachName,
    required this.memberIds,
    required this.memberNames,
    required this.startTime,
    required this.endTime,
    this.notes = '',
    this.location = '',
    required this.createdAt,
    this.gymId = '',
  });

  final String id;
  final String title;
  final String coachId;
  final String coachName;
  final List<String> memberIds;
  final List<String> memberNames;
  final DateTime startTime;
  final DateTime endTime;
  final String notes;
  final String location;
  final DateTime createdAt;
  final String gymId;

  factory PersonalTraining.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? <String, dynamic>{};
    return PersonalTraining(
      id: snap.id,
      title: (d['title'] ?? 'Personal Training') as String,
      coachId: (d['coachId'] ?? '') as String,
      coachName: (d['coachName'] ?? '') as String,
      memberIds: ((d['memberIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList()),
      memberNames: ((d['memberNames'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList()),
      startTime: (d['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (d['endTime'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(hours: 1)),
      notes: (d['notes'] ?? '') as String,
      location: (d['location'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      gymId: (d['gymId'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'coachId': coachId,
        'coachName': coachName,
        'memberIds': memberIds,
        'memberNames': memberNames,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'notes': notes,
        'location': location,
        'createdAt': Timestamp.fromDate(createdAt),
        'gymId': gymId,
      };
}
