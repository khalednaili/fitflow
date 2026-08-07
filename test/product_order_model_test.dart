import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/product_order.dart';
import 'package:fit_flow/models/sale.dart';

void main() {
  group('ProductOrder', () {
    test('itemCount sums quantities across items', () {
      final order = ProductOrder(
        id: '1',
        items: [
          SaleItem(
              productId: 'p1',
              productName: 'A',
              quantity: 2,
              unitPrice: 5),
          SaleItem(
              productId: 'p2',
              productName: 'B',
              quantity: 3,
              unitPrice: 10),
        ],
        createdAt: DateTime.now(),
      );

      expect(order.itemCount, 5);
    });

    test('fromSnapshot / toJson round-trip all fields', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('product_orders').doc('o1').set({
        'items': [
          {
            'productId': 'p1',
            'productName': 'Protein Shake',
            'quantity': 2,
            'unitPrice': 5,
          },
        ],
        'total': 10,
        'status': 'ready',
        'userId': 'user1',
        'userName': 'Jane Doe',
        'gymId': 'gym1',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });

      final snap =
          await firestore.collection('product_orders').doc('o1').get();
      final order = ProductOrder.fromSnapshot(snap);

      expect(order.items, hasLength(1));
      expect(order.items.single.productName, 'Protein Shake');
      expect(order.total, 10);
      expect(order.status, ProductOrderStatus.ready);
      expect(order.userId, 'user1');
      expect(order.userName, 'Jane Doe');
      expect(order.gymId, 'gym1');
      expect(order.itemCount, 2);

      final json = order.toJson();
      expect(json['status'], 'ready');
      expect(json['userId'], 'user1');
      expect((json['items'] as List).single['productName'], 'Protein Shake');
    });

    test('fromSnapshot defaults missing fields to sensible values', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('product_orders')
          .doc('o1')
          .set(<String, dynamic>{});

      final snap =
          await firestore.collection('product_orders').doc('o1').get();
      final order = ProductOrder.fromSnapshot(snap);

      expect(order.items, isEmpty);
      expect(order.total, 0);
      expect(order.status, ProductOrderStatus.pending);
      expect(order.userId, '');
      expect(order.userName, '');
      expect(order.gymId, '');
    });
  });

  group('ProductOrderStatus.validated', () {
    test('returns the given status when it is known', () {
      expect(ProductOrderStatus.validated('ready'), 'ready');
      expect(ProductOrderStatus.validated('completed'), 'completed');
      expect(ProductOrderStatus.validated('cancelled'), 'cancelled');
    });

    test('falls back to pending for unknown statuses', () {
      expect(ProductOrderStatus.validated('bogus'), ProductOrderStatus.pending);
      expect(ProductOrderStatus.validated(''), ProductOrderStatus.pending);
    });
  });
}
