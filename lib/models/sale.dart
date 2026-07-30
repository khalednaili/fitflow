import 'package:cloud_firestore/cloud_firestore.dart';

/// One line item within a [Sale] (a single product sold at a given quantity
/// & unit price, captured at time of sale so historical sales stay accurate
/// even if the product's price later changes).
class SaleItem {
  const SaleItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  final String productId;
  final String productName;
  final int quantity;
  final num unitPrice;

  num get lineTotal => unitPrice * quantity;

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      productId: (map['productId'] ?? '') as String,
      productName: (map['productName'] ?? '') as String,
      quantity: (map['quantity'] ?? 0) as int,
      unitPrice: (map['unitPrice'] ?? 0) as num,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };
}

/// A completed point-of-sale transaction (a "receipt"), recorded from the
/// admin POS screen. `status` and `source` mirror the reference tool's Sales
/// screen filters.
class Sale {
  const Sale({
    required this.id,
    required this.items,
    this.total = 0,
    this.status = 'completed',
    this.source = 'pos',
    this.paymentMethod = 'cash',
    this.soldByName = '',
    this.gymId = '',
    required this.soldAt,
  });

  final String id;
  final List<SaleItem> items;
  final num total;

  /// `'completed'` · `'refunded'`.
  final String status;

  /// `'pos'` (only source currently supported; kept for parity with the
  /// reference tool's filter and future channels, e.g. online store).
  final String source;

  /// `'cash'` · `'card'`.
  final String paymentMethod;
  final String soldByName;
  final String gymId;
  final DateTime soldAt;

  int get itemCount =>
      items.fold<int>(0, (total, item) => total + item.quantity);

  factory Sale.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawItems = (data['items'] as List<dynamic>?) ?? const [];
    return Sale(
      id: snapshot.id,
      items: rawItems
          .map((e) => SaleItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      total: (data['total'] ?? 0) as num,
      status: (data['status'] ?? 'completed') as String,
      source: (data['source'] ?? 'pos') as String,
      paymentMethod: (data['paymentMethod'] ?? 'cash') as String,
      soldByName: (data['soldByName'] ?? '') as String,
      gymId: (data['gymId'] ?? '') as String,
      soldAt: (data['soldAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'items': items.map((e) => e.toJson()).toList(),
        'total': total,
        'status': status,
        'source': source,
        'paymentMethod': paymentMethod,
        'soldByName': soldByName,
        'gymId': gymId,
        'soldAt': Timestamp.fromDate(soldAt),
      };
}
