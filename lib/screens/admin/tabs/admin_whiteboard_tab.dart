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
  const AdminWhiteboardTab({super.key, required this.gymId});
  final String gymId;

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

  late final ClassService _classService = ClassService(gymId: widget.gymId);
  late final WodService _wodService = WodService(gymId: widget.gymId);
  late final BookingService _bookingService =
      BookingService(gymId: widget.gymId);

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

          // Auto-select first class if none selected
          if (_selectedClass == null && dayClasses.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedClass == null && dayClasses.isNotEmpty) {
                setState(() => _selectedClass = dayClasses.first);
              }
            });
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top header ──────────────────────────────────────────────
              _buildTopBar(dateFmt, isToday, dayClasses),
              // ── Section headers row ─────────────────────────────────────
              if (_selectedClass != null)
                _buildSectionHeaders(_selectedClass!),
              // ── Main content ─────────────────────────────────────────────
              Expanded(
                child: _selectedClass == null
                    ? _buildNoSelection(dayClasses.isEmpty)
                    : _buildWhiteboardContent(_selectedClass!),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Top bar: date + class selector ───────────────────────────────────────

  Widget _buildTopBar(
      DateFormat dateFmt, bool isToday, List<GymClass> dayClasses) {
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
                  _selectedDate =
                      _selectedDate.add(const Duration(days: 1));
                  _selectedClass = null;
                }),
              ),
              const SizedBox(width: 16),
              // Class dropdown
              Expanded(
                child: _ClassDropdown(
                  classes: dayClasses,
                  selected: _selectedClass,
                  onChanged: (c) => setState(() {
                    _selectedClass = c;
                    _loadingMap.clear();
                  }),
                  timeLabel: _timeLabel,
                ),
              ),
              const SizedBox(width: 12),
              // Add Bookings button
              if (_selectedClass != null)
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
                _selectedDate =
                    _selectedDate.subtract(const Duration(days: 1));
                _selectedClass = null;
              }),
              onNext: () => setState(() {
                _selectedDate = _selectedDate.add(const Duration(days: 1));
                _selectedClass = null;
              }),
            ),
            const SizedBox(height: 8),
            _ClassDropdown(
              classes: dayClasses,
              selected: _selectedClass,
              onChanged: (c) => setState(() {
                _selectedClass = c;
                _loadingMap.clear();
              }),
              timeLabel: _timeLabel,
            ),
          ],
        );
      }),
    );
  }

  // ── Section header row: "Workout" | "Whiteboard" ─────────────────────────

  Widget _buildSectionHeaders(GymClass gymClass) {
    return StreamBuilder<List<Booking>>(
      stream: _bookingService.streamBookingsForClass(gymClass.id),
      builder: (context, snap) {
        final bookings = snap.data ?? [];
        final checkedIn = bookings.where((b) => b.checkedIn).length;
        final pending = bookings.where((b) => !b.checkedIn).toList();

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
                // Left: Workout label
                SizedBox(
                  width: constraints.maxWidth * 0.40,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: const Text(
                      'Workout',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                // Right: Whiteboard label + stats + Check In All
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        const Text(
                          'Whiteboard',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$checkedIn / ${bookings.length}',
                            style: const TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        const Spacer(),
                        // Default Sorting label
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort_outlined,
                                size: 14, color: _textSub),
                            const SizedBox(width: 4),
                            Text(
                              context.l10n.tr('Default Sorting'),
                              style: const TextStyle(
                                  color: _textSub, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        // Check In All
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
                                  horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(7)),
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
                        gymClass: gymClass,
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
                          gymClass: gymClass,
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
            child: const Icon(Icons.dashboard_outlined,
                size: 36, color: _accent),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  child: const Icon(Icons.close,
                      size: 10, color: _textSub),
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
// _ClassDropdown
// ─────────────────────────────────────────────────────────────────────────────

class _ClassDropdown extends StatelessWidget {
  const _ClassDropdown({
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

  @override
  Widget build(BuildContext context) {
    if (classes.isEmpty) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2920),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<GymClass>(
          value: selected,
          dropdownColor: const Color(0xFF112820),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: _textSub, size: 18),
          hint: const Text('Select class',
              style: TextStyle(color: _textSub, fontSize: 13)),
          isExpanded: true,
          items: classes.map((c) {
            return DropdownMenuItem<GymClass>(
              value: c,
              child: Text(
                timeLabel(c),
                style: const TextStyle(
                    color: Colors.white, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
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
      decoration:
          const BoxDecoration(border: Border(right: BorderSide(color: _border))),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (wod!.warmUp.isNotEmpty) ...[
          _WbLabel('Warm Up:'),
          _WbText(wod!.warmUp),
          const SizedBox(height: 14),
        ],
        if (wod!.parts.isNotEmpty)
          ...wod!.parts.asMap().entries.map((e) => _WbPart(e.value, e.key))
        else ...[
          if (wod!.format.isNotEmpty)
            Text(wod!.format,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
          if (wod!.description.isNotEmpty) _WbText(wod!.description),
          ...wod!.exercises.map((ex) => _WbExercise(ex)),
        ],
        if (wod!.coolDown.isNotEmpty) ...[
          const SizedBox(height: 14),
          _WbLabel('Cool Down:'),
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
        padding: const EdgeInsets.only(top: 4, bottom: 3),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );
}

class _WbText extends StatelessWidget {
  const _WbText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Color(0xFFD1FAE5), fontSize: 13, height: 1.55));
}

class _WbPart extends StatelessWidget {
  const _WbPart(this.part, this.index);
  final WodPart part;
  final int index;

  static const _accent = _AdminWhiteboardTabState._accent;
  static const _textSub = _AdminWhiteboardTabState._textSub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(
              'Part ${String.fromCharCode(65 + index)}: ',
              style: const TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800),
            ),
            Expanded(
              child: Text(
                part.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          if (part.timeCap.isNotEmpty)
            Text(part.timeCap,
                style: const TextStyle(color: _textSub, fontSize: 11)),
          if (part.description.isNotEmpty) _WbText(part.description),
          ...part.exercises.map((ex) => _WbExercise(ex)),
        ],
      ),
    );
  }
}

class _WbExercise extends StatelessWidget {
  const _WbExercise(this.ex);
  final WodExercise ex;

  static const _accent = _AdminWhiteboardTabState._accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('• ', style: const TextStyle(color: _accent, fontSize: 13)),
          Expanded(
            child: Text(
              '${ex.name}${ex.shortLabel.isNotEmpty ? '  ${ex.shortLabel}' : ''}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _InlineMemberPanel — table-style member roster
// ─────────────────────────────────────────────────────────────────────────────

class _InlineMemberPanel extends StatelessWidget {
  const _InlineMemberPanel({
    required this.bookings,
    required this.gymClass,
    required this.loadingMap,
    required this.onToggle,
  });

  final List<Booking> bookings;
  final GymClass gymClass;
  final Map<String, bool> loadingMap;
  final Future<void> Function(Booking) onToggle;

  static const _border = _AdminWhiteboardTabState._border;
  static const _textSub = _AdminWhiteboardTabState._textSub;

  @override
  Widget build(BuildContext context) {
    final sorted = [...bookings]
      ..sort((a, b) {
        if (a.checkedIn == b.checkedIn) return 0;
        return a.checkedIn ? 1 : -1;
      });

    final timeFmt = DateFormat('HH:mm');
    final classLabel =
        '${gymClass.title} (${timeFmt.format(gymClass.startTime)} - ${timeFmt.format(gymClass.endTime)})';

    return Column(
      children: [
        // Column headers
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 28), // info icon space
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
                width: 90,
                child: Text('Attendance',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textSub,
                        letterSpacing: 0.5),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(width: 32), // ⋮ menu space
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
                  const Icon(Icons.group_off_outlined,
                      color: Colors.white12, size: 40),
                  const SizedBox(height: 10),
                  const Text('No bookings yet',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: sorted.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _border),
              itemBuilder: (_, i) => _InlineMemberRow(
                booking: sorted[i],
                classLabel: classLabel,
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
    required this.isLoading,
    required this.onTap,
  });

  final Booking booking;
  final String classLabel;
  final bool isLoading;
  final VoidCallback onTap;

  static const _checked = Color(0xFF16A34A);
  static const _pending = Color(0xFFD97706);
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

    return Container(
      color: checked
          ? const Color(0xFF14532D).withValues(alpha: 0.10)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Info icon
          Icon(Icons.info_outline, size: 16, color: Colors.white24),
          const SizedBox(width: 8),
          // Avatar + name
          Expanded(
            flex: 5,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      statusColor.withValues(alpha: 0.18),
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
          // Class
          Expanded(
            flex: 5,
            child: Text(classLabel,
                style:
                    const TextStyle(color: _textSub, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          // Results — Log Result link
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
          // Attendance toggle
          SizedBox(
            width: 90,
            child: isLoading
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white38)),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: onTap,
                        child: Icon(
                          checked
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          color: checked ? _checked : Colors.white24,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        checked
                            ? Icons.visibility
                            : Icons.visibility_off_outlined,
                        color: checked ? Colors.white24 : _textSub,
                        size: 18,
                      ),
                    ],
                  ),
          ),
          // ⋮ menu
          SizedBox(
            width: 32,
            child: Icon(Icons.more_vert, color: Colors.white24, size: 18),
          ),
        ],
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
