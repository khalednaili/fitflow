import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/gym_class.dart';
import '../../models/personal_training.dart';
import '../../services/personal_training_service.dart';
import '../../services/class_service.dart';
import 'class_detail_screen.dart';
import 'tabs/admin_classes_tab.dart';
import '../../l10n/app_localizations.dart';

enum _CalendarViewMode { day, week, month }

enum _CapacityFilter { all, available, full }

class AdminCalendarScreen extends StatefulWidget {
  const AdminCalendarScreen({
    super.key,
    required this.gymId,
    this.readOnly = false,
    this.ptCoachId,
  });

  final String gymId;

  /// When true the calendar is view-only: time-slot taps are ignored and
  /// class taps show a read-only detail sheet instead of edit/delete actions.
  final bool readOnly;

  /// When set, PT sessions for this coach are overlaid on the calendar.
  final String? ptCoachId;

  @override
  State<AdminCalendarScreen> createState() => _AdminCalendarScreenState();
}

class _AdminCalendarScreenState extends State<AdminCalendarScreen> {
  late final ClassService _classService = ClassService(gymId: widget.gymId);
  late final PersonalTrainingService _ptService =
      PersonalTrainingService(gymId: widget.gymId);

  _CalendarViewMode _viewMode = _CalendarViewMode.week;
  DateTime _anchorDate = DateTime.now();
  bool _compactDensity = false;
  String _filterQuery = '';
  String? _filterCoach;
  _CapacityFilter _capacityFilter = _CapacityFilter.all;

