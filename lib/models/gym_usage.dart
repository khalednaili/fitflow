import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-collection usage breakdown, nested under [GymUsage.collections].
class CollectionUsage {
  const CollectionUsage({
    this.writes = 0,
    this.deletes = 0,
    this.docCount = 0,
    this.storageBytes = 0,
  });

  final int writes;
  final int deletes;
  final int docCount;
  final int storageBytes;

  factory CollectionUsage.fromMap(Map<String, dynamic> map) => CollectionUsage(
        writes: (map['writes'] as num? ?? 0).toInt(),
        deletes: (map['deletes'] as num? ?? 0).toInt(),
        docCount: (map['docCount'] as num? ?? 0).toInt(),
        storageBytes: (map['storageBytes'] as num? ?? 0).toInt(),
      );
}

/// Cumulative Firebase usage counters for a single gym, aggregated
/// server-side by Cloud Functions triggers into the `gymUsage/{gymId}`
/// document. Powers the super admin "Gym Usage & Billing" screen.
///
/// NOTE: Firestore *reads* are not tracked — there is no server-side trigger
/// for reads, and instrumenting every read call site across the app's 20+
/// services was judged too invasive for v1. Only writes, deletes, and
/// storage size (Firestore + Cloud Storage) are metered.
class GymUsage {
  const GymUsage({
    required this.gymId,
    this.writes = 0,
    this.deletes = 0,
    this.docCount = 0,
    this.firestoreStorageBytes = 0,
    this.cloudStorageBytes = 0,
    this.cloudStorageFileCount = 0,
    this.collections = const {},
    this.lastWriteAt,
    this.lastInvoicedWrites = 0,
    this.lastInvoicedDeletes = 0,
    this.lastInvoicedAt,
  });

  final String gymId;

  /// Cumulative Firestore document creates + updates since tracking began.
  final int writes;

  /// Cumulative Firestore document deletes since tracking began.
  final int deletes;

  /// Current total document count across all gym-scoped collections.
  final int docCount;

  /// Estimated current Firestore storage footprint, in bytes (JSON size of
  /// stored documents — an approximation, not Firestore's exact billing
  /// formula).
  final int firestoreStorageBytes;

  /// Current Cloud Storage footprint (e.g. product images), in bytes.
  final int cloudStorageBytes;
  final int cloudStorageFileCount;

  final Map<String, CollectionUsage> collections;

  final DateTime? lastWriteAt;

  /// Snapshot of [writes]/[deletes] as of the last generated platform
  /// invoice — used to compute the billable delta ("period usage") for the
  /// next invoice.
  final int lastInvoicedWrites;
  final int lastInvoicedDeletes;
  final DateTime? lastInvoicedAt;

  int get totalStorageBytes => firestoreStorageBytes + cloudStorageBytes;

  /// Firestore operations (writes + deletes) since the last invoice was
  /// generated. Falls back to lifetime totals when no invoice exists yet.
  int get opsSinceLastInvoice =>
      (writes - lastInvoicedWrites) + (deletes - lastInvoicedDeletes);

  factory GymUsage.empty(String gymId) => GymUsage(gymId: gymId);

  factory GymUsage.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawCollections =
        (data['collections'] as Map<String, dynamic>? ?? {});
    return GymUsage(
      gymId: snapshot.id,
      writes: (data['writes'] as num? ?? 0).toInt(),
      deletes: (data['deletes'] as num? ?? 0).toInt(),
      docCount: (data['docCount'] as num? ?? 0).toInt(),
      firestoreStorageBytes:
          (data['firestoreStorageBytes'] as num? ?? 0).toInt(),
      cloudStorageBytes: (data['cloudStorageBytes'] as num? ?? 0).toInt(),
      cloudStorageFileCount:
          (data['cloudStorageFileCount'] as num? ?? 0).toInt(),
      collections: rawCollections.map(
        (key, value) => MapEntry(
          key,
          CollectionUsage.fromMap(value as Map<String, dynamic>? ?? {}),
        ),
      ),
      lastWriteAt: (data['lastWriteAt'] as Timestamp?)?.toDate(),
      lastInvoicedWrites: (data['lastInvoicedWrites'] as num? ?? 0).toInt(),
      lastInvoicedDeletes: (data['lastInvoicedDeletes'] as num? ?? 0).toInt(),
      lastInvoicedAt: (data['lastInvoicedAt'] as Timestamp?)?.toDate(),
    );
  }
}
