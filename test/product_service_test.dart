import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/product.dart';
import 'package:fit_flow/services/product_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ProductService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = ProductService(gymId: 'gym1', firestore: firestore);
  });

  Future<String> seedProduct({
    String name = 'Protein Shake',
    String category = 'Beverage',
    String sku = 'SKU-1',
    num cost = 2,
    num retailPrice = 5,
    num vatPercent = 0,
    String stockType = 'limited',
    int stock = 10,
    bool active = true,
    String gymId = 'gym1',
  }) async {
    final ref = await firestore.collection('products').add({
      'name': name,
      'category': category,
      'sku': sku,
      'cost': cost,
      'retailPrice': retailPrice,
      'vatPercent': vatPercent,
      'stockType': stockType,
      'stock': stock,
      'active': active,
      'gymId': gymId,
      'createdAt': Timestamp.now(),
    });
    return ref.id;
  }

  group('streamProducts', () {
    test('only returns products scoped to gymId', () async {
      await seedProduct(name: 'Mine', gymId: 'gym1');
      await seedProduct(name: 'Other gym', gymId: 'gym2');

      final products = await service.streamProducts().first;

      expect(products.map((p) => p.name), ['Mine']);
    });

    test('sorts products alphabetically by name (case-insensitive)', () async {
      await seedProduct(name: 'zebra shaker');
      await seedProduct(name: 'Apple juice');
      await seedProduct(name: 'mango bar');

      final products = await service.streamProducts().first;

      expect(products.map((p) => p.name),
          ['Apple juice', 'mango bar', 'zebra shaker']);
    });

    test('maps all fields through correctly', () async {
      await seedProduct(
        name: 'Creatine',
        category: 'Supplements',
        sku: 'CR-100',
        cost: 8,
        retailPrice: 20,
        vatPercent: 19,
        stock: 4,
        active: false,
      );

      final product = (await service.streamProducts().first).single;

      expect(product.category, 'Supplements');
      expect(product.sku, 'CR-100');
      expect(product.cost, 8);
      expect(product.retailPrice, 20);
      expect(product.vatPercent, 19);
      expect(product.stock, 4);
      expect(product.active, false);
    });
  });

  group('streamCategories', () {
    test('returns distinct, sorted, non-empty categories', () async {
      await seedProduct(name: 'a', category: 'Beverage');
      await seedProduct(name: 'b', category: 'Apparel');
      await seedProduct(name: 'c', category: 'Beverage');
      await seedProduct(name: 'd', category: '');

      final categories = await service.streamCategories().first;

      expect(categories, ['Apparel', 'Beverage']);
    });
  });

  group('create / update / setActive / delete', () {
    test('create adds a new product document scoped to the gym', () async {
      await service.create(Product(
        id: '',
        name: 'New Item',
        gymId: 'gym1',
        createdAt: DateTime.now(),
      ));

      final products = await service.streamProducts().first;
      expect(products.map((p) => p.name), ['New Item']);
    });

    test('update overwrites an existing product\'s fields', () async {
      final id = await seedProduct(name: 'Old name', stock: 1);
      final existing = (await service.streamProducts().first).single;

      await service.update(existing.copyWith(name: 'New name', stock: 9));

      final updated = (await service.streamProducts().first)
          .firstWhere((p) => p.id == id);
      expect(updated.name, 'New name');
      expect(updated.stock, 9);
    });

    test('setActive toggles the active flag without touching other fields',
        () async {
      final id = await seedProduct(active: true, stock: 5);

      await service.setActive(id, false);

      final product =
          (await service.streamProducts().first).firstWhere((p) => p.id == id);
      expect(product.active, false);
      expect(product.stock, 5);
    });

    test('delete removes the product document', () async {
      final id = await seedProduct();

      await service.delete(id);

      final products = await service.streamProducts().first;
      expect(products.where((p) => p.id == id), isEmpty);
    });
  });

  group('decrementStock', () {
    test('reduces stock by the given quantity', () async {
      final id = await seedProduct(stock: 10);

      await service.decrementStock(id, 3);

      final product =
          (await service.streamProducts().first).firstWhere((p) => p.id == id);
      expect(product.stock, 7);
    });

    test('never lets stock go negative', () async {
      final id = await seedProduct(stock: 2);

      await service.decrementStock(id, 5);

      final product =
          (await service.streamProducts().first).firstWhere((p) => p.id == id);
      expect(product.stock, 0);
    });

    test('is a no-op for unlimited-stock products', () async {
      final id = await seedProduct(stockType: 'unlimited', stock: 0);

      await service.decrementStock(id, 5);

      final product =
          (await service.streamProducts().first).firstWhere((p) => p.id == id);
      expect(product.stock, 0);
      expect(product.isUnlimitedStock, isTrue);
      expect(product.inStock, isTrue);
    });
  });
}