  List<GymClass> _applyFilters(List<GymClass> classes) {
    return classes.where((c) {
      if (_filterQuery.isNotEmpty &&
          !c.title.toLowerCase().contains(_filterQuery.toLowerCase())) {
        return false;
      }
      if (_filterCoach != null &&
          !c.coachNames.any((n) => n == _filterCoach) &&
          c.coachName != _filterCoach) {
        return false;
      }
      if (_capacityFilter == _CapacityFilter.full && !c.isFull) return false;
      if (_capacityFilter == _CapacityFilter.available && c.isFull) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showClassEditorDialog(
                context,
                gymId: widget.gymId,
              ),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.tr('New Class')),
            ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _CalendarHeader(
              viewMode: _viewMode,
              anchorDate: _anchorDate,
              locale: locale,
              compactDensity: _compactDensity,
              onViewModeChanged: (mode) => setState(() => _viewMode = mode),
              onPrevious: _goToPrevious,
              onNext: _goToNext,
              onToday: _goToToday,
              onJumpToDate: _jumpToDate,
              onCompactDensityChanged: () {
                setState(() => _compactDensity = !_compactDensity);
              },
            ),
            Expanded(
              child: StreamBuilder<List<GymClass>>(
                stream: _classService.streamAllClasses(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Error loading classes:\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    );
                  }

                  final classes = snapshot.data ?? const <GymClass>[];
                  final filteredClasses = _applyFilters(classes);
                  final coachNames = (classes
                      .expand((c) => c.coachNames.isNotEmpty
                          ? c.coachNames
                          : [c.coachName])
                      .where((n) => n.trim().isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort());

                  return Column(
                    children: [
                      if (!widget.readOnly)
                        _FilterBar(
                          filterQuery: _filterQuery,
                          filterCoach: _filterCoach,
                          capacityFilter: _capacityFilter,
                          coaches: coachNames,
                          onQueryChanged: (v) =>
                              setState(() => _filterQuery = v),
                          onCoachChanged: (v) =>
                              setState(() => _filterCoach = v),
                          onCapacityFilterChanged: (v) =>
                              setState(() => _capacityFilter = v),
                          onClearAll: () => setState(() {
                            _filterQuery = '';
                            _filterCoach = null;
                            _capacityFilter = _CapacityFilter.all;
                          }),
                        ),
                      Expanded(
                        child: StreamBuilder<List<PersonalTraining>>(
                          stream: widget.ptCoachId != null
                              ? _ptService.streamForCoach(widget.ptCoachId!)
                              : const Stream.empty(),
                          builder: (context, ptSnap) {
                            final ptSessions =
                                ptSnap.data ?? const <PersonalTraining>[];

                            if (_viewMode == _CalendarViewMode.month) {
                              return _MonthGrid(
                                anchorDate: _anchorDate,
                                classes: filteredClasses,
                                locale: locale,
                                onClassTap: _onClassTap,
                                onDayTap: _onDayTap,
                              );
                            }

                            if (_viewMode == _CalendarViewMode.day) {
                              return _DayAgenda(
                                classes: _classesForDay(
                                    filteredClasses, _anchorDate),
                                ptSessions: _ptForDay(ptSessions, _anchorDate),
                                selectedDay: _anchorDate,
                                locale: locale,
                                compactDensity: _compactDensity,
                                onClassTap: _onClassTap,
                                onTimeSlotTap: _onTimeSlotTap,
                              );
                            }

                            final weekStart = _startOfWeek(_anchorDate);
                            final weekDays = List<DateTime>.generate(
                              7,
                              (index) => weekStart.add(Duration(days: index)),
                              growable: false,
                            );

                            return _WeekAgenda(
                              classes: filteredClasses,
                              ptSessions: ptSessions,
                              weekDays: weekDays,
                              locale: locale,
                              compactDensity: _compactDensity,
                              onClassTap: _onClassTap,
                              onTimeSlotTap: _onTimeSlotTap,
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToPrevious() {
    setState(() {
      if (_viewMode == _CalendarViewMode.month) {
        _anchorDate = DateTime(_anchorDate.year, _anchorDate.month - 1, 1);
      } else if (_viewMode == _CalendarViewMode.day) {
        _anchorDate = _anchorDate.subtract(const Duration(days: 1));
      } else {
        _anchorDate = _anchorDate.subtract(const Duration(days: 7));
      }
    });
  }

  void _goToNext() {
    setState(() {
      if (_viewMode == _CalendarViewMode.month) {
        _anchorDate = DateTime(_anchorDate.year, _anchorDate.month + 1, 1);
      } else if (_viewMode == _CalendarViewMode.day) {
        _anchorDate = _anchorDate.add(const Duration(days: 1));
      } else {
        _anchorDate = _anchorDate.add(const Duration(days: 7));
      }
    });
  }

  void _onDayTap(DateTime day) {
    setState(() {
      _anchorDate = day;
      _viewMode = _CalendarViewMode.day;
    });
  }

  void _goToToday() {
    setState(() => _anchorDate = DateTime.now());
  }

  Future<void> _jumpToDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      initialDate: _anchorDate,
      helpText: context.l10n.tr('Jump to date'),
    );

    if (picked == null) {
      return;
    }

    setState(() => _anchorDate = picked);
  }

  Future<void> _onClassTap(GymClass gymClass) async {
    await _showClassDetailSheet(gymClass);

    // Admin edit/delete are handled inside the sheet via returned action.
  }

  Future<void> _onTimeSlotTap(DateTime slotStart) async {
    if (widget.readOnly) return;
    await showClassEditorDialog(
      context,
      gymId: widget.gymId,
      initialStartDateTime: slotStart,
      initialEndDateTime: slotStart.add(const Duration(hours: 1)),
    );
  }

  Future<void> _showClassDetailSheet(GymClass gymClass) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ClassDetailScreen(
        gymClass: gymClass,
        gymId: widget.gymId,
        readOnly: widget.readOnly,
      ),
    ));
  }

  List<GymClass> _classesForDay(List<GymClass> classes, DateTime day) {
    return classes
        .where((item) => _isSameDay(item.startTime, day))
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  List<PersonalTraining> _ptForDay(
      List<PersonalTraining> sessions, DateTime day) {
    return sessions
        .where((s) => _isSameDay(s.startTime, day))
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  DateTime _startOfWeek(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.viewMode,
    required this.anchorDate,
    required this.locale,
    required this.compactDensity,
    required this.onViewModeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onJumpToDate,
    required this.onCompactDensityChanged,
  });

  final _CalendarViewMode viewMode;
  final DateTime anchorDate;
  final String locale;
  final bool compactDensity;
  final ValueChanged<_CalendarViewMode> onViewModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onJumpToDate;
  final VoidCallback onCompactDensityChanged;

  @override
  Widget build(BuildContext context) {
    final weekStart = _startOfWeek(anchorDate);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final rangeLabel = switch (viewMode) {
      _CalendarViewMode.month =>
        DateFormat('MMMM y', locale).format(anchorDate),
      _CalendarViewMode.day =>
        DateFormat('EEEE, d MMMM', locale).format(anchorDate),
      _CalendarViewMode.week =>
        '${DateFormat('d MMM', locale).format(weekStart)} - ${DateFormat('d MMM', locale).format(weekEnd)}',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SegmentedButton<_CalendarViewMode>(
                segments: <ButtonSegment<_CalendarViewMode>>[
                  ButtonSegment<_CalendarViewMode>(
                    value: _CalendarViewMode.day,
                    label: Text(context.l10n.tr('Day')),
                    icon: const Icon(Icons.view_day_outlined, size: 16),
                  ),
                  ButtonSegment<_CalendarViewMode>(
                    value: _CalendarViewMode.week,
                    label: Text(context.l10n.tr('Week')),
                    icon: const Icon(Icons.view_week_outlined, size: 16),
                  ),
                  ButtonSegment<_CalendarViewMode>(
                    value: _CalendarViewMode.month,
                    label: Text(context.l10n.tr('Month')),
                    icon: const Icon(Icons.calendar_month_outlined, size: 16),
                  ),
                ],
                selected: <_CalendarViewMode>{viewMode},
                onSelectionChanged: (Set<_CalendarViewMode> s) {
                  if (s.isNotEmpty) onViewModeChanged(s.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Spacer(),
              if (viewMode != _CalendarViewMode.month)
                Tooltip(
                  message:
                      context.l10n.tr(compactDensity ? 'Switch to comfort' : 'Switch to compact'),
                  child: IconButton(
                    onPressed: onCompactDensityChanged,
                    icon: Icon(
                      compactDensity ? Icons.density_medium : Icons.density_small,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              IconButton(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  rangeLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton.icon(
                onPressed: onToday,
                icon: const Icon(Icons.today, size: 16),
                label: Text(context.l10n.tr('Today')),
              ),
              IconButton(
                tooltip: context.l10n.tr('Jump to date'),
                onPressed: onJumpToDate,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DateTime _startOfWeek(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }
}

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.classes,
    required this.ptSessions,
    required this.selectedDay,
    required this.locale,
    required this.compactDensity,
    required this.onClassTap,
    required this.onTimeSlotTap,
  });

  final List<GymClass> classes;
  final List<PersonalTraining> ptSessions;
  final DateTime selectedDay;
  final String locale;
  final bool compactDensity;
  final ValueChanged<GymClass> onClassTap;
  final ValueChanged<DateTime> onTimeSlotTap;

  @override
  Widget build(BuildContext context) {
    final hourHeight = compactDensity ? 44.0 : 54.0;
    final sortedClasses = [...classes]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final sortedPt = [...ptSessions]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final conflicts = _findCoachConflicts(classes);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _DayHeader(
                day: selectedDay,
                locale: locale,
                count: classes.length,
                ptCount: ptSessions.length,
              ),
            ),
          ),
        ),
        if (_isSameDay(selectedDay, DateTime.now()))
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _CurrentTimeIndicator(locale: locale),
          ),
        // ── Compact agenda list (classes + PT sorted by time) ────────────
        if (sortedClasses.isNotEmpty || sortedPt.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Text(
                      context.l10n.tr('Schedule'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  ...sortedClasses.map((gc) => _ClassListCard(
                        gymClass: gc,
                        compactDensity: compactDensity,
                        onTap: () => onClassTap(gc),
                        hasConflict: conflicts.contains(gc.id),
                      )),
                  ...sortedPt.map((pt) => _PtListCard(
                        pt: pt,
                        compactDensity: compactDensity,
                      )),
                ],
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(compactDensity ? 8 : 10),
                child: _TimelineDayColumn(
                  day: selectedDay,
                  classes: classes,
                  ptSessions: ptSessions,
                  compactDensity: compactDensity,
                  hourHeight: hourHeight,
                  onClassTap: onClassTap,
                  onSlotTap: onTimeSlotTap,
                  showNowIndicator: _isSameDay(selectedDay, DateTime.now()),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _CurrentTimeIndicator extends StatefulWidget {
  const _CurrentTimeIndicator({required this.locale});

  final String locale;

  @override
  State<_CurrentTimeIndicator> createState() => _CurrentTimeIndicatorState();
}

class _CurrentTimeIndicatorState extends State<_CurrentTimeIndicator> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nowLabel = DateFormat('HH:mm', widget.locale).format(_now);

    return Row(
      children: <Widget>[
        const Expanded(child: Divider()),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${context.l10n.tr('Now')} $nowLabel',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Week agenda — fully synchronized scroll
//
// Layout:
//   ┌──────────┬──────────────────────────────────────────┐
//   │  corner  │  day headers  (sticky, horizontal-sync)  │
//   ├──────────┼──────────────────────────────────────────┤
//   │   time   │                                          │
//   │  gutter  │   7-column event grid                    │
//   │ (sticky, │   • vertical scroll synced to gutter     │
//   │  v-sync) │   • horizontal scroll to reveal all days │
//   └──────────┴──────────────────────────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────

class _WeekAgenda extends StatefulWidget {
  const _WeekAgenda({
    required this.classes,
    required this.ptSessions,
    required this.weekDays,
    required this.locale,
    required this.compactDensity,
    required this.onClassTap,
    required this.onTimeSlotTap,
  });

  final List<GymClass> classes;
  final List<PersonalTraining> ptSessions;
  final List<DateTime> weekDays;
  final String locale;
  final bool compactDensity;
  final ValueChanged<GymClass> onClassTap;
  final ValueChanged<DateTime> onTimeSlotTap;

  @override
  State<_WeekAgenda> createState() => _WeekAgendaState();
}

class _WeekAgendaState extends State<_WeekAgenda> {
  // Main scroll axes
  late final ScrollController _vCtrl; // user scrolls this vertically
  late final ScrollController _gutterCtrl; // time-gutter mirrors _vCtrl
  late final ScrollController _hCtrl; // user scrolls this horizontally
  late final ScrollController _headerCtrl; // day-headers mirror _hCtrl

  // ── layout constants ───────────────────────────────────────────────────────
  double get _hourH => widget.compactDensity ? 48.0 : 58.0;
  double get _dayW => widget.compactDensity ? 200.0 : 240.0;
  double get _gutterW => widget.compactDensity ? 42.0 : 48.0;
  double get _headerH => widget.compactDensity ? 56.0 : 64.0;
  double get _gridH => 24 * _hourH;
  double get _gridW => 7 * _dayW;

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _vCtrl = ScrollController();
    _gutterCtrl = ScrollController();
    _hCtrl = ScrollController();
    _headerCtrl = ScrollController();

    _vCtrl.addListener(_syncGutter);
    _hCtrl.addListener(_syncHeader);

    // Auto-scroll to current hour after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  void _syncGutter() {
    if (!_gutterCtrl.hasClients) return;
    final o = _vCtrl.offset;
    if ((_gutterCtrl.offset - o).abs() > 0.5) _gutterCtrl.jumpTo(o);
  }

  void _syncHeader() {
    if (!_headerCtrl.hasClients) return;
    final o = _hCtrl.offset;
    if ((_headerCtrl.offset - o).abs() > 0.5) _headerCtrl.jumpTo(o);
  }

  void _scrollToNow() {
    if (!_vCtrl.hasClients) return;
    final now = DateTime.now();
    final target = ((now.hour * 60 + now.minute) / 60 * _hourH - 160)
        .clamp(0.0, double.maxFinite);
    _vCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _vCtrl.removeListener(_syncGutter);
    _hCtrl.removeListener(_syncHeader);
    _vCtrl.dispose();
    _gutterCtrl.dispose();
    _hCtrl.dispose();
    _headerCtrl.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  int get _todayIndex {
    final now = DateTime.now();
    for (var i = 0; i < widget.weekDays.length; i++) {
      final d = widget.weekDays[i];
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return i;
      }
    }
    return -1;
  }

  List<GymClass> _classesForDay(DateTime day) => widget.classes
      .where((c) =>
          c.startTime.year == day.year &&
          c.startTime.month == day.month &&
          c.startTime.day == day.day)
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  List<PersonalTraining> _ptForDay(DateTime day) => widget.ptSessions
      .where((s) =>
          s.startTime.year == day.year &&
          s.startTime.month == day.month &&
          s.startTime.day == day.day)
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = theme.colorScheme.outlineVariant.withValues(alpha: 0.35);
    final todayIdx = _todayIndex;
    final now = DateTime.now();

    return Column(
      children: [
        // ── Sticky header row ──────────────────────────────────────────────
        SizedBox(
          height: _headerH,
          child: Row(
            children: [
              // corner placeholder aligned with gutter
              Container(
                width: _gutterW,
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: divider),
                    bottom: BorderSide(color: divider),
                  ),
                ),
              ),
              // day headers — mirrored horizontal scroll
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: divider)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _headerCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: _gridW,
                      child: Row(
                        children: List.generate(7, (d) {
                          final day = widget.weekDays[d];
                          final count = _classesForDay(day).length;
                          final ptCount = _ptForDay(day).length;
                          final isToday = d == todayIdx;
                          return _WeekDayHeader(
                            width: _dayW,
                            day: day,
                            locale: widget.locale,
                            count: count,
                            ptCount: ptCount,
                            isToday: isToday,
                            compact: widget.compactDensity,
                            dividerColor: divider,
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Content (gutter + grid) ────────────────────────────────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time gutter — sticky left, vertical-synced
              Container(
                width: _gutterW,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: divider)),
                ),
                child: SingleChildScrollView(
                  controller: _gutterCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    height: _gridH,
                    child: Column(
                      children: List.generate(24, (h) {
                        return SizedBox(
                          height: _hourH,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6, top: 2),
                            child: Text(
                              '${h.toString().padLeft(2, '0')}:00',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: widget.compactDensity ? 9 : 10,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),

              // Event grid — scrolls horizontally AND vertically (in sync)
              Expanded(
                child: ClipRect(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _hCtrl,
                    child: SizedBox(
                      width: _gridW,
                      child: SingleChildScrollView(
                        controller: _vCtrl,
                        child: SizedBox(
                          height: _gridH,
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              // Hour grid lines
                              ..._buildGridLines(divider),
                              // Day column backgrounds + right borders
                              ..._buildDayBands(theme, todayIdx, divider),
                              // Tappable hour slots
                              ..._buildSlotAreas(),
                              // Class + PT event cards
                              ..._buildEventCards(),
                              // "Now" indicator line
                              if (todayIdx >= 0)
                                _buildNowLine(todayIdx, now, theme),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── stack layer builders ───────────────────────────────────────────────────

  List<Widget> _buildGridLines(Color divider) {
    return List.generate(
        24,
        (h) => Positioned(
              left: 0,
              right: 0,
              top: h * _hourH,
              height: _hourH,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: divider, width: 0.5)),
                ),
              ),
            ));
  }

  List<Widget> _buildDayBands(ThemeData theme, int todayIdx, Color divider) {
    return List.generate(
        7,
        (d) => Positioned(
              left: d * _dayW,
              width: _dayW,
              top: 0,
              height: _gridH,
              child: Container(
                decoration: BoxDecoration(
                  color: d == todayIdx
                      ? theme.colorScheme.primary.withValues(alpha: 0.04)
                      : null,
                  border: Border(right: BorderSide(color: divider, width: 0.5)),
                ),
              ),
            ));
  }

  List<Widget> _buildSlotAreas() {
    final slots = <Widget>[];
    for (var d = 0; d < 7; d++) {
      final day = widget.weekDays[d];
      for (var h = 0; h < 24; h++) {
        final slotStart = DateTime(day.year, day.month, day.day, h);
        slots.add(Positioned(
          left: d * _dayW,
          width: _dayW,
          top: h * _hourH,
          height: _hourH,
          child: InkWell(onTap: () => widget.onTimeSlotTap(slotStart)),
        ));
      }
    }
    return slots;
  }

  List<Widget> _buildEventCards() {
    final events = <Widget>[];
    for (var d = 0; d < 7; d++) {
      final day = widget.weekDays[d];
      final dayClasses = _classesForDay(day);
      final dayPt = _ptForDay(day);
      final conflicts = _findCoachConflicts(dayClasses);
      final layout = _computeOverlapLayout(dayClasses);
      final availW = _dayW - 4;

      // Class cards
      for (final item in layout) {
        final gc = item.gymClass;
        final startMins = gc.startTime.hour * 60 + gc.startTime.minute;
        final durMins = gc.endTime.difference(gc.startTime).inMinutes;
        final top = startMins / 60 * _hourH + 1;
        final height = ((durMins <= 0 ? 30 : durMins) / 60 * _hourH - 2)
            .clamp(widget.compactDensity ? 24.0 : 30.0, double.infinity);
        final colW = availW / item.totalCols;
        final left = d * _dayW + 2 + item.col * colW;

        events.add(Positioned(
          left: left,
          width: colW - 2,
          top: top,
          height: height,
          child: _TimelineEventCard(
            gymClass: gc,
            compactDensity: widget.compactDensity,
            onTap: () => widget.onClassTap(gc),
            hasConflict: conflicts.contains(gc.id),
          ),
        ));
      }

      // PT session cards (rightmost 40 % of the day column)
      if (dayPt.isNotEmpty) {
        final ptW = (availW * 0.42).clamp(60.0, double.infinity);
        final ptOff = d * _dayW + 2 + availW - ptW;
        for (final pt in dayPt) {
          final startMins = pt.startTime.hour * 60 + pt.startTime.minute;
          final durMins = pt.endTime.difference(pt.startTime).inMinutes;
          final top = startMins / 60 * _hourH + 1;
          final height = ((durMins <= 0 ? 30 : durMins) / 60 * _hourH - 2)
              .clamp(widget.compactDensity ? 24.0 : 30.0, double.infinity);
          events.add(Positioned(
            left: ptOff,
            width: ptW - 2,
            top: top,
            height: height,
            child:
                _PtTimelineCard(pt: pt, compactDensity: widget.compactDensity),
          ));
        }
      }
    }
    return events;
  }

  Widget _buildNowLine(int todayIdx, DateTime now, ThemeData theme) {
    final top = (now.hour * 60 + now.minute) / 60 * _hourH;
    return Positioned(
      left: todayIdx * _dayW,
      right: 0,
      top: top - 4,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(height: 2, color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

// ── Week day header chip ───────────────────────────────────────────────────────

class _WeekDayHeader extends StatelessWidget {
  const _WeekDayHeader({
    required this.width,
    required this.day,
    required this.locale,
    required this.count,
    required this.ptCount,
    required this.isToday,
    required this.compact,
    required this.dividerColor,
  });

  final double width;
  final DateTime day;
  final String locale;
  final int count;
  final int ptCount;
  final bool isToday;
  final bool compact;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color:
            isToday ? theme.colorScheme.primary.withValues(alpha: 0.07) : null,
        border: Border(right: BorderSide(color: dividerColor, width: 0.5)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Day number + name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('EEE', locale).format(day).toUpperCase(),
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: isToday
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  DateFormat('d', locale).format(day),
                  style: TextStyle(
                    fontSize: compact ? 15 : 18,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    color: isToday
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          // Badge column
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Class count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: count > 0
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: count > 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (ptCount > 0) ...[
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.l10n.tr('PT'),
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlap layout helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns a Set of class IDs that have a coach conflict with at least one
/// other class in the list (overlapping time AND shared coach).
Set<String> _findCoachConflicts(List<GymClass> classes) {
  final conflicts = <String>{};
  for (var i = 0; i < classes.length; i++) {
    for (var j = i + 1; j < classes.length; j++) {
      final a = classes[i];
      final b = classes[j];
      final overlaps =
          a.startTime.isBefore(b.endTime) && a.endTime.isAfter(b.startTime);
      if (!overlaps) continue;
      final aCoaches = <String>{...a.coachIds, a.coachName.trim()}
          .where((s) => s.isNotEmpty);
      final bCoaches = <String>{...b.coachIds, b.coachName.trim()}
          .where((s) => s.isNotEmpty);
      final aNames = <String>{...a.coachNames, a.coachName.trim()}
          .where((s) => s.isNotEmpty);
      final bNames = <String>{...b.coachNames, b.coachName.trim()}
          .where((s) => s.isNotEmpty);
      final hasSharedCoach = aCoaches.any(bCoaches.toSet().contains) ||
          aNames.any(bNames.toSet().contains);
      if (hasSharedCoach) {
        conflicts.add(a.id);
        conflicts.add(b.id);
      }
    }
  }
  return conflicts;
}

/// Assigns each class a column index and the total number of columns in its
/// overlap cluster, so they can be rendered side-by-side.
List<_EventLayout> _computeOverlapLayout(List<GymClass> classes) {
  if (classes.isEmpty) return [];

  // Sort by start time, then by end time descending so longer events get
  // earlier columns.
  final sorted = [...classes]..sort((a, b) {
      final s = a.startTime.compareTo(b.startTime);
      return s != 0 ? s : b.endTime.compareTo(a.endTime);
    });

  // Assign each event to the first column whose last-end-time ≤ event start.
  final colEnds = <DateTime>[]; // last end-time per column
  final colIndex = <int>[];

  for (final gc in sorted) {
    int assigned = -1;
    for (var ci = 0; ci < colEnds.length; ci++) {
      if (!gc.startTime.isBefore(colEnds[ci])) {
        assigned = ci;
        colEnds[ci] = gc.endTime;
        break;
      }
    }
    if (assigned == -1) {
      assigned = colEnds.length;
      colEnds.add(gc.endTime);
    }
    colIndex.add(assigned);
  }

  // For each event compute the total columns in its overlap cluster: the max
  // column index among all events that overlap with it, plus 1.
  final totalCols = <int>[];
  for (var i = 0; i < sorted.length; i++) {
    final gc = sorted[i];
    var maxCol = colIndex[i];
    for (var j = 0; j < sorted.length; j++) {
      if (i == j) continue;
      final other = sorted[j];
      final overlaps = other.startTime.isBefore(gc.endTime) &&
          other.endTime.isAfter(gc.startTime);
      if (overlaps && colIndex[j] > maxCol) maxCol = colIndex[j];
    }
    totalCols.add(maxCol + 1);
  }

  return List.generate(
    sorted.length,
    (i) => _EventLayout(
        gymClass: sorted[i], col: colIndex[i], totalCols: totalCols[i]),
  );
}

class _EventLayout {
  const _EventLayout(
      {required this.gymClass, required this.col, required this.totalCols});
  final GymClass gymClass;
  final int col;
  final int totalCols;
}

// ─────────────────────────────────────────────────────────────────────────────

class _TimelineDayColumn extends StatelessWidget {
  const _TimelineDayColumn({
    required this.day,
    required this.classes,
    this.ptSessions = const [],
    required this.compactDensity,
    required this.hourHeight,
    required this.onClassTap,
    required this.onSlotTap,
    this.showNowIndicator = false,
  });

  final DateTime day;
  final List<GymClass> classes;
  final List<PersonalTraining> ptSessions;
  final bool compactDensity;
  final double hourHeight;
  final ValueChanged<GymClass> onClassTap;
  final ValueChanged<DateTime> onSlotTap;
  final bool showNowIndicator;

  @override
  Widget build(BuildContext context) {
    final timelineHeight = 24 * hourHeight;
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final timeColWidth = compactDensity ? 36.0 : 40.0;
    final layout = _computeOverlapLayout(classes);
    final conflicts = _findCoachConflicts(classes);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Available width for event cards (after the time label column + gap).
        final eventsWidth = (constraints.maxWidth - timeColWidth - 4)
            .clamp(60.0, double.infinity);

        return SingleChildScrollView(
          child: SizedBox(
            height: timelineHeight,
            child: Stack(
              children: <Widget>[
                // ── Hour grid ──────────────────────────────────────────
                Column(
                  children: List<Widget>.generate(24, (hour) {
                    final slotStart =
                        DateTime(day.year, day.month, day.day, hour);
                    return SizedBox(
                      height: hourHeight,
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: timeColWidth,
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00',
                              style: TextStyle(
                                fontSize: compactDensity ? 10 : 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => onSlotTap(slotStart),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),

                // ── Event cards (side-by-side when overlapping) ────────
                ...layout.map((item) {
                  final gc = item.gymClass;
                  final startMinutes =
                      gc.startTime.hour * 60 + gc.startTime.minute;
                  final durationMinutes =
                      gc.endTime.difference(gc.startTime).inMinutes;
                  final top = startMinutes / 60 * hourHeight;
                  final height =
                      ((durationMinutes <= 0 ? 30 : durationMinutes) /
                              60 *
                              hourHeight)
                          .clamp(compactDensity ? 26.0 : 34.0, double.infinity);

                  // Divide available width equally among overlapping columns.
                  final colWidth = eventsWidth / item.totalCols;
                  final left = timeColWidth + 2 + item.col * colWidth;

                  return Positioned(
                    left: left,
                    width: colWidth - 2,
                    top: top + 2,
                    height: height,
                    child: _TimelineEventCard(
                      gymClass: gc,
                      compactDensity: compactDensity,
                      onTap: () => onClassTap(gc),
                      hasConflict: conflicts.contains(gc.id),
                    ),
                  );
                }),

                // ── PT session blocks ──────────────────────────────────
                ...ptSessions.map((pt) {
                  final startMins =
                      pt.startTime.hour * 60 + pt.startTime.minute;
                  final durMins = pt.endTime.difference(pt.startTime).inMinutes;
                  final top = startMins / 60 * hourHeight;
                  final height =
                      ((durMins <= 0 ? 30 : durMins) / 60 * hourHeight)
                          .clamp(compactDensity ? 26.0 : 34.0, double.infinity);
                  // PT events sit in the rightmost 40% of the column.
                  final ptWidth = eventsWidth * 0.42;
                  final ptLeft = timeColWidth + 2 + eventsWidth - ptWidth;

                  return Positioned(
                    left: ptLeft,
                    width: ptWidth - 2,
                    top: top + 2,
                    height: height,
                    child: _PtTimelineCard(
                      pt: pt,
                      compactDensity: compactDensity,
                    ),
                  );
                }),

                // ── "Now" indicator line ───────────────────────────────
                if (showNowIndicator && isToday)
                  Positioned(
                    left: timeColWidth,
                    right: 0,
                    top: ((now.hour * 60 + now.minute) / 60 * hourHeight),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TimelineEventCard extends StatelessWidget {
  const _TimelineEventCard({
    required this.gymClass,
    required this.compactDensity,
    required this.onTap,
    this.hasConflict = false,
  });

  final GymClass gymClass;
  final bool compactDensity;
  final VoidCallback onTap;
  final bool hasConflict;

  // Resolve coach display name — prefer the list, fall back to legacy field
  String? get _coachDisplay {
    final names =
        gymClass.coachNames.where((n) => n.trim().isNotEmpty).toList();
    if (names.isNotEmpty) return names.join(', ');
    final legacy = gymClass.coachName.trim();
    return legacy.isNotEmpty ? legacy : null;
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(gymClass);
    final theme = Theme.of(context);
    final isFull = gymClass.bookedCount >= gymClass.capacity;
    final time =
        '${DateFormat('HH:mm').format(gymClass.startTime)} – ${DateFormat('HH:mm').format(gymClass.endTime)}';
    final coach = _coachDisplay;

    return Stack(
      children: [
        Material(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: color.withValues(alpha: 0.35), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Left accent bar ────────────────────────────────────
                  Container(
                    width: compactDensity ? 3 : 4,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8),
                      ),
                    ),
                  ),
                  // ── Card content ───────────────────────────────────────
                  Expanded(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxHeight: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          compactDensity ? 5 : 7,
                          compactDensity ? 4 : 5,
                          compactDensity ? 5 : 7,
                          compactDensity ? 3 : 4,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // Time + capacity row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    time,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      fontSize: compactDensity ? 9 : 10,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                // Capacity pill
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isFull
                                        ? Colors.red.withValues(alpha: 0.15)
                                        : color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${gymClass.bookedCount}/${gymClass.capacity}',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          isFull ? Colors.red.shade700 : color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // Class title
                            Text(
                              gymClass.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compactDensity ? 11 : 13,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            // Coach name
                            if (coach != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person_outline_rounded,
                                    size: compactDensity ? 9 : 10,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      coach,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: compactDensity ? 9 : 10,
                                        fontWeight: FontWeight.w500,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            // Repeat indicator (small, only when space)
                            if (gymClass.repeatWeekly)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.repeat_rounded,
                                  size: compactDensity ? 8 : 9,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ), // OverflowBox
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasConflict)
          const Positioned(
            top: 3,
            right: 3,
            child: Icon(
              Icons.warning_amber_rounded,
              size: 11,
              color: Colors.orange,
            ),
          ),
      ],
    );
  }

  Color _colorFor(GymClass gymClass) => _classColor(gymClass);
}

// Top-level color resolver shared by all calendar view modes.
Color _classColor(GymClass gymClass) {
  if (gymClass.classColorValue != null) return Color(gymClass.classColorValue!);
  const palette = <Color>[
    Color(0xFF147AD6),
    Color(0xFF008272),
    Color(0xFFB146C2),
    Color(0xFFD83B01),
    Color(0xFF5C2D91),
    Color(0xFF8764B8),
    Color(0xFF4F6BED),
    Color(0xFF498205),
  ];
  final key = gymClass.title.trim().isNotEmpty
      ? gymClass.title.trim().toLowerCase()
      : gymClass.coachName.trim().toLowerCase();
  return palette[key.isEmpty ? 0 : key.hashCode.abs() % palette.length];
}

class _ClassListCard extends StatelessWidget {
  const _ClassListCard({
    required this.gymClass,
    required this.compactDensity,
    required this.onTap,
    this.hasConflict = false,
  });

  final GymClass gymClass;
  final bool compactDensity;
  final VoidCallback onTap;
  final bool hasConflict;

  @override
  Widget build(BuildContext context) {
    final time =
        '${DateFormat('HH:mm').format(gymClass.startTime)} - ${DateFormat('HH:mm').format(gymClass.endTime)}';

    return ListTile(
      onTap: onTap,
      dense: compactDensity,
      contentPadding: EdgeInsets.symmetric(
        horizontal: compactDensity ? 8 : 12,
        vertical: compactDensity ? 2 : 6,
      ),
      title: Text(gymClass.title),
      subtitle: Row(
        children: [
          if (gymClass.repeatWeekly) ...[
            Icon(Icons.repeat,
                size: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              '$time • ${gymClass.coachName.isNotEmpty ? gymClass.coachName : context.l10n.tr('No coach')}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasConflict)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: Colors.orange,
              ),
            ),
          const Icon(Icons.more_horiz),
        ],
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.4),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.locale,
    required this.count,
    this.ptCount = 0,
  });

  final DateTime day;
  final String locale;
  final int count;
  final int ptCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            DateFormat('EEE, d MMM', locale).format(day),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('$count', style: const TextStyle(fontSize: 12)),
        ),
        if (ptCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline,
                    size: 10, color: Color(0xFF7C3AED)),
                const SizedBox(width: 3),
                Text('$ptCount ${context.l10n.tr('PT')}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7C3AED),
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── PT timeline card ─────────────────────────────────────────────────────────

class _PtTimelineCard extends StatelessWidget {
  const _PtTimelineCard({required this.pt, required this.compactDensity});
  final PersonalTraining pt;
  final bool compactDensity;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final dur = pt.endTime.difference(pt.startTime).inMinutes;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _purple.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(compactDensity ? 4 : 6),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 9, color: Colors.white70),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    context.l10n.tr('PT'),
                    overflow: TextOverflow.clip,
                    maxLines: 1,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: compactDensity ? 8 : 9,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (!compactDensity) const SizedBox(height: 2),
            Text(
              pt.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: compactDensity ? 9 : 10,
                  fontWeight: FontWeight.w700,
                  height: 1.2),
            ),
            if (dur >= 45 && !compactDensity) ...[
              const SizedBox(height: 2),
              Text(
                '${DateFormat('HH:mm').format(pt.startTime)} · ${dur}m',
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ],
            if (pt.memberNames.isNotEmpty && dur >= 60) ...[
              const SizedBox(height: 2),
              Text(
                pt.memberNames.take(2).join(', ') +
                    (pt.memberNames.length > 2
                        ? ' +${pt.memberNames.length - 2}'
                        : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── PT list card (vertical/mobile week view) ──────────────────────────────────

class _PtListCard extends StatelessWidget {
  const _PtListCard({required this.pt, required this.compactDensity});
  final PersonalTraining pt;
  final bool compactDensity;

  @override
  Widget build(BuildContext context) {
    final dur = pt.endTime.difference(pt.startTime).inMinutes;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compactDensity ? 10 : 12,
          vertical: compactDensity ? 7 : 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_person_outlined,
              size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pt.title,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: compactDensity ? 12 : 13,
                        fontWeight: FontWeight.w700)),
                Text(
                  '${DateFormat('HH:mm').format(pt.startTime)} · ${dur}m'
                  '${pt.location.isNotEmpty ? ' · ${pt.location}' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          if (pt.memberNames.isNotEmpty)
            Text(
              '${pt.memberNames.length} ${context.l10n.tr(pt.memberNames.length == 1 ? 'member' : 'members')}',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500),
            ),
        ],
      ),
    );
  }
}

// ── Filter bar ─────────────────────────────────────────────────────────────────

class _FilterBar extends StatefulWidget {
  const _FilterBar({
    required this.filterQuery,
    required this.filterCoach,
    required this.capacityFilter,
    required this.coaches,
    required this.onQueryChanged,
    required this.onCoachChanged,
    required this.onCapacityFilterChanged,
    required this.onClearAll,
  });

  final String filterQuery;
  final String? filterCoach;
  final _CapacityFilter capacityFilter;
  final List<String> coaches;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onCoachChanged;
  final ValueChanged<_CapacityFilter> onCapacityFilterChanged;
  final VoidCallback onClearAll;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.filterQuery);
  }

  @override
  void didUpdateWidget(_FilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filterQuery != _ctrl.text) {
      _ctrl.text = widget.filterQuery;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilter =>
      widget.filterQuery.isNotEmpty ||
      widget.filterCoach != null ||
      widget.capacityFilter != _CapacityFilter.all;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onChanged: widget.onQueryChanged,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.l10n.tr('Search classes…'),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: widget.filterQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _ctrl.clear();
                                widget.onQueryChanged('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                if (_hasActiveFilter) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      _ctrl.clear();
                      widget.onClearAll();
                    },
                    child: Text(context.l10n.tr('Clear all')),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...(_CapacityFilter.values.map((f) {
                    final label = switch (f) {
                      _CapacityFilter.all => context.l10n.tr('All'),
                      _CapacityFilter.available => context.l10n.tr('Available'),
                      _CapacityFilter.full => context.l10n.tr('Full'),
                    };
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: widget.capacityFilter == f,
                        onSelected: (_) => widget.onCapacityFilterChanged(f),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  })),
                  if (widget.coaches.isNotEmpty) ...[
                    Container(
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    ...(widget.coaches.map((coach) {
                      final selected = widget.filterCoach == coach;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(coach),
                          selected: selected,
                          onSelected: (_) => widget.onCoachChanged(
                            selected ? null : coach,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    })),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Month grid view
// ─────────────────────────────────────────────────────────────────────────────

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.anchorDate,
    required this.classes,
    required this.locale,
    required this.onClassTap,
    required this.onDayTap,
  });

  final DateTime anchorDate;
  final List<GymClass> classes;
  final String locale;
  final ValueChanged<GymClass> onClassTap;
  final ValueChanged<DateTime> onDayTap;

  // Number of grid columns × rows (Mon–Sun × 6 weeks)
  static const _cols = 7;
  static const _rows = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final firstOfMonth = DateTime(anchorDate.year, anchorDate.month, 1);
    // Grid starts on Monday of the week that contains the 1st of the month.
    final gridStart =
        firstOfMonth.subtract(Duration(days: firstOfMonth.weekday - 1));

    // Group classes by normalised day key.
    final classesByDay = <String, List<GymClass>>{};
    for (final c in classes) {
      final key =
          '${c.startTime.year}-${c.startTime.month}-${c.startTime.day}';
      (classesByDay[key] ??= []).add(c);
    }
    for (final list in classesByDay.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    final divider =
        theme.colorScheme.outlineVariant.withValues(alpha: 0.3);

    return Column(
      children: [
        // ── Weekday header row ─────────────────────────────────────────────
        Row(
          children: List.generate(_cols, (i) {
            final label = DateFormat.E(locale)
                .format(gridStart.add(Duration(days: i)))
                .toUpperCase();
            return Expanded(
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration:
                    BoxDecoration(border: Border(bottom: BorderSide(color: divider))),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }),
        ),
        // ── Day cells (6 rows × 7 cols) ────────────────────────────────────
        Expanded(
          child: Column(
            children: List.generate(_rows, (row) {
              return Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(_cols, (col) {
                    final day = gridStart
                        .add(Duration(days: row * _cols + col));
                    final isCurrentMonth = day.month == anchorDate.month;
                    final isToday = day.year == today.year &&
                        day.month == today.month &&
                        day.day == today.day;
                    final key =
                        '${day.year}-${day.month}-${day.day}';
                    final dayCls = classesByDay[key] ?? const [];

                    return Expanded(
                      child: _DayCell(
                        day: day,
                        classes: dayCls,
                        isCurrentMonth: isCurrentMonth,
                        isToday: isToday,
                        onTap: () => onDayTap(day),
                        onClassTap: onClassTap,
                        dividerColor: divider,
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single day cell in the month grid
// ─────────────────────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.classes,
    required this.isCurrentMonth,
    required this.isToday,
    required this.onTap,
    required this.onClassTap,
    required this.dividerColor,
  });

  final DateTime day;
  final List<GymClass> classes;
  final bool isCurrentMonth;
  final bool isToday;
  final VoidCallback onTap;
  final ValueChanged<GymClass> onClassTap;
  final Color dividerColor;

  // Maximum chip rows shown before "+N more".
  static const _maxChips = 2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelAlpha = isCurrentMonth ? 1.0 : 0.3;

    final visible = classes.take(_maxChips).toList();
    final overflow = classes.length - _maxChips;

    return InkWell(
      onTap: onTap,
      child: ClipRect(
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: dividerColor, width: 0.5),
              bottom: BorderSide(color: dividerColor, width: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Day number ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
                child: isToday
                    ? Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: cs.onPrimary,
                            height: 1,
                          ),
                        ),
                      )
                    : Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: labelAlpha),
                        ),
                      ),
              ),
              // ── Class chips ────────────────────────────────────────────
              ...visible.map(
                (cls) => _MonthClassChip(
                  gymClass: cls,
                  onTap: () => onClassTap(cls),
                ),
              ),
              // ── Overflow indicator ─────────────────────────────────────
              if (overflow > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 1, 4, 0),
                  child: Text(
                    '+$overflow',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
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
// Class chip inside a month cell
// ─────────────────────────────────────────────────────────────────────────────

class _MonthClassChip extends StatelessWidget {
  const _MonthClassChip({
    required this.gymClass,
    required this.onTap,
  });

  final GymClass gymClass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _classColor(gymClass);
    final isFull = gymClass.capacity > 0 &&
        gymClass.bookedCount >= gymClass.capacity;
    final chipColor = isFull ? Colors.red.shade600 : color;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(3),
          border: Border(
            left: BorderSide(color: chipColor, width: 3),
          ),
        ),
        child: Text(
          gymClass.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: chipColor,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}
