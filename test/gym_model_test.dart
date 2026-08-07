import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/gym.dart';

void main() {
  group('Gym location', () {
    test('hasLocation is false when latitude/longitude are missing', () {
      final gym = Gym(
        id: '1',
        name: 'Iron Gym',
        adminUid: 'u1',
        adminEmail: 'a@b.com',
        status: 'active',
        createdAt: DateTime.now(),
        createdBy: 'super1',
      );

      expect(gym.hasLocation, isFalse);
    });

    test('hasLocation is true once both coordinates are set', () {
      final gym = Gym(
        id: '1',
        name: 'Iron Gym',
        latitude: 36.8065,
        longitude: 10.1815,
        adminUid: 'u1',
        adminEmail: 'a@b.com',
        status: 'active',
        createdAt: DateTime.now(),
        createdBy: 'super1',
      );

      expect(gym.hasLocation, isTrue);
    });

    test('copyWith updates coordinates independently', () {
      final gym = Gym(
        id: '1',
        name: 'Iron Gym',
        adminUid: 'u1',
        adminEmail: 'a@b.com',
        status: 'active',
        createdAt: DateTime.now(),
        createdBy: 'super1',
      );

      final located = gym.copyWith(latitude: 36.8, longitude: 10.2);

      expect(located.hasLocation, isTrue);
      expect(located.latitude, 36.8);
      expect(located.longitude, 10.2);
    });

    test('fromSnapshot / toJson round-trip coordinates', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('gyms').doc('g1').set({
        'name': 'Iron Gym',
        'latitude': 36.8065,
        'longitude': 10.1815,
        'adminUid': 'u1',
        'adminEmail': 'a@b.com',
        'status': 'active',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'createdBy': 'super1',
      });

      final snap = await firestore.collection('gyms').doc('g1').get();
      final gym = Gym.fromSnapshot(snap);

      expect(gym.latitude, 36.8065);
      expect(gym.longitude, 10.1815);
      expect(gym.hasLocation, isTrue);

      final json = gym.toJson();
      expect(json['latitude'], 36.8065);
      expect(json['longitude'], 10.1815);
    });

    test('fromSnapshot defaults coordinates to null when absent', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('gyms').doc('g1').set({
        'name': 'Iron Gym',
        'adminUid': 'u1',
        'adminEmail': 'a@b.com',
        'status': 'active',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'createdBy': 'super1',
      });

      final snap = await firestore.collection('gyms').doc('g1').get();
      final gym = Gym.fromSnapshot(snap);

      expect(gym.latitude, isNull);
      expect(gym.longitude, isNull);
      expect(gym.hasLocation, isFalse);
      expect(gym.toJson().containsKey('latitude'), isFalse);
      expect(gym.toJson().containsKey('longitude'), isFalse);
    });
  });
}
