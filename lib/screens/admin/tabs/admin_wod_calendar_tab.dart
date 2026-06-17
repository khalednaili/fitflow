import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/wod_entry.dart';
import '../../../services/class_type_service.dart';
import '../../../services/wod_service.dart';
import 'admin_wod_tab.dart';

// ── Brand colours ─────────────────────────────────────────────────────────────

const _kRed    = Color(0xFFEF4444); // today highlight (Octiv style)
const _kOrange = Color(0xFFF97316); // WOD brand / For Time
const _kGreen  = Color(0xFF22C55E); // AMRAP
const _kBlue   = Color(0xFF3B82F6); // EMOM
const _kPurple = Color(0xFFA855F7); // Strength / Olympic
const _kGray   = Color(0xFF94A3B8); // fallback

Color _formatColor(String fmt) {
  switch (fmt.toLowerCase()) {
    case 'for time': return _kOrange;
    case 'amrap':    return _kGreen;
    case 'emom':     return _kBlue;
    case 'strength': return _kPurple;
    case 'tabata':   return _kRed;
    default:         return _kGray;
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ── View enum ─────────────────────────────────────────────────────────────────

enum _CalView { month, week, list }

// ── Main widget ───────────────────────────────────────────────────────────────

class AdminWodCalendarTab extends StatefulWidget {
  const AdminWodCalendarTab({super.key, required this.gymId});
  final String gymId;

  @override
  State<AdminWodCalendarTab> createState() => _AdminWodCalendarTabState();
}

class _AdminWodCalendarTabState extends State<AdminWodCalendarTab> {
  // Default to week view (Octiv-style)
  _CalView _view = _CalView.week;
  late DateTime _refDate;
  late final WodService _svc;
  late final ClassTypeService _ctSvc;
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    _refDate = DateTime.now();
    _svc  = WodService(gymId: widget.gymId);
    _ctSvc = ClassTypeService(gymId: widget.gymId);
  }

  // Week starts on Monday
  DateTime get _weekMonday =>
      _refDate.subtract(Duration(days: _refDate.weekday - 1));
  DateTime get _weekSunday => _weekMonday.add(const Duration(days: 6));

  DateTime get _focusedMonth => DateTime(_refDate.year, _refDate.month);

  void _prev() => setState(() {
        _refDate = _view == _CalView.week
            ? _refDate.subtract(const Duration(days: 7))
            : DateTime(_refDate.year, _refDate.month - 1, 1);
      });

  void _next() => setState(() {
        _refDate = _view == _CalView.week
            ? _refDate.add(const Duration(days: 7))
            : DateTime(_refDate.year, _refDate.month + 1, 1);
      });

  void _goToday() => setState(() => _refDate = DateTime.now());

  String get _headerLabel {
    if (_view == _CalView.week) {
      final mon = _weekMonday;
      final sun = _weekSunday;
      if (mon.month == sun.month) {
        return '${DateFormat('MMMM yyyy').format(mon)}'
            ' · ${DateFormat('d').format(mon)}–${DateFormat('d').format(sun)}';
      }
      return '${DateFormat('MMM d').format(mon)} – ${DateFormat('MMM d, yyyy').format(sun)}';
    }
    return DateFormat('MMMM yyyy').format(_refDate);
  }

  // ── Editor helpers ────────────────────────────────────────────────────────

  void _openEditor(BuildContext context, {WodEntry? existing, DateTime? date}) {
    showWodEditor(
      context,
      svc: _svc,
      gymId: widget.gymId,
      existing: existing,
      defaultDate: date,
    );
  }

  void _onDayTap(BuildContext context, DateTime date, List<WodEntry> wods) {
    if (wods.isEmpty) {
      // No workouts yet — go straight to create
      _openEditor(context, date: date);
    } else {
      // One or more workouts exist — show picker so user can edit or add another
      _showWodPicker(context, date, wods);
    }
  }

  void _showWodPicker(BuildContext context, DateTime date, List<WodEntry> wods) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('Workouts — ${DateFormat('EEE d MMM').format(date)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                // Always allow adding another workout for this day
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openEditor(context, date: date);
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...wods.map((w) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: _kOrange.withAlpha(30),
                  child: const Icon(Icons.fitness_center, color: _kOrange, size: 18),
                ),
                title: Text(w.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: w.classTypeName.isNotEmpty ? Text(w.classTypeName) : null,
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  _openEditor(context, existing: w);
                },
              )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Seed demo data ─────────────────────────────────────────────────────────

  Future<void> _confirmAndSeed(BuildContext context) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seed Demo Workouts?'),
        content: Text(
          'This will add ~15 demo WODs to ${DateFormat('MMMM yyyy').format(_focusedMonth)}. '
          'Existing workouts on the same date + class type will be skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Seed Data'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    setState(() => _seeding = true);
    try {
      await _seedDemoData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demo workouts added ✓'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _seedDemoData() async {
    final classTypes = await _ctSvc.streamClassTypes().first;
    final String ctId    = classTypes.isNotEmpty ? classTypes.first.id   : '';
    final String ctName  = classTypes.isNotEmpty ? classTypes.first.name : 'WOD';
    final String ct2Id   = classTypes.length > 1 ? classTypes[1].id   : ctId;
    final String ct2Name = classTypes.length > 1 ? classTypes[1].name : ctName;

    final y = _focusedMonth.year;
    final m = _focusedMonth.month;

    final demos = <_DemoWod>[
      _DemoWod(day: 2,  title: 'Fran',              ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'For Time', '21-15-9 Thrusters & Pull-ups', [
          _DemoEx('Thruster', '3', '21-15-9', '95/65 lb'),
          _DemoEx('Pull-up',  '',  '21-15-9', ''),
        ])]),
      _DemoWod(day: 3,  title: 'Strength Day',      ctId: ct2Id, ctName: ct2Name,
        parts: [
          _DemoPart('Part A – Squat', 'Strength', '5 × 5 Back Squat',   [_DemoEx('Back Squat',    '5', '5', '75% 1RM')]),
          _DemoPart('Part B – Press', 'Strength', '4 × 8 Strict Press', [_DemoEx('Strict Press',  '4', '8', '60% 1RM')]),
        ]),
      _DemoWod(day: 5,  title: 'The Chief',         ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'AMRAP', '3 min AMRAP × 5 cycles', [
          _DemoEx('Power Clean', '', '3', '135/95 lb'),
          _DemoEx('Push-up',     '', '6', ''),
          _DemoEx('Air Squat',   '', '9', ''),
        ])]),
      _DemoWod(day: 7,  title: 'Cindy',             ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'AMRAP', '20 min AMRAP', [
          _DemoEx('Pull-up',   '', '5',  ''),
          _DemoEx('Push-up',   '', '10', ''),
          _DemoEx('Air Squat', '', '15', ''),
        ])]),
      _DemoWod(day: 9,  title: 'Deadlift + Metcon', ctId: ct2Id, ctName: ct2Name,
        parts: [
          _DemoPart('Part A', 'Strength', 'Build to a heavy triple', [_DemoEx('Deadlift', '5', '3', 'Heavy')]),
          _DemoPart('Part B', 'For Time', '3 rounds for time', [
            _DemoEx('Box Jump',         '3', '15', '24/20 in'),
            _DemoEx('Kettlebell Swing', '3', '20', '53/35 lb'),
            _DemoEx('Double Under',     '3', '30', ''),
          ]),
        ]),
      _DemoWod(day: 10, title: 'EMOM 20',           ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'EMOM', 'E1MOM × 20 min', [
          _DemoEx('Hang Power Snatch (odd)', '', '5',  '75/55 lb'),
          _DemoEx('Toes-to-Bar (even)',      '', '10', ''),
        ])]),
      _DemoWod(day: 12, title: 'Half Murph',        ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'For Time', 'Partition as needed', [
          _DemoEx('Run',       '', '800 m', ''),
          _DemoEx('Pull-up',   '', '50',    ''),
          _DemoEx('Push-up',   '', '100',   ''),
          _DemoEx('Air Squat', '', '150',   ''),
          _DemoEx('Run',       '', '800 m', ''),
        ])]),
      _DemoWod(day: 14, title: 'Olympic Lifting',   ctId: ct2Id, ctName: ct2Name,
        parts: [
          _DemoPart('Part A – Snatch',       'Strength', 'E2MOM × 6', [_DemoEx('Power Snatch', '6', '3', '70%')]),
          _DemoPart('Part B – Clean & Jerk', 'Strength', 'E2MOM × 6', [_DemoEx('Clean & Jerk','6', '2', '75%')]),
        ]),
      _DemoWod(day: 16, title: 'Grace',             ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'For Time', '30 Clean & Jerks for time', [
          _DemoEx('Clean & Jerk', '', '30', '135/95 lb'),
        ])]),
      _DemoWod(day: 17, title: 'Tabata Assault',    ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'Tabata', '8 rounds: 20 sec on / 10 sec off', [
          _DemoEx('Assault Bike', '8', '20 sec', ''),
          _DemoEx('Wall Ball',    '8', '20 sec', '20/14 lb'),
        ])]),
      _DemoWod(day: 19, title: 'Annie',             ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'For Time', '50-40-30-20-10 reps', [
          _DemoEx('Double Under', '', '50-40-30-20-10', ''),
          _DemoEx('Sit-up',       '', '50-40-30-20-10', ''),
        ])]),
      _DemoWod(day: 21, title: 'Push & Pull',       ctId: ct2Id, ctName: ct2Name,
        parts: [
          _DemoPart('Part A', 'Strength', '4 × 6 Weighted Pull-ups',  [_DemoEx('Weighted Pull-up', '4', '6', '+25 lb')]),
          _DemoPart('Part B', 'Strength', '4 × 8 DB Bench Press',     [_DemoEx('DB Bench Press',   '4', '8', '50/35 lb')]),
          _DemoPart('Part C', 'AMRAP',    '10 min AMRAP', [
            _DemoEx('Ring Dip',     '', '10', ''),
            _DemoEx('Chest-to-Bar', '', '10', ''),
          ]),
        ]),
      _DemoWod(day: 23, title: 'DT',                ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'For Time', '5 rounds for time', [
          _DemoEx('Deadlift',         '5', '12', '155/105 lb'),
          _DemoEx('Hang Power Clean', '5', '9',  '155/105 lb'),
          _DemoEx('Push Jerk',        '5', '6',  '155/105 lb'),
        ])]),
      _DemoWod(day: 25, title: 'E2MOM Strength',    ctId: ct2Id, ctName: ct2Name,
        parts: [_DemoPart('Part A', 'EMOM', 'E2MOM × 10 (5 sets each)', [
          _DemoEx('Front Squat (odd)',  '5', '4', '80%'),
          _DemoEx('Strict HSPU (even)', '5', '8', ''),
        ])]),
      _DemoWod(day: 27, title: 'Helen',             ctId: ctId,  ctName: ctName,
        parts: [_DemoPart('Part A', 'For Time', '3 rounds for time', [
          _DemoEx('Run',              '3', '400 m', ''),
          _DemoEx('Kettlebell Swing', '3', '21',    '53/35 lb'),
          _DemoEx('Pull-up',          '3', '12',    ''),
        ])]),
    ];

    for (final demo in demos) {
      final date = DateTime(y, m, demo.day);
      final exists = await _svc.existsForDateAndType(date, demo.ctId);
      if (exists) continue;
      final parts = demo.parts
          .map((p) => WodPart(
                title: p.title,
                format: p.format,
                description: p.description,
                exercises: p.exercises
                    .map((e) => WodExercise(
                          name: e.name,
                          sets: e.sets,
                          reps: e.reps,
                          weight: e.weight,
                        ))
                    .toList(),
              ))
          .toList();
      await _svc.create(WodEntry(
        id: '',
        title: demo.title,
        description: parts.first.description,
        date: date,
        classTypeId: demo.ctId,
        classTypeName: demo.ctName,
        gymId: widget.gymId,
        parts: parts,
      ));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final stream = _view == _CalView.week
        ? _svc.streamForRange(_weekMonday, _weekSunday)
        : _svc.streamForMonth(_focusedMonth);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: StreamBuilder<List<WodEntry>>(
        stream: stream,
        builder: (context, snap) {
          final wods = snap.data ?? [];
          final isLoading =
              snap.connectionState == ConnectionState.waiting && wods.isEmpty;

          return Column(
            children: [
              _ControlBar(
                label: _headerLabel,
                view: _view,
                seeding: _seeding,
                onPrev: _prev,
                onNext: _next,
                onToday: _goToday,
                onViewChanged: (v) => setState(() => _view = v),
                onSeed: () => _confirmAndSeed(context),
                onPostWorkout: () => _openEditor(context),
              ),
              if (isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_view == _CalView.week)
                Expanded(
                  child: _WeekView(
                    monday: _weekMonday,
                    wods: wods,
                    onDayTap: (date, dayWods) =>
                        _onDayTap(context, date, dayWods),
                  ),
                )
              else if (_view == _CalView.month)
                Expanded(
                  child: _MonthView(
                    month: _focusedMonth,
                    wods: wods,
                    onDayTap: (date, dayWods) =>
                        _onDayTap(context, date, dayWods),
                  ),
                )
              else
                Expanded(
                  child: _WodListView(
                    wods: wods,
                    onTap: (w) => _openEditor(context, existing: w),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: kIsWeb
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('Post Workout'),
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
            ),
    );
  }
}

// ── Control bar ───────────────────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.label,
    required this.view,
    required this.seeding,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onViewChanged,
    required this.onSeed,
    this.onPostWorkout,
  });

  final String label;
  final _CalView view;
  final bool seeding;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<_CalView> onViewChanged;
  final VoidCallback onSeed;
  final VoidCallback? onPostWorkout;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kIsWeb ? 12 : 8,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withAlpha(80)),
        ),
      ),
      child: Row(
        children: [
          // Today button
          _NavBtn(label: 'Today', onTap: onToday),
          const SizedBox(width: 4),
          // Prev / Next
          _IconNavBtn(icon: Icons.chevron_left, onTap: onPrev),
          _IconNavBtn(icon: Icons.chevron_right, onTap: onNext),
          const SizedBox(width: 8),
          // Date label
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // View toggles
          _ViewToggle(current: view, onChanged: onViewChanged),
          const SizedBox(width: 8),
          if (onPostWorkout != null) ...[
            FilledButton.icon(
              onPressed: onPostWorkout,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Post Workout'),
              style: FilledButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Seed button
          if (seeding)
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: Icon(Icons.science_outlined, color: cs.onSurfaceVariant),
              tooltip: 'Seed demo workouts',
              onPressed: onSeed,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatefulWidget {
  const _NavBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<_NavBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered ? cs.primary.withAlpha(15) : null,
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconNavBtn extends StatelessWidget {
  const _IconNavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.current, required this.onChanged});
  final _CalView current;
  final ValueChanged<_CalView> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget btn(_CalView v, String lbl) {
      final active = current == v;
      return GestureDetector(
        onTap: () => onChanged(v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: active ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            lbl,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(_CalView.month, 'Month'),
          btn(_CalView.week,  'Week'),
          btn(_CalView.list,  'List'),
        ],
      ),
    );
  }
}

// ── Week view ─────────────────────────────────────────────────────────────────

class _WeekView extends StatelessWidget {
  const _WeekView({
    required this.monday,
    required this.wods,
    required this.onDayTap,
  });

  final DateTime monday;
  final List<WodEntry> wods;
  final void Function(DateTime date, List<WodEntry> wods) onDayTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final cs   = Theme.of(context).colorScheme;

    // Group wods by day
    final Map<String, List<WodEntry>> byDay = {};
    for (final w in wods) {
      final key =
          '${w.date.year}-${w.date.month}-${w.date.day}';
      byDay.putIfAbsent(key, () => []).add(w);
    }

    String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

    return Column(
      children: [
        // Sticky day-header row
        Container(
          color: cs.surface,
          child: Row(
            children: days.map((d) {
              final isToday = _sameDay(d, today);
              return Expanded(
                child: _WeekDayHeader(date: d, isToday: isToday),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1),
        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: days.map((d) {
                final dayWods = byDay[dayKey(d)] ?? [];
                final isToday = _sameDay(d, today);
                return Expanded(
                  child: _WeekDayColumn(
                    date: d,
                    wods: dayWods,
                    isToday: isToday,
                    onDayTap: () => onDayTap(d, dayWods),
                    onWodTap: (w) => onDayTap(d, [w]),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekDayHeader extends StatelessWidget {
  const _WeekDayHeader({required this.date, required this.isToday});
  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final dayName = DateFormat('E').format(date).toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(
            dayName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isToday ? _kRed : Colors.grey.shade500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: isToday ? _kRed : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isToday ? Colors.white : Colors.grey.shade800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekDayColumn extends StatefulWidget {
  const _WeekDayColumn({
    required this.date,
    required this.wods,
    required this.isToday,
    required this.onDayTap,
    required this.onWodTap,
  });

  final DateTime date;
  final List<WodEntry> wods;
  final bool isToday;
  final VoidCallback onDayTap;
  final ValueChanged<WodEntry> onWodTap;

  @override
  State<_WeekDayColumn> createState() => _WeekDayColumnState();
}

class _WeekDayColumnState extends State<_WeekDayColumn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final highlightColor = widget.isToday
        ? _kRed.withAlpha(6)
        : (_hovered ? cs.primary.withAlpha(8) : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: highlightColor,
          border: Border(
            top: BorderSide(
              color: _hovered
                  ? cs.primary.withAlpha(60)
                  : Colors.transparent,
            ),
            right: BorderSide(color: cs.outlineVariant.withAlpha(80)),
          ),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // WOD cards
            ...widget.wods.map((w) => _WodCard(
                  wod: w,
                  onTap: () => widget.onWodTap(w),
                )),
            // Tap-to-add area — always present so a second (or third) workout can be added
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onDayTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: widget.wods.isEmpty ? 80 : 28,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add_circle_outline,
                    color: cs.outlineVariant,
                    size: widget.wods.isEmpty ? 20 : 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── WOD card (week view) ──────────────────────────────────────────────────────

class _WodCard extends StatefulWidget {
  const _WodCard({required this.wod, required this.onTap});
  final WodEntry wod;
  final VoidCallback onTap;

  @override
  State<_WodCard> createState() => _WodCardState();
}

class _WodCardState extends State<_WodCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primaryFormat = widget.wod.parts.isNotEmpty
        ? widget.wod.parts.first.format
        : widget.wod.format;
    final fmtColor = _formatColor(primaryFormat);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFFFFBFF) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: fmtColor, width: 3)),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? Colors.black.withAlpha(25)
                    : Colors.black.withAlpha(12),
                blurRadius: _hovered ? 12 : 4,
                offset: _hovered ? const Offset(0, 4) : const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: class type + format badge ──────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.wod.classTypeName.isNotEmpty
                            ? widget.wod.classTypeName
                            : 'WOD',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_hovered)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    if (primaryFormat.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: fmtColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          primaryFormat,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: fmtColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),

                // ── Workout title ───────────────────────────────────────────────
                Text(
                  widget.wod.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),

                // ── Warm Up ────────────────────────────────────────────────────
                if (widget.wod.warmUp.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  _SectionChip(label: 'Warm Up', color: Colors.green.shade600),
                  const SizedBox(height: 2),
                  Text(
                    widget.wod.warmUp,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
                  ),
                ],

                // ── Parts ──────────────────────────────────────────────────────
                if (widget.wod.parts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...widget.wod.parts.map((part) => _PartCard(part: part)),
                ] else if (widget.wod.exercises.isNotEmpty) ...[
                  // Legacy flat exercise list
                  const SizedBox(height: 4),
                  ...widget.wod.exercises.map(
                    (ex) => _ExRow(ex: ex, color: fmtColor),
                  ),
                ],

                // ── Cool Down ──────────────────────────────────────────────────
                if (widget.wod.coolDown.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  _SectionChip(label: 'Cool Down', color: Colors.blue.shade600),
                  const SizedBox(height: 2),
                  Text(
                    widget.wod.coolDown,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
                  ),
                ],

                // ── Member note ────────────────────────────────────────────────
                if (widget.wod.memberNote.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  _SectionChip(label: 'Note', color: Colors.amber.shade700),
                  const SizedBox(height: 2),
                  Text(
                    widget.wod.memberNote,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin label pill used inside the card for named sections.
class _SectionChip extends StatelessWidget {
  const _SectionChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// One workout part block inside a card.
class _PartCard extends StatelessWidget {
  const _PartCard({required this.part});
  final WodPart part;

  @override
  Widget build(BuildContext context) {
    final partColor = _formatColor(part.format);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
      decoration: BoxDecoration(
        color: partColor.withAlpha(12),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: partColor, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Part header
          Row(
            children: [
              if (part.title.isNotEmpty)
                Expanded(
                  child: Text(
                    part.title,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (part.format.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: partColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    part.format,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: partColor,
                    ),
                  ),
                ),
            ],
          ),
          // Time cap + measure
          if (part.timeCap.isNotEmpty || part.measure.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (part.timeCap.isNotEmpty) '⏱ ${part.timeCap}',
                  if (part.measure.isNotEmpty) part.measure,
                ].join('  '),
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          // Description
          if (part.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                part.description,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
              ),
            ),
          // Exercises
          if (part.exercises.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...part.exercises.map((ex) => _ExRow(ex: ex, color: partColor)),
          ],
          // Scales
          if (part.scales.isNotEmpty) ...[
            const SizedBox(height: 3),
            ...part.scales.map((sc) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Icon(Icons.tune, size: 9, color: partColor),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          sc.label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: partColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// Single exercise row with dot bullet.
class _ExRow extends StatelessWidget {
  const _ExRow({required this.ex, required this.color});
  final WodExercise ex;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = _buildLabel();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4, height: 4,
            margin: const EdgeInsets.only(top: 4, right: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  String _buildLabel() {
    final buf = StringBuffer(ex.name);
    if (ex.sets.isNotEmpty && ex.reps.isNotEmpty) {
      buf.write('  ${ex.sets}×${ex.reps}');
    } else if (ex.reps.isNotEmpty) {
      buf.write('  ${ex.reps}');
    }
    if (ex.weight.isNotEmpty) buf.write(' @ ${ex.weight}');
    if (ex.notes.isNotEmpty) buf.write('  — ${ex.notes}');
    return buf.toString();
  }
}

// ── Month view ────────────────────────────────────────────────────────────────

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.month,
    required this.wods,
    required this.onDayTap,
  });

  final DateTime month;
  final List<WodEntry> wods;
  final void Function(DateTime date, List<WodEntry> wods) onDayTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final firstDay = DateTime(month.year, month.month, 1);
    final offset = firstDay.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    int totalCells = offset + daysInMonth;
    if (totalCells % 7 != 0) totalCells += 7 - (totalCells % 7);

    // Weekday header labels (Mon–Sun)
    final dayLabels = List.generate(7, (i) {
      final d = DateTime(2024, 1, 1 + i);
      return DateFormat('E').format(d).toUpperCase();
    });

    // Group wods by day
    final Map<int, List<WodEntry>> byDay = {};
    for (final w in wods) { byDay.putIfAbsent(w.date.day, () => []).add(w); }

    return Column(
      children: [
        // Weekday header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: dayLabels
                .map((l) => Expanded(
                      child: Center(
                        child: Text(l,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            )),
                      ),
                    ))
                .toList(),
          ),
        ),
        // Grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GridView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 5,
                crossAxisSpacing: 3,
                childAspectRatio: 0.82,
              ),
              itemCount: totalCells,
              itemBuilder: (ctx, index) {
                final day = index - offset + 1;
                if (day < 1 || day > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final date =
                    DateTime(month.year, month.month, day);
                final isToday = _sameDay(date, today);
                final dayWods = byDay[day] ?? [];
                return _MonthDayCell(
                  day: day,
                  isToday: isToday,
                  wods: dayWods,
                  onTap: () => onDayTap(date, dayWods),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthDayCell extends StatefulWidget {
  const _MonthDayCell({
    required this.day,
    required this.isToday,
    required this.wods,
    required this.onTap,
  });

  final int day;
  final bool isToday;
  final List<WodEntry> wods;
  final VoidCallback onTap;

  @override
  State<_MonthDayCell> createState() => _MonthDayCellState();
}

class _MonthDayCellState extends State<_MonthDayCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasWod = widget.wods.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered
                ? cs.primary.withAlpha(10)
                : hasWod
                    ? _kOrange.withAlpha(12)
                    : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isToday
                  ? _kRed
                  : _hovered
                      ? cs.primary.withAlpha(60)
                      : hasWod
                          ? _kOrange.withAlpha(80)
                          : cs.outlineVariant.withAlpha(120),
              width: widget.isToday ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 6),
              // Day number
              Container(
                width: 24,
                height: 24,
                decoration: widget.isToday
                    ? const BoxDecoration(
                        color: _kRed,
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Center(
                  child: Text(
                    '${widget.day}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          widget.isToday ? FontWeight.w800 : FontWeight.w600,
                      color: widget.isToday ? Colors.white : cs.onSurface,
                    ),
                  ),
                ),
              ),
              if (hasWod) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 46) {
                        return const Center(
                          child: CircleAvatar(
                            radius: 3.5,
                            backgroundColor: _kOrange,
                          ),
                        );
                      }
                      return Column(
                        children: widget.wods.take(2).map((w) {
                          final fmt = w.parts.isNotEmpty
                              ? w.parts.first.format
                              : w.format;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: _formatColor(fmt),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              w.classTypeName.isNotEmpty
                                  ? w.classTypeName
                                  : w.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
                if (widget.wods.length > 2)
                  Text(
                    '+${widget.wods.length - 2}',
                    style: const TextStyle(
                      fontSize: 8,
                      color: _kOrange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── List view ─────────────────────────────────────────────────────────────────

class _WodListView extends StatelessWidget {
  const _WodListView({required this.wods, required this.onTap});
  final List<WodEntry> wods;
  final ValueChanged<WodEntry> onTap;

  @override
  Widget build(BuildContext context) {
    if (wods.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withAlpha(80)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 64,
                color: cs.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No workouts scheduled',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap + Post Workout to create the first workout for this period',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.7,
            ),
            itemCount: wods.length,
            itemBuilder: (context, i) => _WodListItem(
              wod: wods[i],
              onTap: () => onTap(wods[i]),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: wods.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _WodListItem(
            wod: wods[i],
            onTap: () => onTap(wods[i]),
          ),
        );
      },
    );
  }
}

class _WodListItem extends StatefulWidget {
  const _WodListItem({required this.wod, required this.onTap});

  final WodEntry wod;
  final VoidCallback onTap;

  @override
  State<_WodListItem> createState() => _WodListItemState();
}

class _WodListItemState extends State<_WodListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = widget.wod.parts.isNotEmpty
        ? widget.wod.parts.first.format
        : widget.wod.format;
    final fmtColor = _formatColor(fmt);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFFFFBFF) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(
                color: fmtColor,
                width: _hovered ? 5 : 4,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? fmtColor.withAlpha(28)
                    : Colors.black.withAlpha(10),
                blurRadius: _hovered ? 12 : 4,
                offset: _hovered ? const Offset(0, 4) : const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('d').format(widget.wod.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(widget.wod.date).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            title: Text(
              widget.wod.title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            subtitle: Row(
              children: [
                if (widget.wod.classTypeName.isNotEmpty) ...[
                  Flexible(
                    child: Text(
                      widget.wod.classTypeName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (fmt.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: fmtColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      fmt,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: fmtColor,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: _hovered ? cs.primary : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Seed helper data classes ───────────────────────────────────────────────────

class _DemoEx {
  const _DemoEx(this.name, this.sets, this.reps, this.weight);
  final String name, sets, reps, weight;
}

class _DemoPart {
  const _DemoPart(this.title, this.format, this.description, this.exercises);
  final String title, format, description;
  final List<_DemoEx> exercises;
}

class _DemoWod {
  const _DemoWod({
    required this.day,
    required this.title,
    required this.ctId,
    required this.ctName,
    required this.parts,
  });
  final int day;
  final String title, ctId, ctName;
  final List<_DemoPart> parts;
}
