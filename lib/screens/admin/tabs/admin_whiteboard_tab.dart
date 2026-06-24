import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/booking.dart';
import '../../../models/gym_class.dart';
import '../../../models/wod_entry.dart';
import '../../../services/booking_service.dart';
import '../../../services/class_service.dart';
import '../../../services/wod_service.dart';
import '../../../utils/crash_logger.dart';
import '../class_whiteboard_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminWhiteboardTab — inline whiteboard hub in the admin shell
// ─────────────────────────────────────────────────────────────────────────────

class AdminWhiteboardTab extends StatefulWidget {
  const AdminWhiteboardTab({
    super.key,
    required this.gymId,
    this.firestore,
  });
  final String gymId;
  // Optional override for dependency injection in tests.
  final FirebaseFirestore? firestore;

  @override
  State<AdminWhiteboardTab> createState() => _AdminWhiteboardTabState();
}

class _AdminWhiteboardTabState extends State<AdminWhiteboardTab> {
  // ── colour palette (matches ClassWhiteboardScreen) ──────────────────────
  static const _bg = Color(0xFF0A1F1A);
  static const _surface = Color(0xFF0D2920);
  static const _card = Color(0xFF112820);
  static const _border = Color(0xFF1A3530);
  static const _accent = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);
  static const _textSub = Color(0xFF9CA3AF);

  late final ClassService _classService =
      ClassService(gymId: widget.gymId, firestore: widget.firestore);
  late final WodService _wodService =
      WodService(gymId: widget.gymId, firestore: widget.firestore);
  late final BookingService _bookingService =
      BookingService(gymId: widget.gymId, firestore: widget.firestore);

  DateTime _selectedDate = _today();
  GymClass? _selectedClass;
  final Map<String, bool> _loadingMap = {};

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  List<GymClass> _forDate(List<GymClass> all) => all.where((c) {
        final d = c.startTime;
        return d.year == _selectedDate.year &&
            d.month == _selectedDate.month &&
            d.day == _selectedDate.day;
      }).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  String _timeLabel(GymClass c) {
    final f = DateFormat('HH:mm');
    return '${c.title} (${f.format(c.startTime)} - ${f.format(c.endTime)})';
  }

  String _classPillLabel(GymClass c) {
    final f = DateFormat('HH:mm');
    return '${f.format(c.startTime)} • ${c.title}';
  }

  Future<void> _toggleCheckIn(Booking booking) async {
    if (_selectedClass == null) return;
    final key = booking.userId;
    if (_loadingMap[key] == true) return;
    setState(() => _loadingMap[key] = true);
    try {
      final me = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
      if (booking.checkedIn) {
        await _bookingService.undoCheckIn(
          classId: _selectedClass!.id,
          userId: booking.userId,
        );
      } else {
        await _bookingService.checkInMember(
          classId: _selectedClass!.id,
          userId: booking.userId,
          checkedInBy: me,
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'whiteboard_hub_toggle');
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
    if (_selectedClass == null) return;
    final me = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    for (final b in pending) {
      setState(() => _loadingMap[b.userId] = true);
    }
    try {
      for (final b in pending) {
        await _bookingService.checkInMember(
          classId: _selectedClass!.id,
          userId: b.userId,
          checkedInBy: me,
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'whiteboard_hub_checkInAll');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMap.clear());
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _selectedClass = null;
      });
    }
  }

  void _openTrainerView(WodEntry wod) {
    if (_selectedClass == null) return;
    final fmt = DateFormat('EEEE, d MMMM yyyy');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _TrainerViewProxy(
          wod: wod,
          gymClass: _selectedClass!,
          dateLabel: fmt.format(_selectedClass!.startTime),
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    final isToday = _selectedDate == _today();

    return Material(
      color: _bg,
      child: StreamBuilder<List<GymClass>>(
        stream: _classService.streamAllClasses(),
        builder: (context, classSnap) {
          final allClasses = classSnap.data ?? [];
          final dayClasses = _forDate(allClasses);

          // Reconcile _selectedClass against the fresh list by ID to avoid
          // DropdownButton assertion (value must be in items list).
          final selectedId = _selectedClass?.id;
          GymClass? reconciled;
          if (selectedId != null) {
            final matches = dayClasses.where((c) => c.id == selectedId);
            reconciled = matches.isNotEmpty ? matches.first : null;
          } else if (dayClasses.isNotEmpty) {
            reconciled = dayClasses.first;
          }

          if (reconciled != _selectedClass) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedClass = reconciled);
            });
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top header ──────────────────────────────────────────────
              _buildTopBar(dateFmt, isToday, dayClasses, reconciled),
              if (classSnap.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: _surface,
                  valueColor: AlwaysStoppedAnimation<Color>(_accent),
                ),
              if (reconciled != null) _buildStatsBar(reconciled),
              // ── Section headers row ─────────────────────────────────────
              if (reconciled != null) _buildSectionHeaders(reconciled),
              // ── Main content ─────────────────────────────────────────────
              Expanded(
                child: reconciled == null
                    ? (classSnap.connectionState == ConnectionState.waiting &&
                            !classSnap.hasData
                        ? const _WhiteboardLoadingSkeleton()
                        : _buildNoSelection(dayClasses.isEmpty))
                    : _buildWhiteboardContent(reconciled),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Top bar: date + class selector ───────────────────────────────────────

  Widget _buildTopBar(DateFormat dateFmt, bool isToday,
      List<GymClass> dayClasses, GymClass? currentClass) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0C1C17),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        if (wide) {
          return Row(
            children: [
              _DateChip(
                label: isToday
                    ? context.l10n.tr('Today')
                    : dateFmt.format(_selectedDate),
                onTap: _pickDate,
                onPrev: () => setState(() {
                  _selectedDate =
                      _selectedDate.subtract(const Duration(days: 1));
                  _selectedClass = null;
                }),
                onNext: () => setState(() {
                  _selectedDate = _selectedDate.add(const Duration(days: 1));
                  _selectedClass = null;
                }),
              ),
              const SizedBox(width: 16),
              // Class dropdown
              Expanded(
                child: _ClassPillSelector(
                  classes: dayClasses,
                  selected: currentClass,
                  onChanged: (c) => setState(() {
                    _selectedClass = c;
                    _loadingMap.clear();
                  }),
                  timeLabel: _classPillLabel,
                ),
              ),
              const SizedBox(width: 12),
              // Add Bookings button
              if (currentClass != null)
                FilledButton.icon(
                  onPressed: () {}, // placeholder — open booking dialog
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(context.l10n.tr('Add Bookings')),
                  style: FilledButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          );
        }
        // Narrow: stacked
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DateChip(
              label: isToday
                  ? context.l10n.tr('Today')
                  : dateFmt.format(_selectedDate),
              onTap: _pickDate,
              onPrev: () => setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                _selectedClass = null;
              }),
              onNext: () => setState(() {
                _selectedDate = _selectedDate.add(const Duration(days: 1));
                _selectedClass = null;
              }),
            ),
            const SizedBox(height: 8),
            _ClassPillSelector(
              classes: dayClasses,
              selected: _selectedClass,
              onChanged: (c) => setState(() {
                _selectedClass = c;
                _loadingMap.clear();
              }),
              timeLabel: _classPillLabel,
            ),
          ],
        );
      }),
    );
  }

  Widget _buildStatsBar(GymClass gymClass) {
    return StreamBuilder<List<Booking>>(
      stream: _bookingService.streamBookingsForClass(gymClass.id),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const _StatsBarSkeleton();
        }

        final bookings = snap.data ?? [];
        final checkedIn = bookings.where((b) => b.checkedIn).length;
        final pending = bookings.length - checkedIn;

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatChip(
                icon: Icons.people_outline,
                label: 'Total',
                value: '${bookings.length}',
                color: Colors.white,
              ),
              _StatChip(
                icon: Icons.check_circle,
                label: 'Checked In',
                value: '$checkedIn',
                color: _accent,
              ),
              _StatChip(
                icon: Icons.schedule_outlined,
                label: 'Pending',
                value: '$pending',
                color: const Color(0xFFF59E0B),
              ),
              if (gymClass.capacity > 0)
                _StatChip(
                  icon: Icons.event_seat_outlined,
                  label: 'Capacity',
                  value: '${bookings.length}/${gymClass.capacity}',
                  color: _textSub,
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Section header row: "Workout" | "Whiteboard" ─────────────────────────

  Widget _buildSectionHeaders(GymClass gymClass) {
    return StreamBuilder<List<Booking>>(
      stream: _bookingService.streamBookingsForClass(gymClass.id),
      builder: (context, snap) {
        final pending = (snap.data ?? []).where((b) => !b.checkedIn).toList();

        return Container(
          decoration: const BoxDecoration(
            color: _surface,
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            if (!wide) return const SizedBox.shrink();
            return Row(
              children: [
                SizedBox(
                  width: constraints.maxWidth * 0.40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: const _PanelHeaderTitle(
                      title: 'Workout',
                      subtitle: 'Daily programming',
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: _PanelHeaderTitle(
                            title: 'Whiteboard',
                            subtitle: 'Member attendance',
                          ),
                        ),
                        if (pending.isNotEmpty)
                          FilledButton.icon(
                            onPressed: () => _checkInAll(pending),
                            icon: const Icon(Icons.done_all, size: 14),
                            label: Text(
                                '${context.l10n.tr('Check In All')} (${pending.length})'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        );
      },
    );
  }

  // ── Main embedded whiteboard ──────────────────────────────────────────────

  Widget _buildWhiteboardContent(GymClass gymClass) {
    return StreamBuilder<List<WodEntry>>(
      stream: _wodService.streamForDate(
        gymClass.startTime,
        classTypeId: gymClass.classTypeId,
      ),
      builder: (context, wodSnap) {
        final wod =
            (wodSnap.data?.isNotEmpty == true) ? wodSnap.data!.first : null;

        return StreamBuilder<List<Booking>>(
          stream: _bookingService.streamBookingsForClass(gymClass.id),
          builder: (context, bookSnap) {
            final bookings = bookSnap.data ?? [];

            return LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;

              if ((wodSnap.connectionState == ConnectionState.waiting &&
                      !wodSnap.hasData) ||
                  (bookSnap.connectionState == ConnectionState.waiting &&
                      !bookSnap.hasData)) {
                return _WhiteboardLoadingSkeleton(wide: wide);
              }

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: constraints.maxWidth * 0.40,
                      child: _InlineWodPanel(
                        wod: wod,
                        gymClass: gymClass,
                        onTrainerView: () =>
                            wod != null ? _openTrainerView(wod) : null,
                      ),
                    ),
                    Expanded(
                      child: _InlineMemberPanel(
                        bookings: bookings,
                        classLabel: _timeLabel(gymClass),
                        loadingMap: _loadingMap,
                        onToggle: _toggleCheckIn,
                      ),
                    ),
                  ],
                );
              }

              // Narrow: stacked with toggle
              return DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Container(
                      color: _card,
                      child: TabBar(
                        labelColor: _accent,
                        unselectedLabelColor: _textSub,
                        indicatorColor: _accent,
                        dividerColor: _border,
                        tabs: [
                          Tab(text: context.l10n.tr('Workout')),
                          Tab(
                              text:
                                  '${context.l10n.tr('Members')} (${bookings.length})'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(children: [
                        _InlineWodPanel(
                          wod: wod,
                          gymClass: gymClass,
                          onTrainerView: () =>
                              wod != null ? _openTrainerView(wod) : null,
                        ),
                        _InlineMemberPanel(
                          bookings: bookings,
                          classLabel: _timeLabel(gymClass),
                          loadingMap: _loadingMap,
                          onToggle: _toggleCheckIn,
                        ),
                      ]),
                    ),
                  ],
                ),
              );
            });
          },
        );
      },
    );
  }

  Widget _buildNoSelection(bool noClasses) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.dashboard_outlined, size: 36, color: _accent),
          ),
          const SizedBox(height: 20),
          Text(
            noClasses
                ? 'No classes on this day'
                : 'Select a class to view the whiteboard',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Use the date picker to navigate to another day',
            style: TextStyle(color: _textSub, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DateChip
// ─────────────────────────────────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.onTap,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const _border = _AdminWhiteboardTabState._border;
  static const _textSub = _AdminWhiteboardTabState._textSub;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: _textSub, size: 20),
          onPressed: onPrev,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0D2920),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: _textSub),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _textSub.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 10, color: _textSub),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: _textSub, size: 20),
          onPressed: onNext,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ClassPillSelector
