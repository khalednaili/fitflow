import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/app_user.dart';
import 'package:fit_flow/services/member_service.dart';

Future<void> _seedUser(
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
}

Future<AppUser> _getUser(FakeFirebaseFirestore firestore) async {
  final snap = await firestore.collection('users').doc('u1').get();
  return AppUser.fromSnapshot(snap);
}

void main() {
  group('MemberService multi-gym membership', () {
    late FakeFirebaseFirestore firestore;
    late MemberService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = MemberService(firestore: firestore);
    });

    test('joinGym sets gymId and adds it to gymIds', () async {
      await _seedUser(firestore);

      await service.joinGym(userId: 'u1', gymId: 'gymA');
      final user = await _getUser(firestore);

      expect(user.gymId, 'gymA');
      expect(user.effectiveGymIds, ['gymA']);
    });

    test('joinAdditionalGym adds a gym without changing active gym', () async {
      await _seedUser(firestore, gymId: 'gymA', gymIds: ['gymA']);

      await service.joinAdditionalGym(userId: 'u1', gymId: 'gymB');
      final user = await _getUser(firestore);

      expect(user.gymId, 'gymA');
      expect(user.effectiveGymIds.toSet(), {'gymA', 'gymB'});
      expect(user.isMultiGymMember, isTrue);
    });

    test('switchActiveGym changes active gym and keeps membership', () async {
      await _seedUser(firestore, gymId: 'gymA', gymIds: ['gymA', 'gymB']);

      await service.switchActiveGym(userId: 'u1', gymId: 'gymB');
      final user = await _getUser(firestore);

      expect(user.gymId, 'gymB');
      expect(user.effectiveGymIds.toSet(), {'gymA', 'gymB'});
    });

    test('leaveGym removes a non-active gym from membership', () async {
      await _seedUser(firestore, gymId: 'gymA', gymIds: ['gymA', 'gymB']);

      await service.leaveGym(userId: 'u1', gymId: 'gymB');
      final user = await _getUser(firestore);

      expect(user.gymId, 'gymA');
      expect(user.effectiveGymIds, ['gymA']);
    });

    test('leaveGym on the active gym switches active to a remaining gym',
        () async {
      await _seedUser(firestore, gymId: 'gymA', gymIds: ['gymA', 'gymB']);

      await service.leaveGym(userId: 'u1', gymId: 'gymA');
      final user = await _getUser(firestore);

      expect(user.gymId, 'gymB');
      expect(user.effectiveGymIds, ['gymB']);
    });

    test('leaveGym on the only gym clears the active gym', () async {
      await _seedUser(firestore, gymId: 'gymA', gymIds: ['gymA']);

      await service.leaveGym(userId: 'u1', gymId: 'gymA');
      final user = await _getUser(firestore);

      expect(user.gymId, '');
      expect(user.effectiveGymIds, isEmpty);
    });
  });
}
