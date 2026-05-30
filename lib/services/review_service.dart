import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/class_review.dart';

class ReviewService {
  ReviewService({this.gymId = '', FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('classReviews');

  /// Doc ID guarantees one review per user per class.
  String _docId(String classId, String userId) => '${classId}_$userId';

  Future<void> submitReview({
    required String classId,
    required String userId,
    required String memberName,
    required int rating,
    String comment = '',
  }) {
    final review = ClassReview(
      id: _docId(classId, userId),
      classId: classId,
      userId: userId,
      gymId: gymId,
      rating: rating,
      comment: comment,
      createdAt: DateTime.now(),
      memberName: memberName,
    );
    return _col.doc(review.id).set(review.toJson());
  }

  Stream<ClassReview?> streamMyReview(String classId, String userId) {
    return _col
        .doc(_docId(classId, userId))
        .snapshots()
        .map((s) => s.exists ? ClassReview.fromSnapshot(s) : null);
  }

  Stream<List<ClassReview>> streamReviewsForClass(String classId) {
    return _col
        .where('classId', isEqualTo: classId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ClassReview.fromSnapshot).toList());
  }

  /// Returns a stream of the average rating (0.0 if no reviews).
  Stream<double> streamAverageRating(String classId) {
    return streamReviewsForClass(classId).map((reviews) {
      if (reviews.isEmpty) return 0.0;
      final sum = reviews.fold<int>(0, (acc, r) => acc + r.rating);
      return sum / reviews.length;
    });
  }

  /// Returns a stream of avg rating keyed by classId for a list of class IDs.
  /// Used by the coach portal to show averages for their classes.
  Stream<Map<String, double>> streamAverageRatingsForClasses(
      List<String> classIds) {
    if (classIds.isEmpty) {
      return Stream.value({});
    }
    // Firestore whereIn supports up to 30 items per query.
    final chunks = <List<String>>[];
    for (var i = 0; i < classIds.length; i += 30) {
      chunks.add(classIds.sublist(
          i, i + 30 < classIds.length ? i + 30 : classIds.length));
    }
    final streams = chunks
        .map((chunk) => _col
            .where('classId', whereIn: chunk)
            .snapshots()
            .map((s) => s.docs.map(ClassReview.fromSnapshot).toList()))
        .toList();

    // Merge chunk streams
    return streams.fold<Stream<List<ClassReview>>>(
      Stream.value([]),
      (acc, s) => acc.asyncMap((a) async {
        final b = await s.first;
        return [...a, ...b];
      }),
    ).map((reviews) {
      final map = <String, double>{};
      final grouped = <String, List<int>>{};
      for (final r in reviews) {
        grouped.putIfAbsent(r.classId, () => []).add(r.rating);
      }
      for (final entry in grouped.entries) {
        final sum = entry.value.fold<int>(0, (a, b) => a + b);
        map[entry.key] = sum / entry.value.length;
      }
      return map;
    });
  }
}
