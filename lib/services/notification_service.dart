import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';

class NotificationService {
  NotificationService({this.gymId = '', FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('notifications');

  /// Stream all notifications for a user, newest first (sorted client-side).
  Stream<List<AppNotification>> streamForUser(String userId) {
    return _col.where('userId', isEqualTo: userId).snapshots().map((snap) {
      final list = snap.docs.map(AppNotification.fromDoc).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream unread count only.
  Stream<int> streamUnreadCount(String userId) {
    return _col
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.size);
  }

  /// Create a notification document.
  Future<void> create({
    required String userId,
    required String title,
    required String body,
    required NotificationType type,
    String? classId,
  }) async {
    await _col.add(<String, dynamic>{
      'userId': userId,
      'gymId': gymId,
      'title': title,
      'body': body,
      'type': type.name,
      'classId': classId,
      'isRead': false,
      'createdAt': Timestamp.now(),
    });
  }

  /// Mark a single notification as read.
  Future<void> markRead(String notificationId) async {
    await _col.doc(notificationId).update(<String, dynamic>{
      'isRead': true,
    });
  }

  /// Mark all notifications for a user as read.
  Future<void> markAllRead(String userId) async {
    final unread = await _col
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, <String, dynamic>{'isRead': true});
    }
    await batch.commit();
  }

  /// Delete a notification.
  Future<void> delete(String notificationId) async {
    await _col.doc(notificationId).delete();
  }
}
