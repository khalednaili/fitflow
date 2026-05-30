import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  waitlistPromoted,
  bookingConfirmed,
  classReminder,
  general,
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.classId,
    this.isRead = false,
  });

  final String id;
  final String userId;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime createdAt;
  final String? classId;
  final bool isRead;

  factory AppNotification.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AppNotification(
      id: doc.id,
      userId: (data['userId'] ?? '') as String,
      title: (data['title'] ?? '') as String,
      body: (data['body'] ?? '') as String,
      type: _parseType((data['type'] ?? '') as String),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      classId: data['classId'] as String?,
      isRead: (data['isRead'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'userId': userId,
        'title': title,
        'body': body,
        'type': type.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'classId': classId,
        'isRead': isRead,
      };

  static NotificationType _parseType(String raw) {
    return NotificationType.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => NotificationType.general,
    );
  }

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        userId: userId,
        title: title,
        body: body,
        type: type,
        createdAt: createdAt,
        classId: classId,
        isRead: isRead ?? this.isRead,
      );
}
