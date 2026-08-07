import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/gym.dart';
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

  group('GymService distance sorting', () {
    // Tunis (36.8065, 10.1815), Sfax (34.7406, 10.7603), Sousse (35.8256, 10.6084)
    late Gym tunis, sfax, sousse, noLocation;

    setUpAll(() {
      tunis = Gym(
        id: 'tunis',
        name: 'Tunis Gym',
        latitude: 36.8065,
        longitude: 10.1815,
        adminUid: 'u1',
        adminEmail: 'a@b.com',
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'super1',
      );
      sfax = Gym(
        id: 'sfax',
        name: 'Sfax Gym',
        latitude: 34.7406,
        longitude: 10.7603,
        adminUid: 'u1',
        adminEmail: 'a@b.com',
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'super1',
      );
      sousse = Gym(
        id: 'sousse',
        name: 'Sousse Gym',
        latitude: 35.8256,
        longitude: 10.6084,
        adminUid: 'u1',
        adminEmail: 'a@b.com',
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'super1',
      );
      noLocation = Gym(
        id: 'nowhere',
        name: 'No Location Gym',
        adminUid: 'u1',
        adminEmail: 'a@b.com',
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'super1',
      );
    });

    test('distanceKm returns 0 for identical coordinates', () {
      expect(GymService.distanceKm(36.8065, 10.1815, 36.8065, 10.1815), 0.0);
    });

    test('distanceKm is symmetric and positive for distinct points', () {
      final d1 = GymService.distanceKm(
          tunis.latitude!, tunis.longitude!, sfax.latitude!, sfax.longitude!);
      final d2 = GymService.distanceKm(
          sfax.latitude!, sfax.longitude!, tunis.latitude!, tunis.longitude!);

      expect(d1, greaterThan(0));
      expect(d1, closeTo(d2, 0.001));
    });

    test('sortByDistance orders located gyms nearest-first from Tunis', () {
      final sorted = GymService.sortByDistance(
        [sfax, tunis, sousse],
        36.8065,
        10.1815,
      );

      expect(sorted.map((g) => g.id).toList(), ['tunis', 'sousse', 'sfax']);
    });

    test('sortByDistance places gyms without coordinates at the end', () {
      final sorted = GymService.sortByDistance(
        [noLocation, sfax, tunis],
        36.8065,
        10.1815,
      );

      expect(sorted.last.id, 'nowhere');
      expect(sorted.first.id, 'tunis');
    });
  });

  group('GymService.getGymsByIds', () {
    late FakeFirebaseFirestore firestore;
    late GymService service;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      service = GymService(firestore: firestore);
      await firestore.collection('gyms').doc('g1').set({
        'name': 'Gym One',
        'adminUid': 'u1',
        'adminEmail': 'a@b.com',
        'status': 'active',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'createdBy': 'super1',
      });
      await firestore.collection('gyms').doc('g2').set({
        'name': 'Gym Two',
        'adminUid': 'u1',
        'adminEmail': 'a@b.com',
        'status': 'active',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'createdBy': 'super1',
      });
    });

    test('returns gyms matching the given ids', () async {
      final gyms = await service.getGymsByIds(['g1', 'g2']);

      expect(gyms.map((g) => g.id).toSet(), {'g1', 'g2'});
    });

    test('ignores ids that do not exist', () async {
      final gyms = await service.getGymsByIds(['g1', 'missing']);

      expect(gyms.map((g) => g.id).toList(), ['g1']);
    });

    test('returns empty list for empty input', () async {
      final gyms = await service.getGymsByIds([]);

      expect(gyms, isEmpty);
    });
  });
}
