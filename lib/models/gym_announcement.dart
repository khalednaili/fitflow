import 'package:cloud_firestore/cloud_firestore.dart';

enum AnnouncementType { banner, popup }

enum AnnouncementPriority { info, warning, danger }

class GymAnnouncement {
  const GymAnnouncement({
    required this.id,
    required this.gymId,
    required this.title,
    required this.body,
    required this.type,
    required this.priority,
    required this.isActive,
    required this.createdAt,
    required this.createdBy,
    this.expiresAt,
    this.version = 0,
  });

  final String id;
  final String gymId;
  final String title;
  final String body;
  final AnnouncementType type;
  final AnnouncementPriority priority;
  final bool isActive;
  final DateTime createdAt;
  final String createdBy;
  final DateTime? expiresAt;
  // Incremented on edit so client-side dismissal keys are invalidated
  final int version;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isVisible => isActive && !isExpired;

  factory GymAnnouncement.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return GymAnnouncement(
      id: doc.id,
      gymId: (d['gymId'] ?? '') as String,
      title: (d['title'] ?? '') as String,
      body: (d['body'] ?? '') as String,
      type: _parseType((d['type'] ?? 'banner') as String),
      priority: _parsePriority((d['priority'] ?? 'info') as String),
      isActive: (d['isActive'] ?? true) as bool,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: (d['createdBy'] ?? '') as String,
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      version: (d['version'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'gymId': gymId,
        'title': title,
        'body': body,
        'type': type.name,
        'priority': priority.name,
        'isActive': isActive,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdBy': createdBy,
        'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
        'version': version,
      };

  GymAnnouncement copyWith({
    String? title,
    String? body,
    AnnouncementType? type,
    AnnouncementPriority? priority,
    bool? isActive,
    DateTime? expiresAt,
    bool clearExpiry = false,
    bool bumpVersion = false,
  }) =>
      GymAnnouncement(
        id: id,
        gymId: gymId,
        title: title ?? this.title,
        body: body ?? this.body,
        type: type ?? this.type,
        priority: priority ?? this.priority,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        createdBy: createdBy,
        expiresAt: clearExpiry ? null : (expiresAt ?? this.expiresAt),
        version: bumpVersion ? version + 1 : version,
      );

  static AnnouncementType _parseType(String raw) => AnnouncementType.values
      .firstWhere((t) => t.name == raw, orElse: () => AnnouncementType.banner);

  static AnnouncementPriority _parsePriority(String raw) =>
      AnnouncementPriority.values.firstWhere((p) => p.name == raw,
          orElse: () => AnnouncementPriority.info);
}
