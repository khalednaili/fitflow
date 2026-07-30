import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/sale.dart';
import 'package:fit_flow/services/sales_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late SalesService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = SalesService(gymId: 'gym1', firestore: firestore);
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

  group('recordSale', () {
    test('writes a sale document with the correct total', () async {
      await seedProduct(id: 'p1', retailPrice: 5, stock: 10);
      await seedProduct(id: 'p2', name: 'Shirt', retailPrice: 20, stock: 3);

      await service.recordSale(
        items: [
          const SaleItem(
              productId: 'p1',
              productName: 'Protein Shake',
              quantity: 2,
              unitPrice: 5),
          const SaleItem(
              productId: 'p2', productName: 'Shirt', quantity: 1, unitPrice: 20),
        ],
        paymentMethod: 'card',
        soldByName: 'Admin One',
      );

      final sales = await service.streamSales().first;
      expect(sales, hasLength(1));
      final sale = sales.single;
      expect(sale.total, 30); // 2*5 + 1*20
      expect(sale.paymentMethod, 'card');
      expect(sale.soldByName, 'Admin One');
      expect(sale.gymId, 'gym1');
      expect(sale.itemCount, 3);
    });

    test('decrements stock for every sold product', () async {
      await seedProduct(id: 'p1', stock: 10);
      await seedProduct(id: 'p2', stock: 3);

      await service.recordSale(
        items: [
          const SaleItem(
              productId: 'p1', productName: 'A', quantity: 4, unitPrice: 5),
          const SaleItem(
              productId: 'p2', productName: 'B', quantity: 1, unitPrice: 20),
        ],
        paymentMethod: 'cash',
      );

      final p1 = await firestore.collection('products').doc('p1').get();
      final p2 = await firestore.collection('products').doc('p2').get();
      expect(p1.data()!['stock'], 6);
      expect(p2.data()!['stock'], 2);
    });

    test('never lets stock go negative even when overselling', () async {
      await seedProduct(id: 'p1', stock: 2);

      await service.recordSale(
        items: [
          const SaleItem(
              productId: 'p1', productName: 'A', quantity: 5, unitPrice: 5),
        ],
        paymentMethod: 'cash',
      );

      final p1 = await firestore.collection('products').doc('p1').get();
      expect(p1.data()!['stock'], 0);
    });

    test('does nothing when items is empty', () async {
      await service.recordSale(items: const [], paymentMethod: 'cash');

      final sales = await service.streamSales().first;
      expect(sales, isEmpty);
    });

    test('does not decrement stock for unlimited-stock products', () async {
      await seedProduct(id: 'p1', stockType: 'unlimited', stock: 0);

      await service.recordSale(
        items: [
          const SaleItem(
              productId: 'p1', productName: 'A', quantity: 10, unitPrice: 5),
        ],
        paymentMethod: 'cash',
      );

      final p1 = await firestore.collection('products').doc('p1').get();
      expect(p1.data()!['stock'], 0);
      final sales = await service.streamSales().first;
      expect(sales.single.total, 50);
    });
  });

  group('streamSales', () {
    test('only returns sales scoped to gymId, most recent first', () async {
      await firestore.collection('sales').add({
        'items': [],
        'total': 10,
        'status': 'completed',
        'source': 'pos',
        'paymentMethod': 'cash',
        'soldByName': '',
        'gymId': 'gym1',
        'soldAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });
      await firestore.collection('sales').add({
        'items': [],
        'total': 20,
        'status': 'completed',
        'source': 'pos',
        'paymentMethod': 'cash',
        'soldByName': '',
        'gymId': 'gym1',
        'soldAt': Timestamp.fromDate(DateTime(2024, 6, 1)),
      });
      await firestore.collection('sales').add({
        'items': [],
        'total': 99,
        'status': 'completed',
        'source': 'pos',
        'paymentMethod': 'cash',
        'soldByName': '',
        'gymId': 'gym2',
        'soldAt': Timestamp.fromDate(DateTime(2024, 12, 1)),
      });

      final sales = await service.streamSales().first;

      expect(sales.map((s) => s.total), [20, 10]);
    });
  });
}
