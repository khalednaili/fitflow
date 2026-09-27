import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/gym_class.dart';

void main() {
  group('GymClass.fromSnapshot', () {
    test('parses gymId from the document', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('classes').doc('c1');
      await ref.set({
        'title': 'CrossFit',
        'gymId': 'gym_123',
        'coachName': 'Coach A',
        'startTime': Timestamp.fromDate(DateTime(2026, 1, 1, 9)),
        'endTime': Timestamp.fromDate(DateTime(2026, 1, 1, 10)),
        'capacity': 10,
      });

      final snap = await ref.get();
      final gymClass = GymClass.fromSnapshot(snap);

      expect(gymClass.gymId, 'gym_123');
    });

    test('defaults gymId to empty string when field is missing', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('classes').doc('c1');
      await ref.set({
        'title': 'Legacy class without gymId',
      });

      final snap = await ref.get();
      final gymClass = GymClass.fromSnapshot(snap);

      expect(gymClass.gymId, '');
    });
  });

  group('GymClass.toJson', () {
    test('round-trips gymId through toJson -> fromSnapshot', () async {
      final original = GymClass(
        id: '',
        title: 'CrossFit',
        coachName: 'Coach A',
        description: '',
        startTime: DateTime(2026, 1, 1, 9),
        endTime: DateTime(2026, 1, 1, 10),
        requiredOfferPlanId: '',
        repeatWeekly: false,
        repeatWeekdays: const [],
        capacity: 10,
        bookedCount: 0,
        waitlistCount: 0,
        gymId: 'gym_456',
      );

      final db = FakeFirebaseFirestore();
      final ref = db.collection('classes').doc('c1');
      await ref.set(original.toJson());

      final snap = await ref.get();
      final roundTripped = GymClass.fromSnapshot(snap);

      expect(roundTripped.gymId, 'gym_456');
    });
  });
}
