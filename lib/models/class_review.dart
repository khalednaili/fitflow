import 'package:cloud_firestore/cloud_firestore.dart';

class ClassReview {
  const ClassReview({
    required this.id,
    required this.classId,
    required this.userId,
    required this.gymId,
    required this.rating,
    this.comment = '',
    required this.createdAt,
    this.memberName = '',
  });

  final String id;
  final String classId;
  final String userId;
  final String gymId;

  /// 1–5 star rating.
  final int rating;
  final String comment;
  final DateTime createdAt;
  final String memberName;

  factory ClassReview.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return ClassReview(
      id: snap.id,
      classId: (d['classId'] ?? '') as String,
      userId: (d['userId'] ?? '') as String,
      gymId: (d['gymId'] ?? '') as String,
      rating: (d['rating'] ?? 3) as int,
      comment: (d['comment'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      memberName: (d['memberName'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'classId': classId,
        'userId': userId,
        'gymId': gymId,
        'rating': rating,
        'comment': comment,
        'createdAt': Timestamp.fromDate(createdAt),
        'memberName': memberName,
      };
}
