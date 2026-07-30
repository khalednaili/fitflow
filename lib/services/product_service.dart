import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product.dart';

class ProductService {
  ProductService({this.gymId = '', FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('products');

  bool _matchesGymId(String scopedGymId) {
    return gymId.isEmpty || scopedGymId.isEmpty || scopedGymId == gymId;
  }

  Query<Map<String, dynamic>> get _query {
    Query<Map<String, dynamic>> query = _col;
    if (gymId.isNotEmpty) {
      query = query.where('gymId', isEqualTo: gymId);
    }
    return query;
  }

  /// Streams every product for the current gym, sorted by name.
  Stream<List<Product>> streamProducts() {
    return _query.snapshots().map((snap) {
      final list = snap.docs
          .map(Product.fromSnapshot)
          .where((p) => _matchesGymId(p.gymId))
          .toList();
      list.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return List<Product>.unmodifiable(list);
    });
  }

  /// Distinct, sorted category names across all of the gym's products (used
  /// to populate the category filter dropdown).
  Stream<List<String>> streamCategories() {
    return streamProducts().map((products) {
      final categories = products
          .map((p) => p.category)
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return List<String>.unmodifiable(categories);
    });
  }

  Future<void> create(Product product) => _col.add(product.toJson());

  Future<void> update(Product product) =>
      _col.doc(product.id).update(product.toJson());

  Future<void> setActive(String id, bool active) =>
      _col.doc(id).update({'active': active});

  Future<void> delete(String id) => _col.doc(id).delete();

  /// Atomically decrements [productId]'s stock by [quantity]. Used when
  /// recording a POS sale. Never lets stock go negative. No-ops for
  /// unlimited-stock products.
  Future<void> decrementStock(String productId, int quantity) {
    return _db.runTransaction((tx) async {
      final ref = _col.doc(productId);
      final snap = await tx.get(ref);
      final data = snap.data();
      if ((data?['stockType'] ?? 'limited') == 'unlimited') return;
      final current = (data?['stock'] ?? 0) as int;
      final next = (current - quantity).clamp(0, 1 << 31);
      tx.update(ref, {'stock': next});
    });
  }
}