// ─────────────────────────────────────────────────────────────────────────────

class _ClassPillSelector extends StatelessWidget {
  const _ClassPillSelector({
    required this.classes,
    required this.selected,
    required this.onChanged,
    required this.timeLabel,
  });

  final List<GymClass> classes;
  final GymClass? selected;
  final void Function(GymClass?) onChanged;
  final String Function(GymClass) timeLabel;

  static const _border = _AdminWhiteboardTabState._border;
  static const _textSub = _AdminWhiteboardTabState._textSub;
  static const _accent = _AdminWhiteboardTabState._accent;
  static const _surface = _AdminWhiteboardTabState._surface;
  static const _card = _AdminWhiteboardTabState._card;

  @override
  Widget build(BuildContext context) {
    if (classes.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0D2920),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border),
        ),
        child: const Text('No classes',
            style: TextStyle(color: _textSub, fontSize: 13)),
      );
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: classes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final gymClass = classes[index];
          final isSelected = selected?.id == gymClass.id;
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onChanged(gymClass),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _accent : _card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected
                      ? _accent
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Text(
                timeLabel(gymClass),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PanelHeaderTitle extends StatelessWidget {
  const _PanelHeaderTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: _textSub, fontSize: 11),
        ),
      ],
    );
  }

  static const _textSub = _AdminWhiteboardTabState._textSub;
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _AdminWhiteboardTabState._surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _AdminWhiteboardTabState._border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
                color: _textSub, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  static const _textSub = _AdminWhiteboardTabState._textSub;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _StatsBarSkeleton extends StatelessWidget {
  const _StatsBarSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _AdminWhiteboardTabState._card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AdminWhiteboardTabState._border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: const [
          _SkeletonBox(width: 118, height: 36),
          _SkeletonBox(width: 128, height: 36),
          _SkeletonBox(width: 116, height: 36),
          _SkeletonBox(width: 122, height: 36),
        ],
      ),
    );
  }
}

