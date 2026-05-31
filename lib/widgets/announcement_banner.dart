import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/gym_announcement.dart';
import '../services/announcement_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnnouncementSection — placed at the top of the member dashboard.
// Handles both banner (dismissible cards) and popup (auto-dialog) types.
// ─────────────────────────────────────────────────────────────────────────────

class AnnouncementSection extends StatefulWidget {
  const AnnouncementSection({
    super.key,
    required this.gymId,
    required this.userId,
  });

  final String gymId;
  final String userId;

  @override
  State<AnnouncementSection> createState() => _AnnouncementSectionState();
}

class _AnnouncementSectionState extends State<AnnouncementSection> {
  late final AnnouncementService _service;
  SharedPreferences? _prefs;
  // Tracks popup IDs that have been scheduled this session to prevent duplicates
  final Set<String> _scheduledThisSession = {};

  @override
  void initState() {
    super.initState();
    _service = AnnouncementService(gymId: widget.gymId);
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  // ── SharedPreferences keys ─────────────────────────────────────────────────

  String _dismissedKey(GymAnnouncement a) =>
      '${widget.userId}_${a.id}_${a.version}_dismissed';

  String _shownKey(GymAnnouncement a) =>
      '${widget.userId}_${a.id}_${a.version}_shown';

  bool _isBannerDismissed(GymAnnouncement a) =>
      _prefs?.getBool(_dismissedKey(a)) ?? false;

  bool _isPopupShown(GymAnnouncement a) =>
      _prefs?.getBool(_shownKey(a)) ?? false;

  Future<void> _dismissBanner(GymAnnouncement a) async {
    await _prefs?.setBool(_dismissedKey(a), true);
    if (mounted) setState(() {});
  }

  // ── Popup scheduling ───────────────────────────────────────────────────────

  void _maybeShowPopups(List<GymAnnouncement> popups) {
    if (_prefs == null) return;
    final unseen = popups
        .where(
            (a) => !_isPopupShown(a) && !_scheduledThisSession.contains(a.id))
        .toList();
    if (unseen.isEmpty) return;

    // Show one popup at a time (highest priority, then newest)
    final first = (unseen..sort(_priorityThenDate)).first;
    _scheduledThisSession.add(first.id);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _prefs?.setBool(_shownKey(first), true);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _AnnouncementPopup(announcement: first),
      );
    });
  }

  static int _priorityThenDate(GymAnnouncement a, GymAnnouncement b) {
    const order = {
      AnnouncementPriority.danger: 0,
      AnnouncementPriority.warning: 1,
      AnnouncementPriority.info: 2,
    };
    final cmp = order[a.priority]!.compareTo(order[b.priority]!);
    return cmp != 0 ? cmp : b.createdAt.compareTo(a.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gymId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<GymAnnouncement>>(
      stream: _service.streamActiveAnnouncements(),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final banners =
            all.where((a) => a.type == AnnouncementType.banner).toList();
        final popups =
            all.where((a) => a.type == AnnouncementType.popup).toList();

        if (_prefs != null) _maybeShowPopups(popups);

        final visible = banners.where((a) => !_isBannerDismissed(a)).toList();

        if (visible.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: visible
                .map((a) => _BannerTile(
                      key: ValueKey(a.id),
                      announcement: a,
                      onDismiss: () => _dismissBanner(a),
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner tile — a single dismissible announcement bar
// ─────────────────────────────────────────────────────────────────────────────

class _BannerTile extends StatelessWidget {
  const _BannerTile({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });

  final GymAnnouncement announcement;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = _priorityColors(announcement.priority);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(colors.icon, color: colors.fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: colors.fg,
                  ),
                ),
                if (announcement.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    announcement.body,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.fg.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded,
                size: 16, color: colors.fg.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Popup dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AnnouncementPopup extends StatelessWidget {
  const _AnnouncementPopup({required this.announcement});
  final GymAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final colors = _priorityColors(announcement.priority);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.bg,
                  shape: BoxShape.circle,
                ),
                child: Icon(colors.icon, color: colors.fg, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                announcement.title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                announcement.body,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.fg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(context.l10n.tr('Got it'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Colour helpers
// ─────────────────────────────────────────────────────────────────────────────

class _PriorityColors {
  const _PriorityColors(
      {required this.bg,
      required this.fg,
      required this.border,
      required this.icon});
  final Color bg;
  final Color fg;
  final Color border;
  final IconData icon;
}

_PriorityColors _priorityColors(AnnouncementPriority p) {
  switch (p) {
    case AnnouncementPriority.warning:
      return _PriorityColors(
        bg: const Color(0xFFFFFBEB),
        fg: const Color(0xFFB45309),
        border: const Color(0xFFFDE68A),
        icon: Icons.warning_amber_rounded,
      );
    case AnnouncementPriority.danger:
      return _PriorityColors(
        bg: const Color(0xFFFEF2F2),
        fg: const Color(0xFFDC2626),
        border: const Color(0xFFFECACA),
        icon: Icons.error_outline_rounded,
      );
    case AnnouncementPriority.info:
      return _PriorityColors(
        bg: const Color(0xFFF0FDFA),
        fg: const Color(0xFF0F766E),
        border: const Color(0xFF99F6E4),
        icon: Icons.info_outline_rounded,
      );
  }
}
