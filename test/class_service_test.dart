import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/services/class_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ClassService sut;

  setUp(() {
    db = FakeFirebaseFirestore();
    sut = ClassService(gymId: '', firestore: db);
  });

  Future<void> addClass({
    required String id,
    required DateTime start,
    Duration duration = const Duration(hours: 1),
    String gymId = '',
  }) =>
      db.collection('classes').doc(id).set({
        'title': id,
        'gymId': gymId,
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(start.add(duration)),
        'capacity': 10,
        'bookedCount': 0,
      });

  final past = DateTime.now().subtract(const Duration(days: 1));
  final soon = DateTime.now().add(const Duration(hours: 2));
  final later = DateTime.now().add(const Duration(days: 3));

  group('streamUpcomingClasses', () {
    test('excludes past classes and sorts upcoming by start time', () async {
      await addClass(id: 'past', start: past);
      await addClass(id: 'later', start: later);
      await addClass(id: 'soon', start: soon);

      final list = await sut.streamUpcomingClasses().first;

      expect(list.map((c) => c.id).toList(), ['soon', 'later']);
    });

    test('returns a mutable list (sortable without throwing)', () async {
      await addClass(id: 'soon', start: soon);
      await addClass(id: 'later', start: later);

      final list = await sut.streamUpcomingClasses().first;
      // Would throw "Unsupported operation: sort" on an unmodifiable list.
      expect(
        () => list.sort((a, b) => b.startTime.compareTo(a.startTime)),
        returnsNormally,
      );
    });
  });

  group('streamClasses', () {
    test('returns a mutable list', () async {
      await addClass(id: 'a', start: soon);
      final list = await sut.streamClasses().first;
      expect(() => list.sort((a, b) => a.id.compareTo(b.id)), returnsNormally);
    });
  });

  group('streamUpcomingClassesForIds', () {
    test('returns only the requested upcoming classes, mutable', () async {
      await addClass(id: 'past', start: past);
      await addClass(id: 'soon', start: soon);
      await addClass(id: 'later', start: later);

      final list =
          await sut.streamUpcomingClassesForIds({'soon', 'later', 'past'}).first;

      // 'past' is excluded by the upcoming filter even though requested.
      expect(list.map((c) => c.id).toSet(), {'soon', 'later'});
      expect(
        () => list.sort((a, b) => a.id.compareTo(b.id)),
        returnsNormally,
      );
    });

    test('empty id set yields an empty list', () async {
      await addClass(id: 'soon', start: soon);
      final list = await sut.streamUpcomingClassesForIds(<String>{}).first;
      expect(list, isEmpty);
    });
  });
}
