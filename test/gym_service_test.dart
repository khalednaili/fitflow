import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/services/gym_service.dart';

void main() {
  group('GymService location', () {
    late FakeFirebaseFirestore firestore;
    late GymService service;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      service = GymService(firestore: firestore);
      await firestore.collection('gyms').doc('g1').set({
        'name': 'Iron Gym',
        'adminUid': 'u1',
        'adminEmail': 'a@b.com',
        'status': 'active',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'createdBy': 'super1',
      });
    });

    test('updateGym sets latitude/longitude', () async {
      await service.updateGym('g1', latitude: 36.8065, longitude: 10.1815);

      final gym = await service.getGym('g1');

      expect(gym, isNotNull);
      expect(gym!.latitude, 36.8065);
      expect(gym.longitude, 10.1815);
      expect(gym.hasLocation, isTrue);
    });

    test('updateGym leaves coordinates untouched when not provided', () async {
      await service.updateGym('g1', latitude: 36.8065, longitude: 10.1815);
      await service.updateGym('g1', name: 'Renamed Gym');

      final gym = await service.getGym('g1');

      expect(gym!.name, 'Renamed Gym');
      expect(gym.latitude, 36.8065);
      expect(gym.longitude, 10.1815);
    });

    test('streamActiveGyms includes coordinates for located gyms', () async {
      await service.updateGym('g1', latitude: 36.8065, longitude: 10.1815);

      final gyms = await service.streamActiveGyms().first;

      expect(gyms, hasLength(1));
      expect(gyms.first.hasLocation, isTrue);
    });
  });
}
