import 'package:cloud_firestore/cloud_firestore.dart';

class MemberBooking {
  const MemberBooking({
    required this.id,
    required this.userId,
    required this.classId,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String classId;
  final DateTime createdAt;

  factory MemberBooking.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return MemberBooking(
      id: snapshot.id,
      userId: (data['userId'] ?? '') as String,
      classId: (data['classId'] ?? '') as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
