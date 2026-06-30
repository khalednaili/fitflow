import 'package:cloud_firestore/cloud_firestore.dart';

class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    required this.userId,
    required this.classId,
    required this.createdAt,
    this.memberName = '',
  });

  final String id;
  final String userId;
  final String classId;
  final DateTime createdAt;
  final String memberName;

  factory WaitlistEntry.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return WaitlistEntry(
      id: snapshot.id,
      userId: (data['userId'] ?? '') as String,
      classId: (data['classId'] ?? '') as String,
      // Missing createdAt sorts *earliest* (matches the promotion sorts), and is
      // a stable sentinel rather than DateTime.now() which would shift on every
      // read and make FIFO position non-deterministic.
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      memberName: (data['memberName'] ?? '') as String,
    );
  }
}
