import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../models/gym_class.dart';

class ClassService {
  ClassService({
    FirebaseFirestore? firestore,
    this.gymId = '',
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// When non-empty, all queries are scoped to this gym.
  final String gymId;

  Query<Map<String, dynamic>> get _classesQuery =>
      _firestore.collection('classes');

  bool _matchesGymId(String scopedGymId) {
    return gymId.isEmpty || scopedGymId.isEmpty || scopedGymId == gymId;
  }

  static String _generateToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Stream<List<GymClass>> streamClasses() {
    return _classesQuery.snapshots().map((q) {
      final classes = q.docs
          .map((doc) => GymClass.fromSnapshot(doc))
          .where((gymClass) => _matchesGymId(gymClass.gymId))
          .toList();
      return List<GymClass>.unmodifiable(classes);
    });
  }

  Stream<List<GymClass>> streamUpcomingClasses() {
    final now = DateTime.now();
    // Single-field gymId filter only — sort/filter client-side to avoid
    // requiring a composite (gymId + startTime) index.
    return _classesQuery.snapshots().map((query) {
      final list = query.docs
          .map((doc) => GymClass.fromSnapshot(doc))
          .where((c) => _matchesGymId(c.gymId) && !c.startTime.isBefore(now))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      return list;
    });
  }

  /// Streams ALL classes — past and future — ordered by startTime.
  /// Used by admin screens so past classes are always visible.
  Stream<List<GymClass>> streamAllClasses() {
    final cutoff = DateTime.now().subtract(const Duration(days: 365 * 2));
    // Single-field gymId filter only — sort/filter client-side to avoid
    // requiring a composite (gymId + startTime) index.
    return _classesQuery.snapshots().map((query) {
      final list = query.docs
          .map((doc) => GymClass.fromSnapshot(doc))
          .where((c) => _matchesGymId(c.gymId) && !c.startTime.isBefore(cutoff))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      return list;
    });
  }

  /// Stream classes where the given coach is assigned.
  Stream<List<GymClass>> streamClassesForCoach(String coachId) {
    final now = DateTime.now();
    return _classesQuery
        .where('coachIds', arrayContains: coachId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(GymClass.fromSnapshot)
          .where((c) => _matchesGymId(c.gymId) && !c.startTime.isBefore(now))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      return list;
    });
  }

  /// Stream all classes (past + future) for a coach — for history.
  Stream<List<GymClass>> streamAllClassesForCoach(String coachId) {
    return _classesQuery
        .where('coachIds', arrayContains: coachId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(GymClass.fromSnapshot)
          .where((c) => _matchesGymId(c.gymId))
          .toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
      return list;
    });
  }

  Future<GymClass?> getClassById(String classId) async {
    final doc = await _firestore.collection('classes').doc(classId).get();
    if (!doc.exists) {
      return null;
    }

    final gymClass = GymClass.fromSnapshot(doc);
    if (!_matchesGymId(gymClass.gymId)) {
      return null;
    }
    return gymClass;
  }

