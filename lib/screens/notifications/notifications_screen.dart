import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_notification.dart';
import '../../services/notification_service.dart';
import '../home/class_details_screen.dart';
import '../../services/class_service.dart';
import '../../l10n/app_localizations.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
          body: Center(child: Text(context.l10n.tr('Not signed in.'))));
    }

    final service = NotificationService();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 110,
            backgroundColor: Theme.of(context).colorScheme.primary,
            iconTheme: IconThemeData(color: Colors.white),
            actions: [
              StreamBuilder<List<AppNotification>>(
                stream: service.streamForUser(uid),
                builder: (context, snap) {
                  final hasUnread = (snap.data ?? []).any((n) => !n.isRead);
                  if (!hasUnread) return SizedBox.shrink();
                  return TextButton.icon(
                    onPressed: () => service.markAllRead(uid),
                    icon: Icon(Icons.done_all, color: Colors.white, size: 18),
                    label: Text(context.l10n.tr('Mark all read'),
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  );
                },
              ),
              SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 50, 20, 14),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.notifications_outlined,
                              color: Colors.white, size: 22),
                        ),
                        SizedBox(width: 12),
                        Text(context.l10n.tr('Notifications'),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          StreamBuilder<List<AppNotification>>(
            stream: service.streamForUser(uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final notifications = snap.data ?? [];

              if (notifications.isEmpty) {
                return SliverFillRemaining(
                  child: _EmptyState(),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final n = notifications[i];
                    return _NotificationTile(
                      notification: n,
                      onTap: () => _handleTap(context, n, service),
                      onDismiss: () => service.delete(n.id),
                    );
                  },
                  childCount: notifications.length,
                ),
              );
            },
          ),
          SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  Future<void> _handleTap(
    BuildContext context,
    AppNotification n,
    NotificationService service,
  ) async {
    // Mark as read
    if (!n.isRead) await service.markRead(n.id);

    // Navigate to class if applicable
    if (n.classId != null && n.classId!.isNotEmpty && context.mounted) {
      final gymClass = await ClassService().getClassById(n.classId!);
      if (gymClass != null && context.mounted) {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ClassDetailsScreen(gymClass: gymClass),
        ));
      }
    }
  }
}

// ── Notification tile ─────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  IconData get _icon {
    switch (notification.type) {
      case NotificationType.waitlistPromoted:
        return Icons.celebration_outlined;
      case NotificationType.bookingConfirmed:
        return Icons.check_circle_outline;
      case NotificationType.classReminder:
        return Icons.alarm_outlined;
      case NotificationType.general:
        return Icons.info_outline;
    }
  }

  Color _color(ColorScheme cs) {
    switch (notification.type) {
      case NotificationType.waitlistPromoted:
        return Colors.green.shade600;
      case NotificationType.bookingConfirmed:
        return cs.primary;
      case NotificationType.classReminder:
        return Colors.orange.shade700;
      case NotificationType.general:
        return cs.secondary;
    }
  }

  String _timeAgo(BuildContext context, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) {
      return context.l10n.tr('Just now');
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}${context.l10n.tr('m ago')}';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}${context.l10n.tr('h ago')}';
    }
    if (diff.inDays == 1) {
      return context.l10n.tr('Yesterday');
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}${context.l10n.tr('d ago')}';
    }
    return DateFormat('d MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _color(cs);
    final isUnread = !notification.isRead;

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        color: Colors.red.shade600,
        child: Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      onDismissed: (_) => onDismiss(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isUnread
                ? color.withValues(alpha: 0.06)
                : cs.surfaceContainerLow,
            border: Border.all(
              color:
                  isUnread ? color.withValues(alpha: 0.3) : cs.outlineVariant,
              width: isUnread ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon badge
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 20, color: color),
                ),
                SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontWeight: isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                fontSize: 14,
                                color: isUnread ? cs.onSurface : cs.onSurface,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            _timeAgo(context, notification.createdAt),
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                          if (isUnread) ...[
                            SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: color, shape: BoxShape.circle),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        notification.body,
                        style:
                            TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                      if (notification.classId != null) ...[
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.arrow_forward_ios,
                                size: 10, color: color),
                            SizedBox(width: 4),
                            Text(context.l10n.tr('View class'),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: color,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_none_outlined,
                size: 48, color: cs.primary.withValues(alpha: 0.6)),
          ),
          SizedBox(height: 16),
          Text(context.l10n.tr('All caught up!'),
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          SizedBox(height: 6),
          Text(context.l10n.tr('No notifications yet.'),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
