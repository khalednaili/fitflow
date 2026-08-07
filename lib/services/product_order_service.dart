import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_order.dart';
import '../models/sale.dart';

/// Handles member-placed [ProductOrder]s: orders placed from the in-app
/// Store screen, awaiting staff fulfillment at the front desk.
class ProductOrderService {
  ProductOrderService({this.gymId = '', FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('product_orders');

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('products');

  bool _matchesGymId(String scopedGymId) {
    return gymId.isEmpty || scopedGymId.isEmpty || scopedGymId == gymId;
  }

  /// Streams every order placed for the current gym, most recent first (for
  /// staff fulfillment).
  Stream<List<ProductOrder>> streamOrders() {
    Query<Map<String, dynamic>> query = _col;
    if (gymId.isNotEmpty) {
      query = query.where('gymId', isEqualTo: gymId);
    }
    return query.snapshots().map((snap) {
      final list = snap.docs
          .map(ProductOrder.fromSnapshot)
          .where((o) => _matchesGymId(o.gymId))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List<ProductOrder>.unmodifiable(list);
    });
  }

  /// Streams every order placed by [userId] for the current gym, most recent
  /// first.
  Stream<List<ProductOrder>> streamMyOrders(String userId) {
    return _col.where('userId', isEqualTo: userId).snapshots().map((snap) {
      final list = snap.docs
          .map(ProductOrder.fromSnapshot)
          .where((o) => _matchesGymId(o.gymId))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List<ProductOrder>.unmodifiable(list);
    });
  }

  /// Places a new order: decrements each ordered product's stock and writes
  /// a [ProductOrder] document with `status: pending`, atomically in a
  /// single transaction (mirrors [SalesService.recordSale]).
  Future<void> placeOrder({
    required List<SaleItem> items,
    required String userId,
    String userName = '',
  }) async {
    if (items.isEmpty) return;

    await _db.runTransaction((tx) async {
      final refs = {
        for (final item in items)
          item.productId: _products.doc(item.productId)
      };
      final snaps = {
        for (final entry in refs.entries) entry.key: await tx.get(entry.value)
      };

      for (final item in items) {
        final snap = snaps[item.productId];
        final data = snap?.data();
        if ((data?['stockType'] ?? 'limited') == 'unlimited') continue;
        final current = (data?['stock'] ?? 0) as int;
        final next = (current - item.quantity).clamp(0, 1 << 31);
        tx.update(refs[item.productId]!, {'stock': next});
      }

      final total =
          items.fold<num>(0, (total, item) => total + item.lineTotal);
      tx.set(
        _col.doc(),
        ProductOrder(
          id: '',
          items: items,
          total: total,
          userId: userId,
          userName: userName,
          gymId: gymId,
          createdAt: DateTime.now(),
        ).toJson(),
      );
    });
  }

  /// Marks [orderId] as [status] (`ready` or `completed`). Does not touch
  /// stock — stock was already decremented when the order was placed.
  Future<void> setStatus(String orderId, String status) =>
      _col.doc(orderId).update({'status': ProductOrderStatus.validated(status)});

  /// Cancels [orderId] and restores stock for every non-unlimited item in
  /// the order, atomically. No-ops if the order is already cancelled.
  Future<void> cancelOrder(String orderId) async {
    await _db.runTransaction((tx) async {
      final orderRef = _col.doc(orderId);
      final orderSnap = await tx.get(orderRef);
      final data = orderSnap.data();
      if (data == null) return;
      if ((data['status'] ?? '') == ProductOrderStatus.cancelled) return;

      final order = ProductOrder.fromSnapshot(orderSnap);
      final refs = {
        for (final item in order.items)
          item.productId: _products.doc(item.productId)
      };
      final snaps = {
        for (final entry in refs.entries) entry.key: await tx.get(entry.value)
      };

      for (final item in order.items) {
        final snap = snaps[item.productId];
        final productData = snap?.data();
        if (productData == null) continue;
        if ((productData['stockType'] ?? 'limited') == 'unlimited') continue;
        final current = (productData['stock'] ?? 0) as int;
        tx.update(refs[item.productId]!, {'stock': current + item.quantity});
      }

      tx.update(orderRef, {'status': ProductOrderStatus.cancelled});
    });
  }
}