  /// Live stream of a single class document (e.g. for capacity changes).
  Stream<GymClass?> streamClass(String classId) {
    return _firestore
        .collection('classes')
        .doc(classId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) {
        return null;
      }

      final gymClass = GymClass.fromSnapshot(snap);
      return _matchesGymId(gymClass.gymId) ? gymClass : null;
    });
  }

  Future<void> createClass({
    required String title,
    required String coachName,
    List<String> coachIds = const <String>[],
    List<String> coachNames = const <String>[],
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    required int capacity,
    List<String> requiredOfferPlanIds = const <String>[],
    bool repeatWeekly = false,
    List<int> repeatWeekdays = const <int>[],
    int repeatForWeeks = 8,
    DateTime? recurrenceEndDate,
    int? classColorValue,
    bool dropInEnabled = false,
    double dropInPrice = 0.0,
    String classTypeId = '',
  }) async {
    final cleanCoachIds = coachIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final cleanCoachNames = coachNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final resolvedCoachName =
        cleanCoachNames.isNotEmpty ? cleanCoachNames.join(', ') : coachName;

    final cleanWeekdays = repeatWeekdays
        .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
        .toSet()
        .toList(growable: false)
      ..sort();
    final cleanRequiredOfferPlanIds = requiredOfferPlanIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final primaryRequiredOfferPlanId = cleanRequiredOfferPlanIds.isEmpty
        ? ''
        : cleanRequiredOfferPlanIds.first;

    if (!repeatWeekly || cleanWeekdays.isEmpty) {
      final payload = <String, dynamic>{
        'title': title,
        'coachName': resolvedCoachName,
        'coachIds': cleanCoachIds,
        'coachNames': cleanCoachNames,
        'description': description,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'requiredOfferPlanId': primaryRequiredOfferPlanId,
        'requiredOfferPlanIds': cleanRequiredOfferPlanIds,
        'repeatWeekly': false,
        'repeatWeekdays': const <int>[],
        'capacity': capacity,
        'bookedCount': 0,
        'waitlistCount': 0,
        'qrToken': _generateToken(),
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'dropInEnabled': dropInEnabled,
        'dropInPrice': dropInPrice,
        'gymId': gymId,
        'classTypeId': classTypeId,
      };
      if (classColorValue != null) {
        payload['classColorValue'] = classColorValue;
      }
      await _firestore.collection('classes').add(payload);
      return;
    }

    final classesCollection = _firestore.collection('classes');
    final recurrenceGroupId = classesCollection.doc().id;
    final duration = endTime.difference(startTime);
    final startDateOnly =
        DateTime(startTime.year, startTime.month, startTime.day);
    final weekStart = startDateOnly.subtract(
      Duration(days: startDateOnly.weekday - DateTime.monday),
    );
    final recurrenceEndDateOnly = recurrenceEndDate == null
        ? startDateOnly.add(Duration(days: (repeatForWeeks * 7) - 1))
        : DateTime(
            recurrenceEndDate.year,
            recurrenceEndDate.month,
            recurrenceEndDate.day,
          );
    final totalWeeks =
        (recurrenceEndDateOnly.difference(weekStart).inDays ~/ 7) + 1;

    final batch = _firestore.batch();
    var createdCount = 0;

    for (var weekOffset = 0; weekOffset < totalWeeks; weekOffset++) {
      for (final weekday in cleanWeekdays) {
        final occurrenceDate = weekStart.add(
          Duration(days: weekOffset * 7 + (weekday - DateTime.monday)),
        );

        if (occurrenceDate.isBefore(startDateOnly) ||
            occurrenceDate.isAfter(recurrenceEndDateOnly)) {
          continue;
        }

        final occurrenceStart = DateTime(
          occurrenceDate.year,
          occurrenceDate.month,
          occurrenceDate.day,
          startTime.hour,
          startTime.minute,
        );
        final occurrenceEnd = occurrenceStart.add(duration);

        final docRef = classesCollection.doc();
        final payload = <String, dynamic>{
          'title': title,
          'coachName': resolvedCoachName,
          'coachIds': cleanCoachIds,
          'coachNames': cleanCoachNames,
          'description': description,
          'startTime': Timestamp.fromDate(occurrenceStart),
          'endTime': Timestamp.fromDate(occurrenceEnd),
          'requiredOfferPlanId': primaryRequiredOfferPlanId,
          'requiredOfferPlanIds': cleanRequiredOfferPlanIds,
          'repeatWeekly': true,
          'repeatWeekdays': cleanWeekdays,
          'recurrenceGroupId': recurrenceGroupId,
          'recurrenceEndDate': Timestamp.fromDate(recurrenceEndDateOnly),
          'capacity': capacity,
          'bookedCount': 0,
          'waitlistCount': 0,
          'qrToken': _generateToken(),
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
          'dropInEnabled': dropInEnabled,
          'dropInPrice': dropInPrice,
          'gymId': gymId,
          'classTypeId': classTypeId,
        };
        if (classColorValue != null) {
          payload['classColorValue'] = classColorValue;
        }
        batch.set(docRef, payload);
        createdCount += 1;
      }
    }

    if (createdCount == 0) {
      final payload = <String, dynamic>{
        'title': title,
        'coachName': resolvedCoachName,
        'coachIds': cleanCoachIds,
        'coachNames': cleanCoachNames,
        'description': description,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'requiredOfferPlanId': primaryRequiredOfferPlanId,
        'requiredOfferPlanIds': cleanRequiredOfferPlanIds,
        'repeatWeekly': false,
        'repeatWeekdays': const <int>[],
        'capacity': capacity,
        'bookedCount': 0,
        'waitlistCount': 0,
        'qrToken': _generateToken(),
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'dropInEnabled': dropInEnabled,
        'dropInPrice': dropInPrice,
        'gymId': gymId,
        'classTypeId': classTypeId,
      };
      if (classColorValue != null) {
        payload['classColorValue'] = classColorValue;
      }
      await _firestore.collection('classes').add(payload);
      return;
    }

    await batch.commit();
  }

  Future<void> updateClass({
    required String classId,
    required String title,
    required String coachName,
    List<String> coachIds = const <String>[],
    List<String> coachNames = const <String>[],
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    required int capacity,
    List<String> requiredOfferPlanIds = const <String>[],
    int? classColorValue,
    bool dropInEnabled = false,
    double dropInPrice = 0.0,
    String classTypeId = '',
  }) async {
    final cleanCoachIds = coachIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final cleanCoachNames = coachNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final resolvedCoachName =
        cleanCoachNames.isNotEmpty ? cleanCoachNames.join(', ') : coachName;
    final cleanRequiredOfferPlanIds = requiredOfferPlanIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final primaryRequiredOfferPlanId = cleanRequiredOfferPlanIds.isEmpty
        ? ''
        : cleanRequiredOfferPlanIds.first;

    final payload = <String, dynamic>{
      'title': title,
      'coachName': resolvedCoachName,
      'coachIds': cleanCoachIds,
      'coachNames': cleanCoachNames,
      'description': description,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'requiredOfferPlanId': primaryRequiredOfferPlanId,
      'requiredOfferPlanIds': cleanRequiredOfferPlanIds,
      'capacity': capacity,
      'updatedAt': Timestamp.now(),
      'classColorValue': classColorValue ?? FieldValue.delete(),
      'dropInEnabled': dropInEnabled,
      'dropInPrice': dropInPrice,
      'classTypeId': classTypeId,
    };

    await _firestore.collection('classes').doc(classId).update(payload);
  }

  Future<void> deleteClass(String classId) async {
    await _firestore.collection('classes').doc(classId).delete();
  }

  /// Streams all upcoming classes for the gym (regardless of coach assignment).
  /// Used by the Cover tab so a coach can see classes they could cover.
  Stream<List<GymClass>> streamUpcomingClassesForGym() {
    return _classesQuery.snapshots().map((query) {
      final now = DateTime.now(); // recompute on every emission
      final list = query.docs
          .map((doc) => GymClass.fromSnapshot(doc))
          .where((c) => _matchesGymId(c.gymId) && !c.startTime.isBefore(now))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      return list;
    });
  }

  /// Adds [coachId]/[coachName] as a covering coach for a single class occurrence.
  /// Uses a transaction to keep coachIds, coachNames and coachName in sync.
  Future<void> coverClass({
    required String classId,
    required String coachId,
    required String coachName,
  }) async {
    final docRef = _firestore.collection('classes').doc(classId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) throw Exception('Class not found');

      final data = snap.data()!;
      final ids = List<String>.from(
          (data['coachIds'] as List<dynamic>? ?? []).map((e) => e.toString()));
      final names = List<String>.from(
          (data['coachNames'] as List<dynamic>? ?? [])
              .map((e) => e.toString()));

      if (!ids.contains(coachId)) {
        ids.add(coachId);
        names.add(coachName);
      }

      tx.update(docRef, <String, dynamic>{
        'coachIds': ids,
        'coachNames': names,
        'coachName': names.join(', '),
        'updatedAt': Timestamp.now(),
      });
    });
  }

  /// Removes [coachId] from a class (undo cover / resign from covering).
  Future<void> uncoverClass({
    required String classId,
    required String coachId,
  }) async {
    final docRef = _firestore.collection('classes').doc(classId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) throw Exception('Class not found');

      final data = snap.data()!;
      final ids = List<String>.from(
          (data['coachIds'] as List<dynamic>? ?? []).map((e) => e.toString()));
      final names = List<String>.from(
          (data['coachNames'] as List<dynamic>? ?? [])
              .map((e) => e.toString()));

      final idx = ids.indexOf(coachId);
      if (idx >= 0) {
        ids.removeAt(idx);
        if (idx < names.length) names.removeAt(idx);
      }

      tx.update(docRef, <String, dynamic>{
        'coachIds': ids,
        'coachNames': names,
        'coachName': names.join(', '),
        'updatedAt': Timestamp.now(),
      });
    });
  }

  /// Streams upcoming classes that match any of the given [classIds].
  /// Used by the dashboard to show a user's upcoming booked classes.
  Stream<List<GymClass>> streamUpcomingClassesForIds(Set<String> classIds) {
    if (classIds.isEmpty) {
      return Stream.value(<GymClass>[]);
    }
    return _firestore
        .collection('classes')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.now())
        .orderBy('startTime')
        .snapshots()
        .map((query) {
      final classes = query.docs
          .map((doc) => GymClass.fromSnapshot(doc))
          .where((c) => _matchesGymId(c.gymId) && classIds.contains(c.id))
          .toList();
      return List<GymClass>.unmodifiable(classes);
    });
  }

  /// Streams the count of classes a user attended this month (using bookings).
  Stream<int> streamBookingCountThisMonth(String userId) {
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    return _firestore
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(firstOfMonth))
        .snapshots()
        .map((q) => q.docs.length);
  }

  /// Returns all classes belonging to a recurrence group, sorted by startTime.
  Future<List<GymClass>> getSeriesClasses(String recurrenceGroupId) async {
    final snap = await _firestore
        .collection('classes')
        .where('recurrenceGroupId', isEqualTo: recurrenceGroupId)
        .get();
    final list = snap.docs.map(GymClass.fromSnapshot).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  /// Updates metadata fields on ALL docs in a recurrence group.
  Future<void> updateEntireSeries({
    required String recurrenceGroupId,
    required String title,
    required String coachName,
    List<String> coachIds = const [],
    List<String> coachNames = const [],
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    required int capacity,
    List<String> requiredOfferPlanIds = const [],
    int? classColorValue,
    bool dropInEnabled = false,
    double dropInPrice = 0.0,
    String classTypeId = '',
  }) async {
    final snap = await _firestore
        .collection('classes')
        .where('recurrenceGroupId', isEqualTo: recurrenceGroupId)
        .get();
    final docs = snap.docs;
    final cleanCoachIds = coachIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final cleanCoachNames = coachNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final resolvedCoachName =
        cleanCoachNames.isNotEmpty ? cleanCoachNames.join(', ') : coachName;
    final cleanOfferIds = requiredOfferPlanIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final primaryOfferId = cleanOfferIds.isEmpty ? '' : cleanOfferIds.first;
    final duration = endTime.difference(startTime);

    const batchSize = 500;
    final updatedAt = Timestamp.now();
    for (var i = 0; i < docs.length; i += batchSize) {
      final chunk = docs.sublist(i, (i + batchSize).clamp(0, docs.length));
      final batch = _firestore.batch();
      for (final doc in chunk) {
        final docStart =
            (doc.data()['startTime'] as Timestamp?)?.toDate() ?? startTime;
        final newStart = DateTime(docStart.year, docStart.month, docStart.day,
            startTime.hour, startTime.minute);
        final newEnd = newStart.add(duration);
        batch.update(doc.reference, <String, dynamic>{
          'title': title,
          'coachName': resolvedCoachName,
          'coachIds': cleanCoachIds,
          'coachNames': cleanCoachNames,
          'description': description,
          'startTime': Timestamp.fromDate(newStart),
          'endTime': Timestamp.fromDate(newEnd),
          'capacity': capacity,
          'requiredOfferPlanId': primaryOfferId,
          'requiredOfferPlanIds': cleanOfferIds,
          'classColorValue': classColorValue ?? FieldValue.delete(),
          'dropInEnabled': dropInEnabled,
          'dropInPrice': dropInPrice,
          'updatedAt': updatedAt,
          'classTypeId': classTypeId,
        });
      }
      await batch.commit();
    }
  }

  /// Updates metadata fields on docs in a recurrence group with startTime >= fromDate.
  Future<void> updateSeriesFromDate({
    required String recurrenceGroupId,
    required DateTime fromDate,
    required String title,
    required String coachName,
    List<String> coachIds = const [],
    List<String> coachNames = const [],
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    required int capacity,
    List<String> requiredOfferPlanIds = const [],
    int? classColorValue,
    bool dropInEnabled = false,
    double dropInPrice = 0.0,
    String classTypeId = '',
  }) async {
    final snap = await _firestore
        .collection('classes')
        .where('recurrenceGroupId', isEqualTo: recurrenceGroupId)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate))
        .get();
    final docs = snap.docs;
    final cleanCoachIds = coachIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final cleanCoachNames = coachNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final resolvedCoachName =
        cleanCoachNames.isNotEmpty ? cleanCoachNames.join(', ') : coachName;
    final cleanOfferIds = requiredOfferPlanIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final primaryOfferId = cleanOfferIds.isEmpty ? '' : cleanOfferIds.first;
    final duration = endTime.difference(startTime);

    const batchSize = 500;
    final updatedAt = Timestamp.now();
    for (var i = 0; i < docs.length; i += batchSize) {
      final chunk = docs.sublist(i, (i + batchSize).clamp(0, docs.length));
      final batch = _firestore.batch();
      for (final doc in chunk) {
        final docStart =
            (doc.data()['startTime'] as Timestamp?)?.toDate() ?? startTime;
        final newStart = DateTime(docStart.year, docStart.month, docStart.day,
            startTime.hour, startTime.minute);
        final newEnd = newStart.add(duration);
        batch.update(doc.reference, <String, dynamic>{
          'title': title,
          'coachName': resolvedCoachName,
          'coachIds': cleanCoachIds,
          'coachNames': cleanCoachNames,
          'description': description,
          'startTime': Timestamp.fromDate(newStart),
          'endTime': Timestamp.fromDate(newEnd),
          'capacity': capacity,
          'requiredOfferPlanId': primaryOfferId,
          'requiredOfferPlanIds': cleanOfferIds,
          'classColorValue': classColorValue ?? FieldValue.delete(),
          'dropInEnabled': dropInEnabled,
          'dropInPrice': dropInPrice,
          'updatedAt': updatedAt,
          'classTypeId': classTypeId,
        });
      }
      await batch.commit();
    }
  }

  /// Deletes all docs in a recurrence group.
  Future<void> deleteEntireSeries(String recurrenceGroupId) async {
    final snap = await _firestore
        .collection('classes')
        .where('recurrenceGroupId', isEqualTo: recurrenceGroupId)
        .get();
    const batchSize = 500;
    final docs = snap.docs;
    for (var i = 0; i < docs.length; i += batchSize) {
      final chunk = docs.sublist(i, (i + batchSize).clamp(0, docs.length));
      final batch = _firestore.batch();
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  /// Deletes docs in a recurrence group with startTime >= fromDate.
  Future<void> deleteSeriesFromDate(
      String recurrenceGroupId, DateTime fromDate) async {
    final snap = await _firestore
        .collection('classes')
        .where('recurrenceGroupId', isEqualTo: recurrenceGroupId)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate))
        .get();
    const batchSize = 500;
    final docs = snap.docs;
    for (var i = 0; i < docs.length; i += batchSize) {
      final chunk = docs.sublist(i, (i + batchSize).clamp(0, docs.length));
      final batch = _firestore.batch();
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> copyClassToDate({
    required String sourceClassId,
    required DateTime targetDate,
  }) async {
    final doc = await _firestore.collection('classes').doc(sourceClassId).get();
    if (!doc.exists) return;
    final data = doc.data()!;

    final origStart = (data['startTime'] as Timestamp).toDate();
    final origEnd = (data['endTime'] as Timestamp).toDate();
    final duration = origEnd.difference(origStart);
    final newStart = DateTime(targetDate.year, targetDate.month, targetDate.day,
        origStart.hour, origStart.minute);
    final newEnd = newStart.add(duration);

    final payload = Map<String, dynamic>.from(data);
    payload['startTime'] = Timestamp.fromDate(newStart);
    payload['endTime'] = Timestamp.fromDate(newEnd);
    payload['bookedCount'] = 0;
    payload['waitlistCount'] = 0;
    payload['qrToken'] = _generateToken();
    payload['createdAt'] = Timestamp.now();
    payload['updatedAt'] = Timestamp.now();
    payload.remove('recurrenceGroupId');
    payload.remove('recurrenceEndDate');
    payload['repeatWeekly'] = false;
    payload['repeatWeekdays'] = <int>[];

    await _firestore.collection('classes').add(payload);
  }

  /// Duplicates a series with a new date range, using config from the source series.
  Future<void> duplicateSeries({
    required String sourceRecurrenceGroupId,
    required DateTime newStartDate,
    required DateTime newEndDate,
    TimeOfDay? overrideStartTime,
    TimeOfDay? overrideEndTime,
  }) async {
    final seriesClasses = await getSeriesClasses(sourceRecurrenceGroupId);
    if (seriesClasses.isEmpty) return;

    final source = seriesClasses.first;

    final startHour = overrideStartTime?.hour ?? source.startTime.hour;
    final startMinute = overrideStartTime?.minute ?? source.startTime.minute;
    final endHour = overrideEndTime?.hour ?? source.endTime.hour;
    final endMinute = overrideEndTime?.minute ?? source.endTime.minute;

    final newStart = DateTime(
      newStartDate.year,
      newStartDate.month,
      newStartDate.day,
      startHour,
      startMinute,
    );
    final newEnd = DateTime(
      newStartDate.year,
      newStartDate.month,
      newStartDate.day,
      endHour,
      endMinute,
    );

    await createClass(
      title: source.title,
      coachName: source.coachName,
      coachIds: source.coachIds,
      coachNames: source.coachNames,
      description: source.description,
      startTime: newStart,
      endTime: newEnd,
      capacity: source.capacity,
      requiredOfferPlanIds: source.requiredOfferPlanIds,
      classColorValue: source.classColorValue,
      repeatWeekly: true,
      repeatWeekdays: source.repeatWeekdays,
      recurrenceEndDate: newEndDate,
      dropInEnabled: source.dropInEnabled,
      dropInPrice: source.dropInPrice,
    );
  }

  Future<void> updateCoachNote({
    required String classId,
    required String note,
  }) async {
    await _firestore
        .collection('classes')
        .doc(classId)
        .update(<String, dynamic>{
      'coachNote': note,
      'updatedAt': Timestamp.now(),
    });
  }
}