class _WhiteboardLoadingSkeleton extends StatelessWidget {
  const _WhiteboardLoadingSkeleton({this.wide = false});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SizedBox(
            width: 340,
            child: _PanelLoadingSkeleton(lines: 8, showButton: true),
          ),
          Expanded(child: _MemberLoadingSkeleton()),
        ],
      );
    }

    return const Column(
      children: [
        LinearProgressIndicator(
          minHeight: 2,
          backgroundColor: _AdminWhiteboardTabState._surface,
          valueColor:
              AlwaysStoppedAnimation<Color>(_AdminWhiteboardTabState._accent),
        ),
        Expanded(child: _PanelLoadingSkeleton(lines: 8, showButton: true)),
      ],
    );
  }
}

class _PanelLoadingSkeleton extends StatelessWidget {
  const _PanelLoadingSkeleton({required this.lines, this.showButton = false});

  final int lines;
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showButton) ...[
            const _SkeletonBox(width: double.infinity, height: 42),
            const SizedBox(height: 18),
          ],
          const _SkeletonBox(width: 84, height: 12),
          const SizedBox(height: 10),
          ...List.generate(
            lines,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SkeletonBox(
                width: index.isEven ? double.infinity : 220,
                height: index % 3 == 0 ? 54 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberLoadingSkeleton extends StatelessWidget {
  const _MemberLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: _AdminWhiteboardTabState._surface,
            border: Border(
              bottom: BorderSide(color: _AdminWhiteboardTabState._border),
            ),
          ),
          child: const Row(
            children: [
              Expanded(flex: 5, child: _SkeletonBox(width: 110, height: 12)),
              Expanded(flex: 5, child: _SkeletonBox(width: 120, height: 12)),
              SizedBox(width: 90, child: _SkeletonBox(width: 70, height: 12)),
              SizedBox(width: 140, child: _SkeletonBox(width: 100, height: 12)),
              SizedBox(width: 32),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: 6,
            itemBuilder: (context, index) => Container(
              height: 72,
              decoration: BoxDecoration(
                color: index.isOdd
                    ? _AdminWhiteboardTabState._surface
                    : Colors.transparent,
                border: const Border(
                  left: BorderSide(color: Color(0xFFF59E0B), width: 3),
                  bottom: BorderSide(color: _AdminWhiteboardTabState._border),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: const Row(
                children: [
                  _SkeletonBox(width: 34, height: 22),
                  SizedBox(width: 10),
                  _SkeletonCircle(size: 32),
                  SizedBox(width: 10),
                  Expanded(
                      flex: 5, child: _SkeletonBox(width: 120, height: 12)),
                  Expanded(
                      flex: 5, child: _SkeletonBox(width: 150, height: 12)),
                  SizedBox(
                      width: 90, child: _SkeletonBox(width: 70, height: 12)),
                  SizedBox(
                      width: 140, child: _SkeletonBox(width: 110, height: 28)),
                  SizedBox(width: 32),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

class _SkeletonCircle extends StatelessWidget {
  const _SkeletonCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InlineWodPanel — WOD content + Trainer View button
// ─────────────────────────────────────────────────────────────────────────────

class _InlineWodPanel extends StatelessWidget {
  const _InlineWodPanel({
    required this.wod,
    required this.gymClass,
    required this.onTrainerView,
  });

  final WodEntry? wod;
  final GymClass gymClass;
  final VoidCallback? onTrainerView;

  static const _border = _AdminWhiteboardTabState._border;
  static const _red = _AdminWhiteboardTabState._red;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: _border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trainer View full-width button
          if (wod != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: SizedBox(
                height: 42,
                child: FilledButton.icon(
                  onPressed: onTrainerView,
                  icon: const Icon(Icons.fullscreen, size: 16),
                  label: Text(
                    'Trainer View',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
          // WOD content
          Expanded(child: _WodScrollContent(wod: wod)),
        ],
      ),
    );
  }
}

class _WodScrollContent extends StatelessWidget {
  const _WodScrollContent({required this.wod});
  final WodEntry? wod;

  @override
  Widget build(BuildContext context) {
    if (wod == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fitness_center_outlined,
                color: Colors.white12, size: 48),
            const SizedBox(height: 12),
            const Text('No WOD assigned for this class',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (wod!.warmUp.isNotEmpty) ...[
          const _WbLabel('WARM UP'),
          _WbText(wod!.warmUp),
          const SizedBox(height: 18),
        ],
        if (wod!.parts.isNotEmpty)
          ...wod!.parts.asMap().entries.map((e) => _WbPart(e.value, e.key))
        else ...[
          const _WbLabel('WORKOUT'),
          if (wod!.format.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _WbMetaChips(values: [
                wod!.format,
                if (wod!.timeCap.isNotEmpty) wod!.timeCap,
              ]),
            ),
          if (wod!.description.isNotEmpty) _WbText(wod!.description),
          if (wod!.description.isNotEmpty) const SizedBox(height: 10),
          ...wod!.exercises.map((ex) => _WbExercise(ex)),
        ],
        if (wod!.coolDown.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _WbLabel('COOL DOWN'),
          _WbText(wod!.coolDown),
        ],
      ],
    );
  }
}

class _WbLabel extends StatelessWidget {
  const _WbLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: _textSub,
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800)),
      );

  static const _textSub = _AdminWhiteboardTabState._textSub;
}

class _WbText extends StatelessWidget {
  const _WbText(this.text);
  final String text;

  static const _border = _AdminWhiteboardTabState._border;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _AdminWhiteboardTabState._card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFFD1FAE5), fontSize: 13, height: 1.6)),
      );
}

class _WbPart extends StatelessWidget {
  const _WbPart(this.part, this.index);
  final WodPart part;
  final int index;

  static const _accent = _AdminWhiteboardTabState._accent;

  @override
  Widget build(BuildContext context) {
    final partLabel = 'PART ${String.fromCharCode(65 + index)}'
        '${part.title.isNotEmpty ? ': ${part.title.toUpperCase()}' : ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: _AdminWhiteboardTabState._card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _AdminWhiteboardTabState._border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Accent left strip
                Container(width: 3, color: _accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 14, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partLabel,
                          style: const TextStyle(
                              color: _accent,
                              fontSize: 12,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w800),
                        ),
                        if (part.measure.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Measure: ${part.measure}',
                            style: const TextStyle(
                                color: _AdminWhiteboardTabState._textSub,
                                fontSize: 11),
                          ),
                        ],
                        if (part.format.isNotEmpty || part.timeCap.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _WbMetaChips(values: [
                            if (part.format.isNotEmpty) part.format,
                            if (part.timeCap.isNotEmpty) part.timeCap,
                          ]),
                        ],
                        if (part.description.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(part.description,
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.55)),
                        ],
                        if (part.exercises.isNotEmpty) const SizedBox(height: 10),
                        ...part.exercises.map((ex) => _WbExercise(ex)),
                        // ── Scales (Rx / Intermediate / Scaled) ──────────
                        if (part.scales.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ...part.scales.map((s) => _WbScale(s)),
                        ],
                      ],
                    ),
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

