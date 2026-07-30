import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/sale.dart';

class SalesService {
  SalesService({this.gymId = '', FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('sales');

  CollectionReference<Map<String, dynamic>> get _products =>
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

  /// Streams the gym's sales, most recent first.
  Stream<List<Sale>> streamSales() {
    return _query.snapshots().map((snap) {
      final list = snap.docs
          .map(Sale.fromSnapshot)
          .where((s) => _matchesGymId(s.gymId))
          .toList();
      list.sort((a, b) => b.soldAt.compareTo(a.soldAt));
      return List<Sale>.unmodifiable(list);
    });
  }

  /// Records a completed POS checkout: decrements each sold product's stock
  /// and writes a [Sale] document, atomically in a single transaction so a
  /// crash mid-checkout can never leave stock decremented without a matching
  /// sale record (or vice-versa).
  Future<void> recordSale({
    required List<SaleItem> items,
    required String paymentMethod,
    String soldByName = '',
  }) async {
    if (items.isEmpty) return;

    await _db.runTransaction((tx) async {
      final refs = {
        for (final item in items) item.productId: _products.doc(item.productId)
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

      final total = items.fold<num>(0, (total, item) => total + item.lineTotal);
      tx.set(
        _col.doc(),
        Sale(
          id: '',
          items: items,
          total: total,
          paymentMethod: paymentMethod,
          soldByName: soldByName,
          gymId: gymId,
          soldAt: DateTime.now(),
        ).toJson(),
      );
    });
  }
}
