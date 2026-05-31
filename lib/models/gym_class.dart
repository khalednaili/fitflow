import 'package:cloud_firestore/cloud_firestore.dart';

class GymClass {
  const GymClass({
    required this.id,
    required this.title,
    required this.coachName,
    this.coachIds = const <String>[],
    this.coachNames = const <String>[],
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.requiredOfferPlanId,
    this.requiredOfferPlanIds = const <String>[],
    this.gymId = '',
    required this.repeatWeekly,
    required this.repeatWeekdays,
    required this.capacity,
    required this.bookedCount,
    required this.waitlistCount,
    this.classColorValue,
    this.qrToken = '',
    this.dropInEnabled = false,
    this.dropInPrice = 0.0,
    this.coachNote = '',
    this.recurrenceGroupId,
    this.recurrenceEndDate,
  });

  final String id;
  final String title;
  final String coachName;
  final List<String> coachIds;
  final List<String> coachNames;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String requiredOfferPlanId;
  final List<String> requiredOfferPlanIds;
  final String gymId;
  final bool repeatWeekly;
  final List<int> repeatWeekdays;
  final int capacity;
  final int bookedCount;
  final int waitlistCount;
  final int? classColorValue;
  final String qrToken;
  final bool dropInEnabled;
  final double dropInPrice;
  final String coachNote;
  final String? recurrenceGroupId;
  final DateTime? recurrenceEndDate;

  bool get isFull => bookedCount >= capacity;
  bool get hasOfferRequirement => requiredOfferPlanIds.isNotEmpty;

  factory GymClass.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawWeekdays = (data['repeatWeekdays'] as List<dynamic>? ??
            <dynamic>[])
        .map((item) => item is int ? item : int.tryParse(item.toString()) ?? 0)
        .where((day) => day >= 1 && day <= 7)
        .toList(growable: false);

    final parsedOfferPlanIds =
        ((data['requiredOfferPlanIds'] as List<dynamic>? ?? <dynamic>[])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false));
    final legacyOfferPlanId = (data['requiredOfferPlanId'] ?? '') as String;
    final parsedColorValue = data['classColorValue'];

    return GymClass(
      id: snapshot.id,
      title: (data['title'] ?? '') as String,
      coachName: (data['coachName'] ?? '') as String,
      coachIds: ((data['coachIds'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false)),
      coachNames: ((data['coachNames'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false)),
      description: (data['description'] ?? '') as String,
      startTime: (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (data['endTime'] as Timestamp?)?.toDate() ??
          ((data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now())
              .add(const Duration(hours: 1)),
      requiredOfferPlanId: parsedOfferPlanIds.isNotEmpty
          ? parsedOfferPlanIds.first
          : legacyOfferPlanId,
      requiredOfferPlanIds: parsedOfferPlanIds.isNotEmpty
          ? parsedOfferPlanIds
          : (legacyOfferPlanId.trim().isEmpty
              ? const <String>[]
              : <String>[legacyOfferPlanId.trim()]),
      repeatWeekly: (data['repeatWeekly'] ?? false) as bool,
      repeatWeekdays: rawWeekdays,
      capacity: (data['capacity'] ?? 0) as int,
      bookedCount: (data['bookedCount'] ?? 0) as int,
      waitlistCount: (data['waitlistCount'] ?? 0) as int,
      classColorValue: parsedColorValue is int
          ? parsedColorValue
          : (parsedColorValue is num ? parsedColorValue.toInt() : null),
      qrToken: (data['qrToken'] ?? '') as String,
      dropInEnabled: (data['dropInEnabled'] ?? false) as bool,
      dropInPrice: ((data['dropInPrice'] ?? 0.0) as num).toDouble(),
      coachNote: (data['coachNote'] ?? '') as String,
      recurrenceGroupId: data['recurrenceGroupId'] as String?,
      recurrenceEndDate: (data['recurrenceEndDate'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'coachName': coachName,
      'coachIds': coachIds,
      'coachNames': coachNames,
      'description': description,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'requiredOfferPlanId': requiredOfferPlanId,
      'requiredOfferPlanIds': requiredOfferPlanIds,
      'repeatWeekly': repeatWeekly,
      'repeatWeekdays': repeatWeekdays,
      'capacity': capacity,
      'bookedCount': bookedCount,
      'waitlistCount': waitlistCount,
      'classColorValue': classColorValue,
      'qrToken': qrToken,
      'dropInEnabled': dropInEnabled,
      'dropInPrice': dropInPrice,
      'coachNote': coachNote,
      'recurrenceGroupId': recurrenceGroupId,
      'recurrenceEndDate': recurrenceEndDate != null
          ? Timestamp.fromDate(recurrenceEndDate!)
          : null,
    };
  }
}
