import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/personal_record.dart';
import 'package:fit_flow/services/progress_service.dart';

void main() {
  group('ProgressService.streamProgress', () {
    late FakeFirebaseFirestore db;
    late ProgressService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = ProgressService(firestore: db);
    });

    test('reflects a newly added personal record without a new booking',
        () async {
      const uid = 'user-1';
      final events = <ProgressData>[];
      final sub = service.streamProgress(uid).listen(events.add);
      addTearDown(sub.cancel);

      // Wait for the initial (empty) snapshot from both underlying streams.
      await Future.delayed(const Duration(milliseconds: 50));
      expect(events, isNotEmpty);
      expect(events.last.prsByExercise, isEmpty);

      // Adding a PR (with no corresponding booking change) must still be
      // reflected — this is the regression this test guards: previously PRs
      // were only re-read via `.first` whenever the *bookings* stream fired,
      // so a PR added elsewhere never appeared until the next check-in.
      await db.collection('personalRecords').add(
            PersonalRecord(
              id: '',
              userId: uid,
              exerciseName: 'Front Squat',
              value: '100 kg',
              unit: 'kg',
              achievedAt: DateTime(2026, 1, 1),
            ).toJson(),
          );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(events.last.prsByExercise.keys, contains('Front Squat'));
    });
  });
}
