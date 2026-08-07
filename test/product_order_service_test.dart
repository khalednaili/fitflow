import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/sale.dart';
import 'package:fit_flow/services/product_order_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ProductOrderService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = ProductOrderService(gymId: 'gym1', firestore: firestore);
  });

  Future<String> seedProduct({
    String id = 'p1',
    String name = 'Protein Shake',
    num retailPrice = 5,
    String stockType = 'limited',
    int stock = 10,
    String gymId = 'gym1',
  }) async {
    await firestore.collection('products').doc(id).set({
      'name': name,
      'retailPrice': retailPrice,
      'stockType': stockType,
      'stock': stock,
      'active': true,
      'gymId': gymId,
      'createdAt': Timestamp.now(),
    });
    return id;
  }

  group('placeOrder', () {
    test('writes a pending order document with the correct total', () async {
      await seedProduct(id: 'p1', retailPrice: 5, stock: 10);
      await seedProduct(id: 'p2', name: 'Shirt', retailPrice: 20, stock: 3);

      await service.placeOrder(
        items: [
          const SaleItem(
              productId: 'p1',
              productName: 'Protein Shake',
              quantity: 2,
              unitPrice: 5),
          const SaleItem(
              productId: 'p2', productName: 'Shirt', quantity: 1, unitPrice: 20),
        ],
        userId: 'user1',
        userName: 'Jane Doe',
      );

      final orders = await service.streamMyOrders('user1').first;
      expect(orders, hasLength(1));
      final order = orders.single;
      expect(order.total, 30); // 2*5 + 1*20
      expect(order.status, 'pending');
      expect(order.userId, 'user1');
      expect(order.userName, 'Jane Doe');
      expect(order.gymId, 'gym1');
      expect(order.itemCount, 3);
    });

    test('decrements stock for every ordered product', () async {
      await seedProduct(id: 'p1', stock: 10);
      await seedProduct(id: 'p2', stock: 3);

      await service.placeOrder(
        items: [
          const SaleItem(
              productId: 'p1', productName: 'A', quantity: 4, unitPrice: 5),
          const SaleItem(
              productId: 'p2', productName: 'B', quantity: 1, unitPrice: 20),
        ],
        userId: 'user1',
      );

      final p1 = await firestore.collection('products').doc('p1').get();
      final p2 = await firestore.collection('products').doc('p2').get();
      expect(p1.data()!['stock'], 6);
      expect(p2.data()!['stock'], 2);
    });

    test('never lets stock go negative even when overselling', () async {
      await seedProduct(id: 'p1', stock: 2);

      await service.placeOrder(
        items: [
          const SaleItem(
              productId: 'p1', productName: 'A', quantity: 5, unitPrice: 5),
        ],
        userId: 'user1',
      );

      final p1 = await firestore.collection('products').doc('p1').get();
      expect(p1.data()!['stock'], 0);
    });

    test('does nothing when items is empty', () async {
      await service.placeOrder(items: const [], userId: 'user1');

      final orders = await service.streamMyOrders('user1').first;
      expect(orders, isEmpty);
    });

    test('does not decrement stock for unlimited-stock products', () async {
      await seedProduct(id: 'p1', stockType: 'unlimited', stock: 0);

      await service.placeOrder(
        items: [
          const SaleItem(
              productId: 'p1', productName: 'A', quantity: 10, unitPrice: 5),
        ],
        userId: 'user1',
      );

      final p1 = await firestore.collection('products').doc('p1').get();
      expect(p1.data()!['stock'], 0);
      final orders = await service.streamMyOrders('user1').first;
      expect(orders.single.total, 50);
    });
  });

  group('streamMyOrders', () {
    test('only returns orders for the given user, most recent first',
        () async {
      await firestore.collection('product_orders').add({
        'items': [],
        'total': 10,
        'status': 'pending',
        'userId': 'user1',
        'userName': '',
        'gymId': 'gym1',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });
      await firestore.collection('product_orders').add({
        'items': [],
        'total': 20,
        'status': 'pending',
        'userId': 'user1',
        'userName': '',
        'gymId': 'gym1',
        'createdAt': Timestamp.fromDate(DateTime(2024, 6, 1)),
      });
      await firestore.collection('product_orders').add({
        'items': [],
        'total': 99,
        'status': 'pending',
        'userId': 'user2',
        'userName': '',
        'gymId': 'gym1',
        'createdAt': Timestamp.fromDate(DateTime(2024, 12, 1)),
      });

      final orders = await service.streamMyOrders('user1').first;

      expect(orders.map((o) => o.total), [20, 10]);
    });

    test('excludes orders scoped to a different gym', () async {
      await firestore.collection('product_orders').add({
        'items': [],
        'total': 10,
        'status': 'pending',
        'userId': 'user1',
        'userName': '',
        'gymId': 'gym1',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });
      await firestore.collection('product_orders').add({
        'items': [],
        'total': 20,
        'status': 'pending',
        'userId': 'user1',
        'userName': '',
        'gymId': 'gym2',
        'createdAt': Timestamp.fromDate(DateTime(2024, 6, 1)),
      });

      final orders = await service.streamMyOrders('user1').first;

      expect(orders.map((o) => o.total), [10]);
    });
  });
}
