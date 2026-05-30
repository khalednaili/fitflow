import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a friend connection between two gym members.
/// Doc ID is always "${smallerUid}_${largerUid}" to avoid duplicates.
class FriendConnection {
  const FriendConnection({
    required this.id,
    required this.requesterId,
    required this.receiverId,
    required this.gymId,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String requesterId;
  final String receiverId;
  final String gymId;

  /// 'pending' | 'accepted'
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  factory FriendConnection.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return FriendConnection(
      id: snap.id,
      requesterId: (d['requesterId'] ?? '') as String,
      receiverId: (d['receiverId'] ?? '') as String,
      gymId: (d['gymId'] ?? '') as String,
      status: (d['status'] ?? 'pending') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'requesterId': requesterId,
        'receiverId': receiverId,
        'gymId': gymId,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  /// Returns the friend's user ID relative to [myUid].
  String friendId(String myUid) =>
      requesterId == myUid ? receiverId : requesterId;

  /// Stable doc ID so there is never a duplicate pair.
  static String docId(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
