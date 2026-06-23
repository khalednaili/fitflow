import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/booking.dart';
import '../../models/gym_class.dart';
import '../../models/wod_entry.dart';
import '../../services/booking_service.dart';
import '../../services/wod_service.dart';
import '../../utils/crash_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ClassWhiteboardScreen
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen whiteboard overlay for a coach.
///
/// Shows the WOD details for this class (matched by date + classTypeId) and
/// the full booked-member roster with live check-in status. The coach can
/// manually check in / undo check-in for any member directly from this screen.
class ClassWhiteboardScreen extends StatefulWidget {
  const ClassWhiteboardScreen({
    super.key,
    required this.gymClass,
    required this.gymId,
  });

  final GymClass gymClass;
  final String gymId;

  @override
  State<ClassWhiteboardScreen> createState() => _ClassWhiteboardScreenState();
}

class _ClassWhiteboardScreenState extends State<ClassWhiteboardScreen>
    with SingleTickerProviderStateMixin {
  late final _bookingService = BookingService(gymId: widget.gymId);
  late final _wodService = WodService(gymId: widget.gymId);
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  late final Stream<List<Booking>> _bookingsStream =
      _bookingService.streamBookingsForClass(widget.gymClass.id);

  late final Stream<List<WodEntry>> _wodStream = _wodService.streamForDate(
    widget.gymClass.startTime,
    classTypeId: widget.gymClass.classTypeId,
  );

  final Map<String, bool> _loadingMap = {};

  // ── colour palette ──────────────────────────────────────────────────────────

  static const _bg = Color(0xFF0C0C0C);
  static const _card = Color(0xFF1A1A1A);
  static const _border = Color(0xFF282828);
  static const _accent = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);
  static const _textSub = Color(0xFF6B7280);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  String get _timeRange {
    final fmt = DateFormat('HH:mm');
    return '${fmt.format(widget.gymClass.startTime)} → ${fmt.format(widget.gymClass.endTime)}';
  }

  String get _dateLabel =>
      DateFormat('EEEE, d MMMM yyyy').format(widget.gymClass.startTime);

  String get _duration {
    final mins = widget.gymClass.endTime
        .difference(widget.gymClass.startTime)
        .inMinutes;
    if (mins <= 0) return '';
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  // ── actions ──────────────────────────────────────────────────────────────────

  Future<void> _toggleCheckIn(Booking booking) async {
    final key = booking.userId;
    if (_loadingMap[key] == true) return;
    setState(() => _loadingMap[key] = true);
    try {
      final me = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
      if (booking.checkedIn) {
        await _bookingService.undoCheckIn(
          classId: widget.gymClass.id,
          userId: booking.userId,
        );
      } else {
        await _bookingService.checkInMember(
          classId: widget.gymClass.id,
          userId: booking.userId,
          checkedInBy: me,
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'whiteboard_toggleCheckIn');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMap.remove(key));
    }
  }

  Future<void> _checkInAll(List<Booking> pending) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    for (final b in pending) {
      setState(() => _loadingMap[b.userId] = true);
    }
    try {
      for (final b in pending) {
        await _bookingService.checkInMember(
          classId: widget.gymClass.id,
          userId: b.userId,
          checkedInBy: me,
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'whiteboard_checkInAll');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMap.clear());
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: StreamBuilder<List<WodEntry>>(
          stream: _wodStream,
          builder: (context, wodSnap) {
            final wods = wodSnap.data ?? [];
            final wod = wods.isNotEmpty ? wods.first : null;

            return StreamBuilder<List<Booking>>(
              stream: _bookingsStream,
              builder: (context, bookSnap) {
                final bookings = bookSnap.data ?? [];
                final checkedIn =
                    bookings.where((b) => b.checkedIn).toList();
                final pending =
                    bookings.where((b) => !b.checkedIn).toList();

                return Column(
                  children: [
                    _Header(
                      gymClass: widget.gymClass,
                      timeRange: _timeRange,
                      dateLabel: _dateLabel,
                      duration: _duration,
                      checkedInCount: checkedIn.length,
                      totalCount: bookings.length,
                      pendingCount: pending.length,
                      onClose: () => Navigator.of(context).pop(),
                      onCheckInAll: pending.isEmpty
                          ? null
                          : () => _checkInAll(pending),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 760;
                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left: Workout panel
                                SizedBox(
                                  width: constraints.maxWidth * 0.42,
                                  child: _WodPanel(
                                    wod: wod,
                                    gymClass: widget.gymClass,
                                    dateLabel: _dateLabel,
                                  ),
                                ),
                                // Right: Whiteboard / members
                                Expanded(
                                  child: _MemberPanel(
                                    bookings: bookings,
                                    gymClass: widget.gymClass,
                                    loadingMap: _loadingMap,
                                    onToggle: _toggleCheckIn,
                                  ),
                                ),
                              ],
                            );
                          }
                          // Narrow: tabs
                          return Column(
                            children: [
                              Container(
                                color: _ClassWhiteboardScreenState._card,
                                child: TabBar(
                                  controller: _tabController,
                                  labelColor: _ClassWhiteboardScreenState._accent,
                                  unselectedLabelColor:
                                      _ClassWhiteboardScreenState._textSub,
                                  indicatorColor:
                                      _ClassWhiteboardScreenState._accent,
                                  dividerColor:
                                      _ClassWhiteboardScreenState._border,
                                  tabs: [
                                    Tab(text: context.l10n.tr('Workout')),
                                    Tab(
                                        text:
                                            '${context.l10n.tr('Members')} (${bookings.length})'),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _WodPanel(
                                      wod: wod,
                                      gymClass: widget.gymClass,
                                      dateLabel: _dateLabel,
                                    ),
                                    _MemberPanel(
                                      bookings: bookings,
                                      gymClass: widget.gymClass,
                                      loadingMap: _loadingMap,
                                      onToggle: _toggleCheckIn,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.gymClass,
    required this.timeRange,
    required this.dateLabel,
    required this.duration,
    required this.checkedInCount,
    required this.totalCount,
    required this.pendingCount,
    required this.onClose,
    required this.onCheckInAll,
  });

  final GymClass gymClass;
  final String timeRange;
  final String dateLabel;
  final String duration;
  final int checkedInCount;
  final int totalCount;
  final int pendingCount;
  final VoidCallback onClose;
  final VoidCallback? onCheckInAll;

  @override
  Widget build(BuildContext context) {
    const accent = _ClassWhiteboardScreenState._accent;
    const textSub = _ClassWhiteboardScreenState._textSub;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(bottom: BorderSide(color: Color(0xFF282828))),
      ),
      child: Row(
        children: [
          // Close
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, color: Colors.white70, size: 20),
            ),
          ),
          const SizedBox(width: 14),

          // Whiteboard icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.dashboard_outlined,
                color: accent, size: 18),
          ),
          const SizedBox(width: 12),

          // Title + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gymClass.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateLabel  ·  $timeRange'
                  '${duration.isEmpty ? '' : '  ·  $duration'}',
                  style: const TextStyle(color: textSub, fontSize: 12),
                ),
                if (gymClass.coachNames.isNotEmpty)
                  Text(
                    gymClass.coachNames.join(', '),
                    style: const TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),

          // Stats
          _StatChip(
            label: context.l10n.tr('Checked in'),
            value: '$checkedInCount / $totalCount',
            color: checkedInCount == totalCount && totalCount > 0
                ? const Color(0xFF16A34A)
                : accent,
          ),
          const SizedBox(width: 10),

          // Check in all button
          if (onCheckInAll != null)
            FilledButton.icon(
              onPressed: onCheckInAll,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
              icon: const Icon(Icons.done_all, size: 16),
              label: Text(
                  '${context.l10n.tr('Check In All')} ($pendingCount)'),
            ),
          if (onCheckInAll == null && totalCount > 0)
            _StatChip(
              label: '',
              value: context.l10n.tr('All checked in ✓'),
              color: const Color(0xFF16A34A),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WodPanel
// ─────────────────────────────────────────────────────────────────────────────

class _WodPanel extends StatelessWidget {
  const _WodPanel({
    required this.wod,
    required this.gymClass,
    required this.dateLabel,
  });

  final WodEntry? wod;
  final GymClass gymClass;
  final String dateLabel;

  static const _border = _ClassWhiteboardScreenState._border;
  static const _red = _ClassWhiteboardScreenState._red;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Section header ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                const Text(
                  'Workout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                // Trainer View button
                if (wod != null)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _TrainerViewScreen(
                          wod: wod!,
                          gymClass: gymClass,
                          dateLabel: dateLabel,
                        ),
                        fullscreenDialog: true,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fullscreen,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            context.l10n.tr('Trainer View'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── Content ───────────────────────────────────────────────────
          Expanded(child: _WodContent(wod: wod)),
        ],
      ),
    );
  }
}

class _WodContent extends StatelessWidget {
  const _WodContent({required this.wod});

  final WodEntry? wod;

  static const _accent = _ClassWhiteboardScreenState._accent;

  @override
  Widget build(BuildContext context) {
    if (wod == null) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fitness_center_outlined,
                  color: Colors.white12, size: 56),
              const SizedBox(height: 16),
              Text(
                context.l10n.tr('No WOD assigned for this class'),
                style: const TextStyle(color: Colors.white38, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // WOD title
        Text(
          wod!.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        if (wod!.classTypeName.isNotEmpty)
          Text(wod!.classTypeName,
              style: const TextStyle(color: _accent, fontSize: 13,
                  fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),

        // Warm-up
        if (wod!.warmUp.isNotEmpty) ...[
          _SectionLabel(context.l10n.tr('Warm-Up')),
          _TextBlock(wod!.warmUp),
          const SizedBox(height: 16),
        ],

        // Multi-part WOD
        if (wod!.parts.isNotEmpty)
          ...wod!.parts.asMap().entries.map((e) =>
              _WodPartCard(part: e.value, index: e.key))
        else ...[
          // Legacy flat format
          if (wod!.format.isNotEmpty || wod!.timeCap.isNotEmpty)
            _FormatRow(format: wod!.format, timeCap: wod!.timeCap),
          if (wod!.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TextBlock(wod!.description),
          ],
          if (wod!.exercises.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionLabel(context.l10n.tr('Exercises')),
            const SizedBox(height: 8),
            ...wod!.exercises.map(_ExerciseRow.new),
          ],
        ],

        // Cool-down
        if (wod!.coolDown.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionLabel(context.l10n.tr('Cool-Down')),
          _TextBlock(wod!.coolDown),
        ],

        // Member note
        if (wod!.memberNote.isNotEmpty) ...[
          const SizedBox(height: 16),
          _NoteBox(
            label: context.l10n.tr('Note for members'),
            text: wod!.memberNote,
            color: const Color(0xFF1D4ED8),
          ),
        ],

        // Coach note (visible on whiteboard)
        if (wod!.coachNote.isNotEmpty) ...[
          const SizedBox(height: 10),
          _NoteBox(
            label: context.l10n.tr('Coach note'),
            text: wod!.coachNote,
            color: const Color(0xFF92400E),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MemberPanel
// ─────────────────────────────────────────────────────────────────────────────

class _MemberPanel extends StatelessWidget {
  const _MemberPanel({
    required this.bookings,
    required this.gymClass,
    required this.loadingMap,
    required this.onToggle,
  });

  final List<Booking> bookings;
  final GymClass gymClass;
  final Map<String, bool> loadingMap;
  final Future<void> Function(Booking) onToggle;

  static const _border = _ClassWhiteboardScreenState._border;
  static const _textSub = _ClassWhiteboardScreenState._textSub;

  @override
  Widget build(BuildContext context) {
    // Sort: pending first, then checked-in
    final sorted = [...bookings]
      ..sort((a, b) {
        if (a.checkedIn == b.checkedIn) return 0;
        return a.checkedIn ? 1 : -1;
      });

    final checkedCount = bookings.where((b) => b.checkedIn).length;
    final fmt = DateFormat('HH:mm');
    final classTimeLabel =
        '${gymClass.title} (${fmt.format(gymClass.startTime)} - ${fmt.format(gymClass.endTime)})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Section header ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            children: [
              const Text(
                'Whiteboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _ClassWhiteboardScreenState._accent
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$checkedCount / ${bookings.length}',
                  style: const TextStyle(
                    color: _ClassWhiteboardScreenState._accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── Column headers ──────────────────────────────────────────────
        if (bookings.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 5,
                  child: Text('Name',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _textSub,
                          letterSpacing: 0.5)),
                ),
                const Expanded(
                  flex: 5,
                  child: Text('Class',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _textSub,
                          letterSpacing: 0.5)),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    context.l10n.tr('Attendance'),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textSub,
                        letterSpacing: 0.5),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        // ── Member rows ─────────────────────────────────────────────────
        Expanded(
          child: bookings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.group_off_outlined,
                          color: Colors.white12, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.tr('No bookings yet'),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: _border),
                  itemBuilder: (_, i) => _MemberRow(
                    booking: sorted[i],
                    classTimeLabel: classTimeLabel,
                    isLoading: loadingMap[sorted[i].userId] == true,
                    onTap: () => onToggle(sorted[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MemberRow — table-style row matching Octiv whiteboard layout
// ─────────────────────────────────────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.booking,
    required this.classTimeLabel,
    required this.isLoading,
    required this.onTap,
  });

  final Booking booking;
  final String classTimeLabel;
  final bool isLoading;
  final VoidCallback onTap;

  static const _checkedColor = Color(0xFF16A34A);
  static const _pendingColor = Color(0xFFD97706);

  String get _initials {
    final parts = booking.memberName.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final checked = booking.checkedIn;
    final statusColor = checked ? _checkedColor : _pendingColor;

    return Container(
      color: checked
          ? const Color(0xFF14532D).withValues(alpha: 0.12)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // ── Name column ─────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: statusColor.withValues(alpha: 0.18),
                  child: Text(
                    _initials,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.memberName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (booking.isDropIn)
                        const Text(
                          'Drop-in',
                          style: TextStyle(
                              color: Color(0xFFA78BFA),
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Class column ────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Text(
              classTimeLabel,
              style: const TextStyle(
                  color: _ClassWhiteboardScreenState._textSub,
                  fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // ── Attendance column ───────────────────────────────────────
          SizedBox(
            width: 90,
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white38),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Green check = checked in
                      GestureDetector(
                        onTap: checked ? onTap : onTap,
                        child: Icon(
                          checked
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          color: checked
                              ? _checkedColor
                              : Colors.white24,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Grey eye/slash = not checked in indicator
                      Icon(
                        checked
                            ? Icons.visibility
                            : Icons.visibility_off_outlined,
                        color: checked
                            ? Colors.white24
                            : _ClassWhiteboardScreenState._textSub,
                        size: 20,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TrainerViewScreen — full-screen workout display (like Octiv Trainer View)
// ─────────────────────────────────────────────────────────────────────────────

class _TrainerViewScreen extends StatefulWidget {
  const _TrainerViewScreen({
    required this.wod,
    required this.gymClass,
    required this.dateLabel,
  });

  final WodEntry wod;
  final GymClass gymClass;
  final String dateLabel;

  @override
  State<_TrainerViewScreen> createState() => _TrainerViewScreenState();
}

class _TrainerViewScreenState extends State<_TrainerViewScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  // Build the list of sections to display: warm-up, each part, cool-down
  late final List<_TrainerSection> _sections = _buildSections();

  List<_TrainerSection> _buildSections() {
    final wod = widget.wod;
    final sections = <_TrainerSection>[];

    if (wod.warmUp.isNotEmpty) {
      sections.add(_TrainerSection(
          label: 'Warm Up', content: wod.warmUp, isText: true));
    }

    if (wod.parts.isNotEmpty) {
      for (var i = 0; i < wod.parts.length; i++) {
        final p = wod.parts[i];
        final buf = StringBuffer();
        if (p.format.isNotEmpty) buf.writeln(p.format);
        if (p.timeCap.isNotEmpty) buf.writeln('Time cap: ${p.timeCap}');
        if (p.description.isNotEmpty) buf.writeln(p.description);
        for (final ex in p.exercises) {
          buf.writeln(
              '• ${ex.name}${ex.shortLabel.isNotEmpty ? '  ${ex.shortLabel}' : ''}${ex.notes.isNotEmpty ? '  — ${ex.notes}' : ''}');
        }
        sections.add(_TrainerSection(
            label: 'Part ${String.fromCharCode(65 + i)}: ${p.title}',
            content: buf.toString().trim(),
            isText: true));
      }
    } else {
      if (wod.description.isNotEmpty || wod.exercises.isNotEmpty) {
        final buf = StringBuffer();
        if (wod.format.isNotEmpty) buf.writeln(wod.format);
        if (wod.timeCap.isNotEmpty) buf.writeln('Time cap: ${wod.timeCap}');
        if (wod.description.isNotEmpty) buf.writeln(wod.description);
        for (final ex in wod.exercises) {
          buf.writeln(
              '• ${ex.name}${ex.shortLabel.isNotEmpty ? '  ${ex.shortLabel}' : ''}${ex.notes.isNotEmpty ? '  — ${ex.notes}' : ''}');
        }
        sections.add(_TrainerSection(
            label: wod.title,
            content: buf.toString().trim(),
            isText: true));
      }
    }

    if (wod.coolDown.isNotEmpty) {
      sections.add(_TrainerSection(
          label: 'Cool Down', content: wod.coolDown, isText: true));
    }

    if (sections.isEmpty) {
      sections.add(_TrainerSection(
          label: wod.title, content: wod.description, isText: true));
    }

    return sections;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _sections.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _prev() {
    if (_currentPage > 0) {
      _pageController.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final headerTitle =
        '${widget.gymClass.title} – ${fmt.format(widget.gymClass.startTime)}';

    final hasPrev = _currentPage > 0;
    final hasNext = _currentPage < _sections.length - 1;
    final prevLabel = hasPrev ? _sections[_currentPage - 1].label : null;
    final nextLabel = hasNext ? _sections[_currentPage + 1].label : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Red header bar ───────────────────────────────────────────
            Container(
              color: const Color(0xFFEF4444),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  // WOD title (left)
                  Expanded(
                    child: Text(
                      headerTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // ← Prev section name
                  if (prevLabel != null)
                    GestureDetector(
                      onTap: _prev,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_back_ios,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 3),
                          Text(
                            prevLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  if (prevLabel != null && nextLabel != null)
                    const SizedBox(width: 16),
                  // Next section name →
                  if (nextLabel != null)
                    GestureDetector(
                      onTap: _next,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            nextLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.arrow_forward_ios,
                              color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  const SizedBox(width: 16),
                  // Close
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close,
                        color: Colors.white70, size: 22),
                  ),
                ],
              ),
            ),
            // ── Workout content ──────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _sections.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) {
                  final s = _sections[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Part title in large red text
                        Text(
                          s.label,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Content
                        if (s.content.isNotEmpty)
                          Text(
                            s.content,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              height: 1.7,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // ── Dot indicators ───────────────────────────────────────────
            if (_sections.length > 1)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                child: Row(
                  children: [
                    ...List.generate(_sections.length, (i) {
                      final active = i == _currentPage;
                      return GestureDetector(
                        onTap: () => _pageController.animateToPage(i,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          width: active ? 28 : 8,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xFFEF4444)
                                : Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      );
                    }),
                    const Spacer(),
                    Text(
                      '${_currentPage + 1} / ${_sections.length}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrainerSection {
  const _TrainerSection(
      {required this.label,
      required this.content,
      required this.isText});

  final String label;
  final String content;
  final bool isText;
}

// ─────────────────────────────────────────────────────────────────────────────
// WOD sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _WodPartCard extends StatelessWidget {
  const _WodPartCard({required this.part, required this.index});

  final WodPart part;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ClassWhiteboardScreenState._card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _ClassWhiteboardScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _ClassWhiteboardScreenState._accent
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    String.fromCharCode(65 + index), // A, B, C…
                    style: const TextStyle(
                        color: _ClassWhiteboardScreenState._accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  part.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
              ),
              if (part.format.isNotEmpty)
                _FormatBadge(part.format),
            ],
          ),
          if (part.timeCap.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.timer_outlined,
                  size: 13, color: _ClassWhiteboardScreenState._textSub),
              const SizedBox(width: 4),
              Text(part.timeCap,
                  style: const TextStyle(
                      color: _ClassWhiteboardScreenState._textSub,
                      fontSize: 12)),
            ]),
          ],
          if (part.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TextBlock(part.description),
          ],
          if (part.exercises.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...part.exercises.map(_ExerciseRow.new),
          ],
          if (part.scales.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...part.scales.map((s) => _ScaleBlock(scale: s)),
          ],
        ],
      ),
    );
  }
}

class _ScaleBlock extends StatelessWidget {
  const _ScaleBlock({required this.scale});

  final WodScale scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                scale.label,
                style: const TextStyle(
                    color: Color(0xFFA78BFA),
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          if (scale.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            _TextBlock(scale.description),
          ],
          ...scale.exercises.map(_ExerciseRow.new),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow(this.ex);

  final WodExercise ex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ',
              style: TextStyle(
                  color: _ClassWhiteboardScreenState._accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: Colors.white),
                children: [
                  TextSpan(
                    text: ex.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (ex.shortLabel.isNotEmpty)
                    TextSpan(
                      text: '  ${ex.shortLabel}',
                      style: const TextStyle(
                          color: _ClassWhiteboardScreenState._accent,
                          fontWeight: FontWeight.w700),
                    ),
                  if (ex.notes.isNotEmpty)
                    TextSpan(
                      text: '  — ${ex.notes}',
                      style: const TextStyle(
                          color: _ClassWhiteboardScreenState._textSub,
                          fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.format, required this.timeCap});

  final String format;
  final String timeCap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        if (format.isNotEmpty) _FormatBadge(format),
        if (timeCap.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined,
                    size: 12, color: Color(0xFFF59E0B)),
                const SizedBox(width: 4),
                Text(
                  timeCap,
                  style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge(this.format);

  final String format;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _ClassWhiteboardScreenState._accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        format,
        style: const TextStyle(
            color: _ClassWhiteboardScreenState._accent,
            fontSize: 12,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: _ClassWhiteboardScreenState._textSub,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          color: Color(0xFFE5E7EB), fontSize: 13, height: 1.5),
    );
  }
}

class _NoteBox extends StatelessWidget {
  const _NoteBox(
      {required this.label, required this.text, required this.color});

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800),
          ),
          if (label.isNotEmpty)
            Text(label,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}
