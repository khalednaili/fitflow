import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/app_user.dart';

Future<AppUser> _makeUser(
  FakeFirebaseFirestore firestore, {
  String gymId = '',
  List<String> gymIds = const [],
}) async {
  await firestore.collection('users').doc('u1').set({
    'email': 'a@b.com',
    'displayName': 'Alice',
    'role': 'member',
    'gymId': gymId,
    'gymIds': gymIds,
    'membershipPlanId': '',
    'subscriptionStatus': 'active',
  });
  final snap = await firestore.collection('users').doc('u1').get();
  return AppUser.fromSnapshot(snap);
}

void main() {
  group('AppUser multi-gym membership', () {
    test('effectiveGymIds falls back to gymId when gymIds is empty', () async {
      final firestore = FakeFirebaseFirestore();
      final user = await _makeUser(firestore, gymId: 'gymA');

      expect(user.effectiveGymIds, ['gymA']);
      expect(user.isMultiGymMember, isFalse);
    });

    test('effectiveGymIds merges gymId and gymIds, deduped', () async {
      final firestore = FakeFirebaseFirestore();
      final user = await _makeUser(
        firestore,
        gymId: 'gymA',
        gymIds: ['gymA', 'gymB'],
      );

      expect(user.effectiveGymIds.toSet(), {'gymA', 'gymB'});
      expect(user.isMultiGymMember, isTrue);
    });

    test('effectiveGymIds is empty when user has no gym at all', () async {
      final firestore = FakeFirebaseFirestore();
      final user = await _makeUser(firestore);

      expect(user.effectiveGymIds, isEmpty);
      expect(user.isMultiGymMember, isFalse);
    });

    test('toJson includes effectiveGymIds under gymIds key', () {
      const user = AppUser(
        id: 'u1',
        email: 'a@b.com',
        displayName: 'Alice',
        role: 'member',
        membershipPlanId: '',
        subscriptionStatus: 'active',
        gymId: 'gymA',
        gymIds: ['gymA', 'gymB'],
      );

      final json = user.toJson();
      expect((json['gymIds'] as List).toSet(), {'gymA', 'gymB'});
      expect(json['gymId'], 'gymA');
    });

    test('fromSnapshot ignores empty-string entries in gymIds', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('u1').set({
        'email': 'a@b.com',
        'displayName': 'Alice',
        'role': 'member',
        'gymId': 'gymA',
        'gymIds': ['gymA', '', 'gymB'],
        'membershipPlanId': '',
        'subscriptionStatus': 'active',
      });
      final snap = await firestore.collection('users').doc('u1').get();
      final user = AppUser.fromSnapshot(snap);

      expect(user.gymIds, ['gymA', 'gymB']);
    });
  });
}
