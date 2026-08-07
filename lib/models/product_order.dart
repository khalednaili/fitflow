import 'package:cloud_firestore/cloud_firestore.dart';

import 'sale.dart';

/// An order placed by a member from the in-app Store, awaiting staff
/// fulfillment (handed over at the front desk). Distinct from [Sale], which
/// records a completed POS checkout — a [ProductOrder] only becomes a [Sale]
/// once staff mark it fulfilled.
class ProductOrder {
  const ProductOrder({
    required this.id,
    required this.items,
    this.total = 0,
    this.status = ProductOrderStatus.pending,
    this.userId = '',
    this.userName = '',
    this.gymId = '',
    required this.createdAt,
  });

  final String id;
  final List<SaleItem> items;
  final num total;

  /// `'pending'` · `'ready'` · `'completed'` · `'cancelled'`.
  final String status;
  final String userId;
  final String userName;
  final String gymId;
  final DateTime createdAt;

  int get itemCount =>
      items.fold<int>(0, (total, item) => total + item.quantity);

  factory ProductOrder.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawItems = (data['items'] as List<dynamic>?) ?? const [];
    return ProductOrder(
      id: snapshot.id,
      items: rawItems
          .map((e) => SaleItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      total: (data['total'] ?? 0) as num,
      status:
          ProductOrderStatus.validated((data['status'] ?? 'pending') as String),
      userId: (data['userId'] ?? '') as String,
      userName: (data['userName'] ?? '') as String,
      gymId: (data['gymId'] ?? '') as String,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'items': items.map((e) => e.toJson()).toList(),
        'total': total,
        'status': status,
        'userId': userId,
        'userName': userName,
        'gymId': gymId,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

abstract final class ProductOrderStatus {
  static const pending = 'pending';
  static const ready = 'ready';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  /// Returns [status] if it is a known value, otherwise [pending].
  static String validated(String status) => const {
        pending,
        ready,
        completed,
        cancelled,
      }.contains(status)
          ? status
          : pending;
}
