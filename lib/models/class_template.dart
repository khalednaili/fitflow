import 'package:cloud_firestore/cloud_firestore.dart';

/// A weekly recurring class template used to auto-generate GymClass documents.
class ClassTemplate {
  const ClassTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.dayOfWeek, // 1=Mon … 7=Sun (ISO weekday)
    required this.startHour,
    required this.startMinute,
    required this.durationMinutes,
    required this.capacity,
    this.coachIds = const [],
    this.coachNames = const [],
    this.requiredOfferPlanIds = const [],
    this.classColorValue,
    this.active = true,
    this.createdAt,
    this.gymId = '',
  });

  final String id;
  final String title;
  final String description;
  final int dayOfWeek;
  final int startHour;
  final int startMinute;
  final int durationMinutes;
  final int capacity;
  final List<String> coachIds;
  final List<String> coachNames;
  final List<String> requiredOfferPlanIds;
  final int? classColorValue;
  final bool active;
  final DateTime? createdAt;
  final String gymId;

  String get dayName {
    const days = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[dayOfWeek.clamp(1, 7)];
  }

  String get timeLabel {
    final hh = startHour.toString().padLeft(2, '0');
    final mm = startMinute.toString().padLeft(2, '0');
    final endTotal = startHour * 60 + startMinute + durationMinutes;
    final eh = (endTotal ~/ 60).toString().padLeft(2, '0');
    final em = (endTotal % 60).toString().padLeft(2, '0');
    return '$hh:$mm – $eh:$em';
  }

  factory ClassTemplate.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return ClassTemplate(
      id: snap.id,
      title: (d['title'] ?? '') as String,
      description: (d['description'] ?? '') as String,
      dayOfWeek: (d['dayOfWeek'] ?? 1) as int,
      startHour: (d['startHour'] ?? 6) as int,
      startMinute: (d['startMinute'] ?? 0) as int,
      durationMinutes: (d['durationMinutes'] ?? 60) as int,
      capacity: (d['capacity'] ?? 10) as int,
      coachIds: List<String>.from(d['coachIds'] ?? []),
      coachNames: List<String>.from(d['coachNames'] ?? []),
      requiredOfferPlanIds: List<String>.from(d['requiredOfferPlanIds'] ?? []),
      classColorValue:
          d['classColorValue'] is int ? d['classColorValue'] as int : null,
      active: (d['active'] ?? true) as bool,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      gymId: (d['gymId'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'dayOfWeek': dayOfWeek,
        'startHour': startHour,
        'startMinute': startMinute,
        'durationMinutes': durationMinutes,
        'capacity': capacity,
        'coachIds': coachIds,
        'coachNames': coachNames,
        'requiredOfferPlanIds': requiredOfferPlanIds,
        'classColorValue': classColorValue,
        'active': active,
        'gymId': gymId,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  ClassTemplate copyWith({
    String? title,
    String? description,
    int? dayOfWeek,
    int? startHour,
    int? startMinute,
    int? durationMinutes,
    int? capacity,
    List<String>? coachIds,
    List<String>? coachNames,
    List<String>? requiredOfferPlanIds,
    int? classColorValue,
    bool? active,
  }) =>
      ClassTemplate(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        startHour: startHour ?? this.startHour,
        startMinute: startMinute ?? this.startMinute,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        capacity: capacity ?? this.capacity,
        coachIds: coachIds ?? this.coachIds,
        coachNames: coachNames ?? this.coachNames,
        requiredOfferPlanIds: requiredOfferPlanIds ?? this.requiredOfferPlanIds,
        classColorValue: classColorValue ?? this.classColorValue,
        active: active ?? this.active,
        createdAt: createdAt,
        gymId: gymId,
      );
}
