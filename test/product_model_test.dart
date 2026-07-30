import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/product.dart';

void main() {
  group('Product', () {
    test('isUnlimitedStock / inStock reflect stockType', () {
      final unlimited = Product(
        id: '1',
        name: 'Water',
        stockType: 'unlimited',
        stock: 0,
        createdAt: DateTime.now(),
      );
      final limitedInStock = unlimited.copyWith(stockType: 'limited', stock: 5);
      final limitedOutOfStock =
          unlimited.copyWith(stockType: 'limited', stock: 0);

      expect(unlimited.isUnlimitedStock, isTrue);
      expect(unlimited.inStock, isTrue);
      expect(limitedInStock.isUnlimitedStock, isFalse);
      expect(limitedInStock.inStock, isTrue);
      expect(limitedOutOfStock.inStock, isFalse);
    });

    test('imageUrl returns first uploaded image or empty string', () {
      final noImages = Product(id: '1', name: 'x', createdAt: DateTime.now());
      final withImages = noImages.copyWith(imageUrls: ['a.png', 'b.png']);

      expect(noImages.imageUrl, '');
      expect(withImages.imageUrl, 'a.png');
    });

    test('fromSnapshot / toJson round-trip all fields', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('products').doc('p1').set({
        'name': 'Creatine',
        'category': 'Supplements',
        'sku': 'CR-1',
        'cost': 8,
        'retailPrice': 20,
        'vatPercent': 19,
        'stockType': 'limited',
        'stock': 4,
        'description': 'Pre-workout supplement',
        'displayInApp': false,
        'imageUrls': ['a.png'],
        'active': false,
        'gymId': 'gym1',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });

      final snap = await firestore.collection('products').doc('p1').get();
      final product = Product.fromSnapshot(snap);

      expect(product.description, 'Pre-workout supplement');
      expect(product.displayInApp, isFalse);
      expect(product.imageUrls, ['a.png']);
      expect(product.stockType, 'limited');

      final json = product.toJson();
      expect(json['description'], 'Pre-workout supplement');
      expect(json['displayInApp'], isFalse);
      expect(json['imageUrls'], ['a.png']);
    });

    test('fromSnapshot defaults missing fields to sensible values', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('products').doc('p1').set({'name': 'Bare'});

      final snap = await firestore.collection('products').doc('p1').get();
      final product = Product.fromSnapshot(snap);

      expect(product.stockType, 'limited');
      expect(product.displayInApp, isTrue);
      expect(product.imageUrls, isEmpty);
      expect(product.active, isTrue);
    });
  });
}
