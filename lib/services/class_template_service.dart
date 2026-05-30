import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/class_template.dart';
import '../models/gym_class.dart';

class ClassTemplateService {
  ClassTemplateService({this.gymId = '', FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('classTemplates');

  Query<Map<String, dynamic>> get _templatesQuery => _col;

  bool _matchesGymId(String scopedGymId) {
    return gymId.isEmpty || scopedGymId.isEmpty || scopedGymId == gymId;
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  Stream<List<ClassTemplate>> streamAll() => _templatesQuery.snapshots().map((s) {
        final list = s.docs
            .map(ClassTemplate.fromSnapshot)
            .where((template) => _matchesGymId(template.gymId))
            .toList();
        list.sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
        return List<ClassTemplate>.unmodifiable(list);
      });

  Stream<List<ClassTemplate>> streamActive() =>
      _templatesQuery.where('active', isEqualTo: true).snapshots().map((s) {
        final list = s.docs
            .map(ClassTemplate.fromSnapshot)
            .where((template) => _matchesGymId(template.gymId))
            .toList();
        list.sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
        return List<ClassTemplate>.unmodifiable(list);
      });

  // ── CRUD ───────────────────────────────────────────────────────────────────

  Future<void> create(ClassTemplate t) => _col.add(<String, dynamic>{
        ...t.toJson(),
        'gymId': gymId,
      });

  Future<void> update(ClassTemplate t) =>
      _col.doc(t.id).update(<String, dynamic>{
        ...t.toJson(),
        if (gymId.isNotEmpty) 'gymId': gymId,
      });

  Future<void> toggleActive(String id, bool active) => _col.doc(id).update({
        'active': active,
        if (gymId.isNotEmpty) 'gymId': gymId,
      });

  Future<void> delete(String id) => _col.doc(id).delete();

  // ── Generate week of classes ───────────────────────────────────────────────

  /// Generates GymClass documents for every active template for the ISO week
  /// containing [weekDate]. Skips slots where a class with the same title and
  /// startTime already exists.
  Future<int> generateWeek(DateTime weekDate) async {
    // Find Monday of the requested week
    final monday = weekDate.subtract(Duration(days: weekDate.weekday - 1));

    final templates = await _templatesQuery
        .where('active', isEqualTo: true)
        .get()
        .then(
          (s) => s.docs
              .map(ClassTemplate.fromSnapshot)
              .where((template) => _matchesGymId(template.gymId))
              .toList(),
        );

    final classes = _db.collection('classes');
    int created = 0;

    for (final t in templates) {
      // day 1=Mon … 7=Sun
      final classDate = monday.add(Duration(days: t.dayOfWeek - 1));
      final start = DateTime(
        classDate.year,
        classDate.month,
        classDate.day,
        t.startHour,
        t.startMinute,
      );
      final end = start.add(Duration(minutes: t.durationMinutes));

      // Idempotency check: skip if already exists
      final existing = await classes
          .where('title', isEqualTo: t.title)
          .where('startTime', isEqualTo: Timestamp.fromDate(start))
          .get();
      final hasExistingForGym = existing.docs.any((doc) {
        final scopedGymId = (doc.data()['gymId'] ?? '') as String;
        return _matchesGymId(scopedGymId);
      });
      if (hasExistingForGym) continue;

      final gymClass = GymClass(
        id: '',
        title: t.title,
        coachName: t.coachNames.isNotEmpty ? t.coachNames.first : '',
        coachIds: t.coachIds,
        coachNames: t.coachNames,
        description: t.description,
        startTime: start,
        endTime: end,
        requiredOfferPlanId: t.requiredOfferPlanIds.isNotEmpty
            ? t.requiredOfferPlanIds.first
            : '',
        requiredOfferPlanIds: t.requiredOfferPlanIds,
        repeatWeekly: false,
        repeatWeekdays: const [],
        capacity: t.capacity,
        bookedCount: 0,
        waitlistCount: 0,
        classColorValue: t.classColorValue,
      );
      await classes.add(<String, dynamic>{
        ...gymClass.toJson(),
        'gymId': gymId,
      });
      created++;
    }
    return created;
  }
}
