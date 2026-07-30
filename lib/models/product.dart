import 'package:cloud_firestore/cloud_firestore.dart';

/// A store item sold to members (drinks, apparel, supplements, ...).
///
/// Monetary fields ([cost], [retailPrice]) follow the app-wide [Currency]
/// convention: whole units of the currency (e.g. `2.5` means 2.5 TND), never
/// minor units / cents.
class Product {
  const Product({
    required this.id,
    required this.name,
    this.category = '',
    this.sku = '',
    this.cost = 0,
    this.retailPrice = 0,
    this.vatPercent = 0,
    this.stockType = 'limited',
    this.stock = 0,
    this.description = '',
    this.displayInApp = true,
    this.imageUrls = const [],
    this.active = true,
    this.gymId = '',
    required this.createdAt,
  });

  final String id;
  final String name;
  final String category;
  final String sku;
  final num cost;
  final num retailPrice;
  final num vatPercent;

  /// `'unlimited'` · `'limited'`. Unlimited-stock products are always
  /// purchasable and never decremented by a sale.
  final String stockType;
  final int stock;
  final String description;

  /// Whether the product is visible to members in the client app (distinct
  /// from [active], which controls whether staff can sell/manage it).
  final bool displayInApp;

  /// Up to 3 uploaded image URLs (Firebase Storage download URLs).
  final List<String> imageUrls;
  final bool active;
  final String gymId;
  final DateTime createdAt;

  bool get isUnlimitedStock => stockType == 'unlimited';

  bool get inStock => isUnlimitedStock || stock > 0;

  /// First image, or empty string if none uploaded yet.
  String get imageUrl => imageUrls.isEmpty ? '' : imageUrls.first;

  Product copyWith({
    String? name,
    String? category,
    String? sku,
    num? cost,
    num? retailPrice,
    num? vatPercent,
    String? stockType,
    int? stock,
    String? description,
    bool? displayInApp,
    List<String>? imageUrls,
    bool? active,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      sku: sku ?? this.sku,
      cost: cost ?? this.cost,
      retailPrice: retailPrice ?? this.retailPrice,
      vatPercent: vatPercent ?? this.vatPercent,
      stockType: stockType ?? this.stockType,
      stock: stock ?? this.stock,
      description: description ?? this.description,
      displayInApp: displayInApp ?? this.displayInApp,
      imageUrls: imageUrls ?? this.imageUrls,
      active: active ?? this.active,
      gymId: gymId,
      createdAt: createdAt,
    );
  }

  factory Product.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawImageUrls = (data['imageUrls'] as List<dynamic>?) ?? const [];
    return Product(
      id: snapshot.id,
      name: (data['name'] ?? '') as String,
      category: (data['category'] ?? '') as String,
      sku: (data['sku'] ?? '') as String,
      cost: (data['cost'] ?? 0) as num,
      retailPrice: (data['retailPrice'] ?? 0) as num,
      vatPercent: (data['vatPercent'] ?? 0) as num,
      stockType: (data['stockType'] ?? 'limited') as String,
      stock: (data['stock'] ?? 0) as int,
      description: (data['description'] ?? '') as String,
      displayInApp: (data['displayInApp'] ?? true) as bool,
      imageUrls: rawImageUrls.map((e) => e as String).toList(),
      active: (data['active'] ?? true) as bool,
      gymId: (data['gymId'] ?? '') as String,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'category': category,
        'sku': sku,
        'cost': cost,
        'retailPrice': retailPrice,
        'vatPercent': vatPercent,
        'stockType': stockType,
        'stock': stock,
        'description': description,
        'displayInApp': displayInApp,
        'imageUrls': imageUrls,
        'active': active,
        'gymId': gymId,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