class _WbMetaChips extends StatelessWidget {
  const _WbMetaChips({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .where((value) => value.trim().isNotEmpty)
          .map(
            (value) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Text(
                value,
                style: const TextStyle(
                    color: _textSub, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          )
          .toList(),
    );
  }

  static const _textSub = _AdminWhiteboardTabState._textSub;
}

class _WbExercise extends StatelessWidget {
  const _WbExercise(this.ex);
  final WodExercise ex;

  static const _accent = _AdminWhiteboardTabState._accent;
  static const _textSub = _AdminWhiteboardTabState._textSub;

  @override
  Widget build(BuildContext context) {
    final repLabel = <String>[
      if (ex.sets.isNotEmpty) '${ex.sets} sets',
      if (ex.reps.isNotEmpty) ex.reps,
      if (ex.weight.isNotEmpty) ex.weight,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 7),
          decoration: const BoxDecoration(
            color: _accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    if (repLabel.isNotEmpty)
                      TextSpan(
                        text: '$repLabel  ',
                        style: const TextStyle(
                            color: _accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    TextSpan(
                      text: ex.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (ex.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  ex.notes,
                  style: const TextStyle(
                      color: _textSub, fontSize: 12, height: 1.45),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WbScale — renders a single scale block (Rx / Intermediate / Scaled)
// ─────────────────────────────────────────────────────────────────────────────

class _WbScale extends StatelessWidget {
  const _WbScale(this.scale);
  final WodScale scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scale label pill (Rx, Intermediate, Scaled…)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
            ),
            child: Text(
              '— ${scale.label} —',
              style: const TextStyle(
                  color: Color(0xFFA78BFA),
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
          if (scale.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(scale.description,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5)),
          ],
          if (scale.exercises.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...scale.exercises.map((ex) => _WbExercise(ex)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InlineMemberPanel — table-style member roster
// ─────────────────────────────────────────────────────────────────────────────

class _InlineMemberPanel extends StatelessWidget {
  const _InlineMemberPanel({
    required this.bookings,
    required this.classLabel,
    required this.loadingMap,
    required this.onToggle,
  });

  final List<Booking> bookings;
  final String classLabel;
  final Map<String, bool> loadingMap;
  final Future<void> Function(Booking) onToggle;

  static const _border = _AdminWhiteboardTabState._border;
  static const _textSub = _AdminWhiteboardTabState._textSub;
  static const _surface = _AdminWhiteboardTabState._surface;

  @override
  Widget build(BuildContext context) {
    final sorted = [...bookings]..sort((a, b) {
        if (a.checkedIn == b.checkedIn) return 0;
        return a.checkedIn ? 1 : -1;
      });

    return Column(
      children: [
        // Column headers
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: _surface,
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
              const SizedBox(
                width: 90,
                child: Text('Results',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textSub,
                        letterSpacing: 0.5),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(
                width: 140,
                child: Text('Attendance',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textSub,
                        letterSpacing: 0.5),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(width: 32),
            ],
          ),
        ),
        // Member rows
        if (bookings.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: _AdminWhiteboardTabState._card,
                      shape: BoxShape.circle,
                      border: Border.all(color: _border),
                    ),
                    child: const Icon(Icons.event_busy_outlined,
                        color: Colors.white24, size: 42),
                  ),
                  const SizedBox(height: 16),
                  const Text('No bookings for this class',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 6),
                  const Text('Bookings will appear here once members reserve.',
                      style: TextStyle(color: _textSub, fontSize: 12)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: sorted.length,
              itemBuilder: (_, i) => _InlineMemberRow(
                booking: sorted[i],
                classLabel: classLabel,
                memberNumber: i + 1,
                rowIndex: i,
                isLoading: loadingMap[sorted[i].userId] == true,
                onTap: () => onToggle(sorted[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _InlineMemberRow extends StatelessWidget {
  const _InlineMemberRow({
    required this.booking,
    required this.classLabel,
    required this.memberNumber,
    required this.rowIndex,
    required this.isLoading,
    required this.onTap,
  });

  final Booking booking;
  final String classLabel;
  final int memberNumber;
  final int rowIndex;
  final bool isLoading;
  final VoidCallback onTap;

  static const _checked = Color(0xFF16A34A);
  static const _pending = Color(0xFFF59E0B);
  static const _border = _AdminWhiteboardTabState._border;
  static const _surface = _AdminWhiteboardTabState._surface;
  static const _textSub = _AdminWhiteboardTabState._textSub;

  String get _initials {
    final parts = booking.memberName.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final checked = booking.checkedIn;
    final statusColor = checked ? _checked : _pending;
    final baseColor = rowIndex.isOdd ? _surface : Colors.transparent;
    final rowColor = checked
        ? Color.alphaBlend(
            _checked.withValues(alpha: 0.08),
            baseColor == Colors.transparent ? Colors.transparent : baseColor,
          )
        : baseColor;

    return Material(
      color: rowColor,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        hoverColor: Colors.white.withValues(alpha: 0.03),
        splashColor: statusColor.withValues(alpha: 0.10),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: statusColor, width: 3),
              bottom: const BorderSide(color: _border),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text(
                        '#$memberNumber',
                        style: const TextStyle(
                            color: _textSub,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: statusColor.withValues(alpha: 0.18),
                      child: Text(_initials,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(booking.memberName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          if (booking.isDropIn)
                            const Text('Drop-in',
                                style: TextStyle(
                                    color: Color(0xFFA78BFA),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Text(classLabel,
                    style: const TextStyle(color: _textSub, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              SizedBox(
                width: 90,
                child: Center(
                  child: Text(
                    'Log Result',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white24),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white38)),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(
                              scale: animation,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                            child: Icon(
                              checked
                                  ? Icons.check_circle
                                  : Icons.check_circle_outline,
                              key: ValueKey<bool>(checked),
                              color: checked ? _checked : Colors.white24,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(
                            label: checked ? 'Checked In' : 'Pending',
                            color: statusColor,
                          ),
                        ],
                      ),
              ),
              SizedBox(
                width: 32,
                child: Icon(Icons.more_vert, color: Colors.white24, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TrainerViewProxy — routes to the Trainer View screen from the hub
// ─────────────────────────────────────────────────────────────────────────────

class _TrainerViewProxy extends StatelessWidget {
  const _TrainerViewProxy({
    required this.wod,
    required this.gymClass,
    required this.dateLabel,
  });

  final WodEntry wod;
  final GymClass gymClass;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    // We open the ClassWhiteboardScreen just to reuse _TrainerViewScreen
    // which is a private class. Instead, redirect through ClassWhiteboardScreen
    // with a push-replace into trainer view via the whiteboard.
    // Actually, let's just push ClassWhiteboardScreen — the trainer view
    // is accessible from within it via the "Trainer View" button.
    return ClassWhiteboardScreen(gymClass: gymClass, gymId: gymClass.gymId);
  }
}
