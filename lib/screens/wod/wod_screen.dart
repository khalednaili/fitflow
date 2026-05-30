import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/class_type.dart';
import '../../models/wod_entry.dart';
import '../../services/class_type_service.dart';
import '../../services/member_service.dart';
import '../../services/wod_service.dart';
import '../../widgets/user_avatar.dart';
import '../home/workout_tracker_screen.dart';
import '../../l10n/app_localizations.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _kPartAccents = [
  Color(0xFF2563EB),
  Color(0xFFF97316),
  Color(0xFF7C3AED),
  Color(0xFF059669),
  Color(0xFFDC2626),
  Color(0xFF0891B2),
];

const _kFormatIcons = <String, IconData>{
  'AMRAP': Icons.replay_rounded,
  'For Time': Icons.timer_rounded,
  'EMOM': Icons.alarm_rounded,
  'Strength': Icons.fitness_center_rounded,
  'Warm-Up': Icons.self_improvement_rounded,
  'Mobility': Icons.accessibility_new_rounded,
  'Tabata': Icons.av_timer_rounded,
  'For Load': Icons.monitor_weight_rounded,
  'Chipper': Icons.format_list_numbered_rounded,
};

double _kPartNavHeight = 64;

// Centers content on wide screens (max 880px).
Widget _webCenter(Widget child, {double maxWidth = 880}) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

String _partLabel(int index) {
  const labels = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
  return index < labels.length ? labels[index] : '${index + 1}';
}

RoundedRectangleBorder _cardShape(BuildContext context, {double radius = 24}) {
  final cs = Theme.of(context).colorScheme;
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: BorderSide(color: cs.outlineVariant.withAlpha(120)),
  );
}

Color _classTypeColor(ClassType type, ColorScheme cs) =>
    type.colorValue != null ? Color(type.colorValue!) : cs.primary;

IconData _scaleIcon(String label) {
  switch (label.trim().toUpperCase()) {
    case 'RX':
      return Icons.local_fire_department_rounded;
    case 'INTERMEDIATE':
    case 'LEVEL2':
      return Icons.trending_up_rounded;
    case 'SCALED':
    case 'LEVEL1':
      return Icons.accessibility_new_rounded;
    default:
      return Icons.tune_rounded;
  }
}

String _weekRangeLabel(DateTime monday) {
  final sunday = monday.add(Duration(days: 6));
  return '${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(sunday)}';
}

String _partCountLabel(BuildContext context, int count) =>
    '$count ${context.l10n.tr(count == 1 ? 'part' : 'parts')}';

String _partTitle(BuildContext context, int index) =>
    '${context.l10n.tr('Part')} ${_partLabel(index)}';

String _countLabel(
        BuildContext context, int count, String singular, String plural) =>
    '$count ${context.l10n.tr(count == 1 ? singular : plural)}';

void _openWodDetail(BuildContext context, WodEntry wod, WodService service) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => WodDetailScreen(wod: wod, service: service),
    ),
  );
}

// ── WodScreen (list) ─────────────────────────────────────────────────────────

class WodScreen extends StatefulWidget {
  const WodScreen({super.key, this.gymId = ''});
  final String gymId;

  @override
  State<WodScreen> createState() => _WodScreenState();
}

class _WodScreenState extends State<WodScreen> {
  late final _svc = WodService(gymId: widget.gymId);
  late final _classTypeSvc = ClassTypeService(gymId: widget.gymId);
  DateTime _selected = DateTime.now();
  String _selectedClassTypeId = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _WorkoutsHeader(
              dateLabel: DateFormat('EEEE, MMMM d').format(today),
              onProgressTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => WorkoutTrackerScreen(gymId: widget.gymId),
                ),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _DateRowDelegate(
              selected: _selected,
              onChanged: (d) => setState(() => _selected = d),
            ),
          ),
          SliverToBoxAdapter(
            child: StreamBuilder<List<ClassType>>(
              stream: _classTypeSvc.streamClassTypes(),
              builder: (context, snap) {
                final types = snap.data ?? [];
                if (types.isEmpty) return SizedBox.shrink();
                return _ClassTypeFilterRow(
                  classTypes: types,
                  selectedId: _selectedClassTypeId,
                  onChanged: (id) => setState(() => _selectedClassTypeId = id),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: StreamBuilder<List<WodEntry>>(
              stream: _svc.streamForDate(
                _selected,
                classTypeId: _selectedClassTypeId,
              ),
              builder: (context, snap) {
                Widget child;
                if (snap.connectionState == ConnectionState.waiting) {
                  child = _LoadingDeck(key: ValueKey('loading'));
                } else {
                  final wods = snap.data ?? [];
                  if (wods.isEmpty) {
                    child = _EmptyWod(
                      key: ValueKey('empty'),
                      date: _selected,
                    );
                  } else {
                    child = Column(
                      key: ValueKey('data'),
                      children: [
                        for (final wod in wods)
                          _WodSummaryCard(wod: wod, service: _svc),
                      ],
                    );
                  }
                }

                return _webCenter(
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: child,
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: StreamBuilder<List<WodEntry>>(
              stream: _svc.streamRecent(10),
              builder: (context, snap) {
                final recent = (snap.data ?? [])
                    .where((w) => !_sameDay(w.date, _selected))
                    .toList();
                if (recent.isEmpty) return SizedBox.shrink();
                return _webCenter(
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 28, 16, 0),
                    child: _HistorySection(
                      wods: recent,
                      service: _svc,
                      selected: _selected,
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ),
    );
  }
}

// ── WodDetailScreen ──────────────────────────────────────────────────────────

class WodDetailScreen extends StatefulWidget {
  const WodDetailScreen({
    super.key,
    required this.wod,
    required this.service,
  });

  final WodEntry wod;
  final WodService service;

  @override
  State<WodDetailScreen> createState() => _WodDetailScreenState();
}

class _WodDetailScreenState extends State<WodDetailScreen> {
  late final ScrollController _scrollController = ScrollController()
    ..addListener(_handleScroll);
  late final List<GlobalKey> _partKeys =
      List.generate(widget.wod.parts.length, (_) => GlobalKey());

  double _scrollOffset = 0;
  int _activePart = 0;

  WodEntry get wod => widget.wod;

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final next = _scrollController.offset;
    if ((next - _scrollOffset).abs() < 1) return;
    setState(() => _scrollOffset = next);
  }

  Future<void> _scrollToPart(int index) async {
    if (index < 0 || index >= _partKeys.length) return;
    final context = _partKeys[index].currentContext;
    if (context == null) return;
    setState(() => _activePart = index);
    await Scrollable.ensureVisible(
      context,
      duration: Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      alignment: 0.08,
    );
  }

  double _sidebarTop(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final pinnedTop = topInset +
        kToolbarHeight +
        (wod.parts.length > 1 ? _kPartNavHeight : 0) +
        16;
    final expandedTop = topInset + 240 - _scrollOffset + 16;
    return math.max(pinnedTop, expandedTop);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;
          if (!isWide) {
            return SelectionArea(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  _WodDetailAppBar(wod: wod),
                  if (wod.parts.length > 1)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedBoxDelegate(
                        height: _kPartNavHeight,
                        child: _PartNavigationBar(
                          partCount: wod.parts.length,
                          activeIndex: _activePart,
                          onTap: _scrollToPart,
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _webCenter(
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 64),
                        child: _NarrowDetailBody(
                          wod: wod,
                          service: widget.service,
                          uid: uid,
                          partKeys: _partKeys,
                        ),
                      ),
                      maxWidth: 920,
                    ),
                  ),
                ],
              ),
            );
          }

          const maxWidth = 1240.0;
          const sidebarWidth = 320.0;
          final centeredWidth = math.min(maxWidth, constraints.maxWidth);
          final horizontalPad = (constraints.maxWidth - centeredWidth) / 2;
          final sidebarTop = _sidebarTop(context);
          final availableHeight = constraints.maxHeight - sidebarTop - 16;

          return SelectionArea(
            child: Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    _WodDetailAppBar(wod: wod),
                    if (wod.parts.length > 1)
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _PinnedBoxDelegate(
                          height: _kPartNavHeight,
                          child: _PartNavigationBar(
                            partCount: wod.parts.length,
                            activeIndex: _activePart,
                            onTap: _scrollToPart,
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPad + 24,
                          24,
                          horizontalPad + sidebarWidth + 48,
                          72,
                        ),
                        child: _WideMainBody(
                          wod: wod,
                          partKeys: _partKeys,
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: sidebarTop,
                  right: horizontalPad + 24,
                  width: sidebarWidth,
                  child: SizedBox(
                    height: availableHeight > 240 ? availableHeight : 240,
                    child: _WideSidebar(
                      wod: wod,
                      service: widget.service,
                      uid: uid,
                      activePart: _activePart,
                      onPartTap: _scrollToPart,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Shared headers ───────────────────────────────────────────────────────────

// ── Static workout header (no expand animation) ───────────────────────────────

class _WorkoutsHeader extends StatelessWidget {
  const _WorkoutsHeader({
    required this.dateLabel,
    required this.onProgressTap,
  });

  final String dateLabel;
  final VoidCallback onProgressTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Decorative circles
          Positioned(
            top: -40,
            right: -20,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(16),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -36,
            left: -24,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.fromLTRB(
              isWide ? 32 : 20,
              topPad + 20,
              isWide ? 24 : 12,
              20,
            ),
            child: _webCenter(
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.tr('Workouts'),
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: isWide ? 36 : 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          context.l10n.tr('Training Schedule'),
                          style: TextStyle(
                            color: cs.onPrimary.withAlpha(210),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 12),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(28),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withAlpha(40),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 8),
                              Text(
                                dateLabel,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.tr('My Progress'),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withAlpha(28),
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(Icons.bar_chart_rounded),
                    onPressed: onProgressTap,
                  ),
                ],
              ),
              maxWidth: 880,
            ),
          ),
        ],
      ),
    );
  }
}

class _WodDetailAppBar extends StatelessWidget {
  const _WodDetailAppBar({required this.wod});
  final WodEntry wod;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      surfaceTintColor: Colors.transparent,
      leading: Padding(
        padding: EdgeInsets.all(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Navigator.pop(context),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(34),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: EdgeInsets.fromLTRB(56, 0, 16, 16),
        title: Hero(
          tag: 'wod_title_${wod.id}',
          child: Material(
            color: Colors.transparent,
            child: Text(
              wod.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                shadows: [
                  Shadow(
                    color: Colors.black45,
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
        background: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, Color(0xFFF97316)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: 24,
                top: 60,
                child: Icon(
                  Icons.fitness_center_rounded,
                  size: 120,
                  color: Colors.white.withAlpha(30),
                ),
              ),
              Positioned(
                right: -40,
                top: -30,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(14),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                left: -30,
                bottom: -26,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: 58,
                left: 16,
                right: 16,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderChip(
                      icon: Icons.calendar_today_rounded,
                      label: DateFormat('EEEE, MMM d').format(wod.date),
                    ),
                    if (wod.classTypeName.isNotEmpty)
                      _HeaderChip(
                        icon: Icons.category_rounded,
                        label: wod.classTypeName,
                      ),
                    if (wod.parts.isNotEmpty)
                      _HeaderChip(
                        icon: Icons.segment_rounded,
                        label: _partCountLabel(context, wod.parts.length),
                      ),
                    if (wod.parts.isEmpty && wod.format.isNotEmpty)
                      _HeaderChip(
                        icon: _kFormatIcons[wod.format] ??
                            Icons.fitness_center_rounded,
                        label: wod.format,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(28),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withAlpha(55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Date row / filters ───────────────────────────────────────────────────────

class _DateRow extends StatefulWidget {
  const _DateRow({required this.selected, required this.onChanged});
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_DateRow> createState() => _DateRowState();
}

class _DateRowState extends State<_DateRow> {
  int _weekOffset = 0;

  List<DateTime> get _days {
    final monday =
        _mondayOf(DateTime.now()).add(Duration(days: 7 * _weekOffset));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  String _headline(BuildContext context) {
    if (_weekOffset == 0) return context.l10n.tr('This Week');
    if (_weekOffset == -1) return context.l10n.tr('Last Week');
    return DateFormat('MMMM yyyy').format(_days.first);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final days = _days;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 700;
    // On wide screens, fit all 7 days without scrolling
    final dayItemWidth = isWide
        ? ((screenWidth.clamp(0.0, 880.0) - 28 - 6 * 10) / 7).clamp(56.0, 110.0)
        : 56.0;

    return Material(
      color: cs.surface,
      child: Column(
        children: [
          Padding(
            padding:
                EdgeInsets.fromLTRB(isWide ? 24 : 12, 12, isWide ? 24 : 12, 6),
            child: _webCenter(
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => setState(() => _weekOffset--),
                    icon: Icon(Icons.chevron_left_rounded),
                    tooltip: context.l10n.tr('Previous week'),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _headline(context),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          _weekRangeLabel(days.first),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  IconButton.filledTonal(
                    onPressed: _weekOffset >= 0
                        ? null
                        : () => setState(() => _weekOffset++),
                    icon: Icon(Icons.chevron_right_rounded),
                    tooltip: context.l10n.tr('Next week'),
                  ),
                ],
              ),
              maxWidth: 880,
            ),
          ),
          SizedBox(
            height: 92,
            child: isWide
                ? _webCenter(
                    Padding(
                      padding: EdgeInsets.fromLTRB(14, 6, 14, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          days.length,
                          (index) => _DayChip(
                            day: days[index],
                            today: today,
                            selected: widget.selected,
                            width: dayItemWidth,
                            onTap: widget.onChanged,
                          ),
                        ),
                      ),
                    ),
                    maxWidth: 880,
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(14, 6, 14, 10),
                    itemCount: days.length,
                    itemBuilder: (context, index) => Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: _DayChip(
                        day: days[index],
                        today: today,
                        selected: widget.selected,
                        width: 56,
                        onTap: widget.onChanged,
                      ),
                    ),
                  ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withAlpha(70),
          ),
        ],
      ),
    );
  }
}

// ── Day chip widget ───────────────────────────────────────────────────────────

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.today,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final DateTime day;
  final DateTime today;
  final DateTime selected;
  final double width;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _sameDay(day, selected);
    final isToday = _sameDay(day, today);
    final isFuture = day.isAfter(DateTime(today.year, today.month, today.day));

    return InkWell(
      onTap: () => onTap(day),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: width,
        height: 72,
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [cs.primary, Color(0xFFF97316)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected
              ? null
              : isToday
                  ? cs.primaryContainer.withAlpha(130)
                  : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : isToday
                    ? cs.primary.withAlpha(80)
                    : cs.outlineVariant.withAlpha(110),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withAlpha(35),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: isFuture && !isSelected ? 0.58 : 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('EEE').format(day).toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? cs.onPrimary : cs.onSurface,
                ),
              ),
              SizedBox(height: 4),
              Text(
                isToday ? context.l10n.tr('TODAY') : ' ',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? cs.onPrimary.withAlpha(215) : cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pinned date-row delegate ──────────────────────────────────────────────────

class _DateRowDelegate extends SliverPersistentHeaderDelegate {
  _DateRowDelegate({
    required this.selected,
    required this.onChanged,
  });

  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  // _DateRow height: top-padding row (~66) + day list (92) + divider (1) ≈ 159
  static final double _height = 160;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      _DateRow(selected: selected, onChanged: onChanged);

  @override
  bool shouldRebuild(_DateRowDelegate old) =>
      selected != old.selected || onChanged != old.onChanged;
}

class _ClassTypeFilterRow extends StatelessWidget {
  const _ClassTypeFilterRow({
    required this.classTypes,
    required this.selectedId,
    required this.onChanged,
  });

  final List<ClassType> classTypes;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  context.l10n.tr('All'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selectedId.isEmpty ? cs.onPrimary : cs.onSurface,
                  ),
                ),
                selected: selectedId.isEmpty,
                onSelected: (_) => onChanged(''),
                showCheckmark: false,
                backgroundColor: cs.surfaceContainerHigh,
                selectedColor: cs.primary,
                shape: StadiumBorder(
                  side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
                ),
              ),
            ),
            ...classTypes.map((type) {
              final color = _classTypeColor(type, cs);
              final selected = selectedId == type.id;
              return Padding(
                padding: EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  showCheckmark: false,
                  selected: selected,
                  onSelected: (_) => onChanged(selected ? '' : type.id),
                  selectedColor: color.withAlpha(40),
                  backgroundColor: cs.surfaceContainerHigh,
                  side: BorderSide(
                    color: selected ? color.withAlpha(120) : cs.outlineVariant,
                  ),
                  shape: StadiumBorder(),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        type.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected ? color : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── WOD list widgets ─────────────────────────────────────────────────────────

class _LoadingDeck extends StatelessWidget {
  const _LoadingDeck({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(
        2,
        (index) => Card(
          margin: EdgeInsets.only(bottom: index == 1 ? 0 : 14),
          elevation: 0,
          shape: _cardShape(context),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  height: 18,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  height: 12,
                  width: 220,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                SizedBox(height: 18),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
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

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.wods,
    required this.service,
    required this.selected,
  });

  final List<WodEntry> wods;
  final WodService service;
  final DateTime selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, color: cs.onSurface, size: 20),
            SizedBox(width: 8),
            Text(
              context.l10n.tr('History'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        SizedBox(height: 14),
        Card(
          elevation: 0,
          shape: _cardShape(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < wods.length; i++) ...[
                _RecentWodRow(
                  wod: wods[i],
                  isSelected: _sameDay(wods[i].date, selected),
                  service: service,
                  onTap: () => _openWodDetail(context, wods[i], service),
                ),
                if (i != wods.length - 1)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: cs.outlineVariant.withAlpha(80),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WodSummaryCard extends StatelessWidget {
  const _WodSummaryCard({required this.wod, required this.service});
  final WodEntry wod;
  final WodService service;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final accent = _kPartAccents[0];
    final firstPart = wod.parts.isNotEmpty ? wod.parts.first : null;
    final preview = firstPart == null
        ? ''
        : [firstPart.format, firstPart.title]
            .where((part) => part.trim().isNotEmpty)
            .join(' • ');

    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black.withAlpha(18),
        shape: _cardShape(context),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openWodDetail(context, wod, service),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withAlpha(8),
                        Colors.white,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -22,
                right: -18,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withAlpha(12),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: Container(width: 4, color: accent),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Hero(
                                tag: 'wod_title_${wod.id}',
                                child: Material(
                                  color: Colors.transparent,
                                  child: Text(
                                    wod.title,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: cs.onSurface,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (wod.classTypeName.isNotEmpty)
                                    _Badge(
                                      label: wod.classTypeName,
                                      bg: cs.secondaryContainer,
                                      fg: cs.onSecondaryContainer,
                                    ),
                                  if (wod.parts.isNotEmpty)
                                    _Badge(
                                      label:
                                          '${wod.parts.length} part${wod.parts.length == 1 ? '' : 's'}',
                                      bg: accent.withAlpha(20),
                                      fg: accent,
                                    ),
                                  if (firstPart != null &&
                                      firstPart.format.isNotEmpty)
                                    _Badge(
                                      icon: _kFormatIcons[firstPart.format],
                                      label: firstPart.format,
                                      bg: cs.tertiaryContainer,
                                      fg: cs.onTertiaryContainer,
                                    ),
                                  if (wod.parts.isEmpty &&
                                      wod.format.isNotEmpty)
                                    _Badge(
                                      icon: _kFormatIcons[wod.format],
                                      label: wod.format,
                                      bg: cs.tertiaryContainer,
                                      fg: cs.onTertiaryContainer,
                                    ),
                                  if (wod.timeCap.isNotEmpty)
                                    _Badge(
                                      icon: Icons.timer_outlined,
                                      label: wod.timeCap,
                                      bg: cs.surfaceContainerHighest,
                                      fg: cs.onSurfaceVariant,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12),
                        StreamBuilder<WodScore?>(
                          stream: service.streamMyScore(wod.id, uid),
                          builder: (context, snap) {
                            final logged = snap.data != null;
                            return _ScorePill(logged: logged);
                          },
                        ),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      SizedBox(height: 16),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surface.withAlpha(220),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outlineVariant.withAlpha(70),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.bolt_rounded, color: accent, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                preview,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _openWodDetail(context, wod, service),
                        icon: Icon(Icons.arrow_forward_rounded),
                        label: Text(context.l10n.tr('Open Workout')),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.logged});
  final bool logged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = logged ? Color(0xFF059669) : cs.primary;
    return AnimatedContainer(
      duration: Duration(milliseconds: 260),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            logged ? Icons.check_circle_rounded : Icons.edit_rounded,
            size: 16,
            color: color,
          ),
          SizedBox(width: 6),
          Text(
            context.l10n.tr(logged ? 'Logged' : 'Log'),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentWodRow extends StatelessWidget {
  const _RecentWodRow({
    required this.wod,
    required this.isSelected,
    required this.service,
    required this.onTap,
  });

  final WodEntry wod;
  final bool isSelected;
  final WodService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 58,
              padding: EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('MMM').format(wod.date).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${wod.date.day}',
                    style: TextStyle(
                      fontSize: 20,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'wod_title_${wod.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        wod.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE, MMM d').format(wod.date),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (wod.classTypeName.isNotEmpty)
                        _Badge(
                          label: wod.classTypeName,
                          bg: cs.secondaryContainer,
                          fg: cs.onSecondaryContainer,
                        ),
                      if (wod.parts.isNotEmpty)
                        _Badge(
                          label:
                              '${wod.parts.length} part${wod.parts.length == 1 ? '' : 's'}',
                          bg: cs.surfaceContainerHighest,
                          fg: cs.onSurfaceVariant,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            StreamBuilder<WodScore?>(
              stream: service.streamMyScore(wod.id, uid),
              builder: (context, snap) {
                final hasScore = snap.data != null;
                return Column(
                  children: [
                    Icon(
                      hasScore
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: hasScore
                          ? Color(0xFF059669)
                          : cs.onSurfaceVariant.withAlpha(140),
                    ),
                    SizedBox(height: 4),
                    Text(
                      hasScore ? '✓' : '○',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color:
                            hasScore ? Color(0xFF059669) : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWod extends StatelessWidget {
  const _EmptyWod({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: _cardShape(context),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fitness_center_rounded,
                size: 36,
                color: cs.onSurfaceVariant.withAlpha(160),
              ),
            ),
            SizedBox(height: 20),
            Text(
              context.l10n.tr('No workout posted'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '${context.l10n.tr('Nothing scheduled for')} ${DateFormat('EEEE, MMMM d').format(date)}.\n${context.l10n.tr('Rest up — something strong is coming.')}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail layouts ───────────────────────────────────────────────────────────

class _NarrowDetailBody extends StatelessWidget {
  const _NarrowDetailBody({
    required this.wod,
    required this.service,
    required this.uid,
    required this.partKeys,
  });

  final WodEntry wod;
  final WodService service;
  final String uid;
  final List<GlobalKey> partKeys;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailContentColumn(wod: wod, partKeys: partKeys),
        SizedBox(height: 18),
        if (wod.memberNote.isNotEmpty) ...[
          _StimulusCard(note: wod.memberNote),
          SizedBox(height: 18),
        ],
        if (wod.createdBy.isNotEmpty) ...[
          _CoachCard(coachId: wod.createdBy),
          SizedBox(height: 18),
        ],
        StreamBuilder<WodScore?>(
          stream: service.streamMyScore(wod.id, uid),
          builder: (context, snap) => _ScoreSection(
            wod: wod,
            myScore: snap.data,
            userId: uid,
            service: service,
          ),
        ),
      ],
    );
  }
}

class _WideMainBody extends StatelessWidget {
  const _WideMainBody({required this.wod, required this.partKeys});

  final WodEntry wod;
  final List<GlobalKey> partKeys;

  @override
  Widget build(BuildContext context) {
    return _DetailContentColumn(wod: wod, partKeys: partKeys);
  }
}

class _WideSidebar extends StatelessWidget {
  const _WideSidebar({
    required this.wod,
    required this.service,
    required this.uid,
    required this.activePart,
    required this.onPartTap,
  });

  final WodEntry wod;
  final WodService service;
  final String uid;
  final int activePart;
  final ValueChanged<int> onPartTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wod.parts.length > 1) ...[
            _SidebarPartNavigator(
              count: wod.parts.length,
              activePart: activePart,
              onTap: onPartTap,
            ),
            SizedBox(height: 16),
          ],
          if (wod.memberNote.isNotEmpty) ...[
            _StimulusCard(note: wod.memberNote),
            SizedBox(height: 16),
          ],
          if (wod.createdBy.isNotEmpty) ...[
            _CoachCard(coachId: wod.createdBy),
            SizedBox(height: 16),
          ],
          StreamBuilder<WodScore?>(
            stream: service.streamMyScore(wod.id, uid),
            builder: (context, snap) => _ScoreSection(
              wod: wod,
              myScore: snap.data,
              userId: uid,
              service: service,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailContentColumn extends StatelessWidget {
  const _DetailContentColumn({required this.wod, required this.partKeys});

  final WodEntry wod;
  final List<GlobalKey> partKeys;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (wod.parts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wod.description.isNotEmpty) ...[
            _DescriptionBox(
              title: wod.format.isNotEmpty
                  ? wod.format
                  : context.l10n.tr('Workout Details'),
              text: wod.description,
              accent: cs.primary,
            ),
            SizedBox(height: 16),
          ],
          if (wod.exercises.isNotEmpty)
            Card(
              elevation: 0,
              shape: _cardShape(context),
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tr('Workout Flow'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    SizedBox(height: 14),
                    for (final entry in wod.exercises.asMap().entries)
                      _ExerciseTile(
                        index: entry.key + 1,
                        exercise: entry.value,
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in wod.parts.asMap().entries)
          Padding(
            key: partKeys[entry.key],
            padding: EdgeInsets.only(bottom: 16),
            child: _PartDetailCard(part: entry.value, index: entry.key),
          ),
      ],
    );
  }
}

class _PartNavigationBar extends StatelessWidget {
  const _PartNavigationBar({
    required this.partCount,
    required this.activeIndex,
    required this.onTap,
  });

  final int partCount;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface.withAlpha(248),
      padding: EdgeInsets.symmetric(vertical: 10),
      child: _webCenter(
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final accent = _kPartAccents[index % _kPartAccents.length];
              final selected = index == activeIndex;
              return FilterChip(
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => onTap(index),
                backgroundColor: accent.withAlpha(10),
                selectedColor: accent.withAlpha(24),
                side: BorderSide(color: accent.withAlpha(selected ? 180 : 90)),
                shape: StadiumBorder(),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      _partTitle(context, index),
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            },
            separatorBuilder: (_, __) => SizedBox(width: 8),
            itemCount: partCount,
          ),
        ),
        maxWidth: 1240,
      ),
    );
  }
}

class _SidebarPartNavigator extends StatelessWidget {
  const _SidebarPartNavigator({
    required this.count,
    required this.activePart,
    required this.onTap,
  });

  final int count;
  final int activePart;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: _cardShape(context),
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.tr('Part Navigator'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            SizedBox(height: 14),
            for (var i = 0; i < count; i++) ...[
              _SidebarPartButton(
                label: _partLabel(i),
                accent: _kPartAccents[i % _kPartAccents.length],
                selected: i == activePart,
                onTap: () => onTap(i),
              ),
              if (i != count - 1) SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarPartButton extends StatelessWidget {
  const _SidebarPartButton({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 220),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(16) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent.withAlpha(150) : cs.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '${context.l10n.tr('Part')} $label',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? accent : cs.onSurface,
                ),
              ),
            ),
            Icon(Icons.arrow_downward_rounded, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

class _PinnedBoxDelegate extends SliverPersistentHeaderDelegate {
  _PinnedBoxDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Colors.transparent,
      elevation: overlapsContent ? 1 : 0,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedBoxDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

// ── Part detail card ─────────────────────────────────────────────────────────

class _PartDetailCard extends StatefulWidget {
  const _PartDetailCard({required this.part, required this.index});

  final WodPart part;
  final int index;

  @override
  State<_PartDetailCard> createState() => _PartDetailCardState();
}

class _PartDetailCardState extends State<_PartDetailCard> {
  int _selectedScale = 0;

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    final cs = Theme.of(context).colorScheme;
    final accent = _kPartAccents[widget.index % _kPartAccents.length];
    final countLabel = part.scales.isNotEmpty
        ? _countLabel(context, part.scales.length, 'scale', 'scales')
        : _countLabel(context, part.exercises.length, 'exercise', 'exercises');

    return Card(
      elevation: 0,
      shape: _cardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 3, color: accent),
          Container(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withAlpha(26), accent.withAlpha(8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withAlpha(45),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _partLabel(widget.index),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        part.title,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (part.format.isNotEmpty)
                            _Badge(
                              icon: _kFormatIcons[part.format],
                              label: part.format,
                              bg: accent.withAlpha(20),
                              fg: accent,
                            ),
                          if (part.measure.isNotEmpty)
                            _Badge(
                              label: part.measure,
                              bg: cs.secondaryContainer,
                              fg: cs.onSecondaryContainer,
                            ),
                          if (part.timeCap.isNotEmpty)
                            _Badge(
                              icon: Icons.timer_outlined,
                              label: part.timeCap,
                              bg: cs.surfaceContainerHighest,
                              fg: cs.onSurfaceVariant,
                            ),
                          _Badge(
                            icon: part.scales.isNotEmpty
                                ? Icons.layers_rounded
                                : Icons.format_list_numbered_rounded,
                            label: countLabel,
                            bg: Colors.white.withAlpha(140),
                            fg: accent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (part.description.isNotEmpty) ...[
                  _DescriptionBox(
                    title:
                        '${_partTitle(context, widget.index)} ${context.l10n.tr('Notes')}',
                    text: part.description,
                    accent: accent,
                  ),
                  SizedBox(height: 14),
                ],
                if (part.scales.isNotEmpty) ...[
                  _ScaleTabSelector(
                    scales: part.scales,
                    selectedIndex: _selectedScale,
                    accent: accent,
                    onChanged: (index) =>
                        setState(() => _selectedScale = index),
                  ),
                  SizedBox(height: 14),
                  _ScaleContent(
                    scale: part.scales[
                        _selectedScale.clamp(0, part.scales.length - 1)],
                    accent: accent,
                  ),
                ] else ...[
                  for (final entry in part.exercises.asMap().entries)
                    _ExerciseTile(
                      index: entry.key + 1,
                      exercise: entry.value,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScaleTabSelector extends StatelessWidget {
  const _ScaleTabSelector({
    required this.scales,
    required this.selectedIndex,
    required this.accent,
    required this.onChanged,
  });

  final List<WodScale> scales;
  final int selectedIndex;
  final Color accent;
  final ValueChanged<int> onChanged;

  Color _selectedBg(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    switch (label.trim().toUpperCase()) {
      case 'RX':
        return cs.primary;
      case 'INTERMEDIATE':
      case 'LEVEL2':
        return cs.secondary;
      case 'SCALED':
      case 'LEVEL1':
        return cs.tertiary;
      default:
        return accent;
    }
  }

  Color _selectedFg(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    switch (label.trim().toUpperCase()) {
      case 'RX':
        return cs.onPrimary;
      case 'INTERMEDIATE':
      case 'LEVEL2':
        return cs.onSecondary;
      case 'SCALED':
      case 'LEVEL1':
        return cs.onTertiary;
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(170),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withAlpha(110)),
      ),
      child: Row(
        children: scales.asMap().entries.map((entry) {
          final index = entry.key;
          final scale = entry.value;
          final selected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 220),
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? _selectedBg(context, scale.label)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _scaleIcon(scale.label),
                      size: 16,
                      color: selected
                          ? _selectedFg(context, scale.label)
                          : cs.onSurfaceVariant,
                    ),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        scale.label,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? _selectedFg(context, scale.label)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ScaleContent extends StatelessWidget {
  const _ScaleContent({required this.scale, required this.accent});

  final WodScale scale;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      child: Column(
        key: ValueKey(scale.label),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scale.description.isNotEmpty) ...[
            _DescriptionBox(
              title: scale.label,
              text: scale.description,
              accent: accent,
            ),
            if (scale.exercises.isNotEmpty) SizedBox(height: 12),
          ],
          for (final entry in scale.exercises.asMap().entries)
            _ExerciseTile(index: entry.key + 1, exercise: entry.value),
        ],
      ),
    );
  }
}

// ── Rich text / descriptions ────────────────────────────────────────────────

class _DescriptionBox extends StatelessWidget {
  const _DescriptionBox({
    required this.title,
    required this.text,
    required this.accent,
  });

  final String title;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final lines = text
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final minuteLines = lines.where(_isMinuteLine).toList();
    final regularLines = lines.where((line) => !_isMinuteLine(line)).toList();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withAlpha(55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          if (regularLines.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < regularLines.length; i++) ...[
                  _HighlightedText(line: regularLines[i], accent: accent),
                  if (i != regularLines.length - 1) SizedBox(height: 8),
                ],
              ],
            ),
          if (minuteLines.isNotEmpty) ...[
            if (regularLines.isNotEmpty) SizedBox(height: 10),
            for (var i = 0; i < minuteLines.length; i++) ...[
              _MinuteLine(line: minuteLines[i], accent: accent),
              if (i != minuteLines.length - 1) SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

bool _isMinuteLine(String line) =>
    RegExp(r'^\s*Min\s*\d+\s*:', caseSensitive: false).hasMatch(line) ||
    RegExp(r'^\s*Min\d+\s*:', caseSensitive: false).hasMatch(line);

class _MinuteLine extends StatelessWidget {
  const _MinuteLine({required this.line, required this.accent});

  final String line;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'^\s*Min\s*(\d+)\s*:\s*(.*)$', caseSensitive: false)
            .firstMatch(line) ??
        RegExp(r'^\s*Min(\d+)\s*:\s*(.*)$', caseSensitive: false)
            .firstMatch(line);
    final minute = match?.group(1) ?? '';
    final detail = match?.group(2) ?? line;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Min $minute',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(child: _HighlightedText(line: detail, accent: accent)),
      ],
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.line, required this.accent});

  final String line;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final matches = RegExp(r'\b\d+(?:-\d+){1,}\b').allMatches(line).toList();
    if (matches.isEmpty) {
      return Text(
        line,
        style: TextStyle(
          fontSize: 14,
          height: 1.7,
          color: cs.onSurfaceVariant,
        ),
      );
    }

    final spans = <TextSpan>[];
    var current = 0;
    for (final match in matches) {
      if (match.start > current) {
        spans.add(TextSpan(text: line.substring(current, match.start)));
      }
      spans.add(
        TextSpan(
          text: line.substring(match.start, match.end),
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
      current = match.end;
    }
    if (current < line.length) {
      spans.add(TextSpan(text: line.substring(current)));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(
        fontSize: 14,
        height: 1.7,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

// ── Stimulus / supporting cards ──────────────────────────────────────────────

class _StimulusCard extends StatefulWidget {
  const _StimulusCard({required this.note});
  final String note;

  @override
  State<_StimulusCard> createState() => _StimulusCardState();
}

class _StimulusCardState extends State<_StimulusCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paragraphs = widget.note
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final cs = Theme.of(context).colorScheme;
    const accent = Color(0xFFF59E0B);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = 8 + (_controller.value * 10);
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: accent.withAlpha(16),
                blurRadius: glow,
                spreadRadius: 0.5,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Card(
        elevation: 0,
        shape: _cardShape(context),
        color: accent.withAlpha(10),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('💡', style: TextStyle(fontSize: 22)),
                  SizedBox(width: 10),
                  Text(
                    context.l10n.tr('Stimulus'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              for (var i = 0; i < paragraphs.length; i++) ...[
                if (paragraphs.length > 1)
                  Text(
                    '${context.l10n.tr('Focus')} ${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB45309),
                    ),
                  ),
                if (paragraphs.length > 1) SizedBox(height: 6),
                Text(
                  paragraphs[i],
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (i != paragraphs.length - 1)
                  Divider(
                    height: 24,
                    color: accent.withAlpha(60),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachCard extends StatefulWidget {
  const _CoachCard({required this.coachId});
  final String coachId;

  @override
  State<_CoachCard> createState() => _CoachCardState();
}

class _CoachCardState extends State<_CoachCard> {
  final _memberService = MemberService();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<AppUser?>(
      stream: _memberService.streamUser(widget.coachId),
      builder: (context, snap) {
        final coach = snap.data;
        if (coach == null) return SizedBox.shrink();
        final name =
            coach.displayName.isNotEmpty ? coach.displayName : coach.email;
        final initials = name
            .trim()
            .split(' ')
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();

        return Card(
          elevation: 0,
          shape: _cardShape(context),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                UserAvatar(
                  photoUrl: coach.photoUrl,
                  initials: initials,
                  color: cs.primary,
                  radius: 24,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.tr('Posted by'),
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      if (coach.fitnessLevel.isNotEmpty) ...[
                        SizedBox(height: 3),
                        Text(
                          coach.fitnessLevel,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.l10n.tr('Coach'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
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

// ── Score section ────────────────────────────────────────────────────────────

class _ScoreSection extends StatefulWidget {
  const _ScoreSection({
    required this.wod,
    required this.myScore,
    required this.userId,
    required this.service,
  });

  final WodEntry wod;
  final WodScore? myScore;
  final String userId;
  final WodService service;

  @override
  State<_ScoreSection> createState() => _ScoreSectionState();
}

class _ScoreSectionState extends State<_ScoreSection> {
  final _scoreCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _editing = false;
  bool _saving = false;
  bool _personalRecord = false;

  @override
  void initState() {
    super.initState();
    _scoreCtrl.text = widget.myScore?.score ?? '';
    _notesCtrl.text = widget.myScore?.notes ?? '';
  }

  @override
  void didUpdateWidget(covariant _ScoreSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myScore != widget.myScore && !_editing) {
      _scoreCtrl.text = widget.myScore?.score ?? '';
      _notesCtrl.text = widget.myScore?.notes ?? '';
    }
  }

  @override
  void dispose() {
    _scoreCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.saveScore(
        WodScore(
          id: widget.myScore?.id ?? '',
          wodId: widget.wod.id,
          userId: widget.userId,
          score: _scoreCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
        ),
      );
      if (mounted) setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasScore = widget.myScore != null;
    final borderColor = hasScore ? cs.primary.withAlpha(90) : cs.outlineVariant;

    return Card(
      elevation: 0,
      shape: _cardShape(context),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasScore
                      ? Icons.emoji_events_rounded
                      : Icons.sports_score_rounded,
                  color: hasScore ? Color(0xFFF59E0B) : cs.primary,
                  size: 24,
                ),
                SizedBox(width: 10),
                Text(
                  context.l10n.tr('My Score'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                Spacer(),
                if (!_editing && hasScore)
                  IconButton.filledTonal(
                    onPressed: () {
                      _scoreCtrl.text = widget.myScore?.score ?? '';
                      _notesCtrl.text = widget.myScore?.notes ?? '';
                      setState(() => _editing = true);
                    },
                    icon: Icon(Icons.edit_rounded),
                    tooltip: context.l10n.tr('Edit score'),
                  ),
              ],
            ),
            SizedBox(height: 16),
            AnimatedSwitcher(
              duration: Duration(milliseconds: 260),
              child: _editing
                  ? Container(
                      key: ValueKey('score-editing'),
                      padding: EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                        color: cs.surfaceContainerLowest,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _scoreCtrl,
                            decoration: InputDecoration(
                              labelText: context.l10n
                                  .tr('Score (e.g. 12:34, 95 reps)'),
                              prefixIcon: Icon(Icons.timer_outlined),
                            ),
                          ),
                          SizedBox(height: 12),
                          TextField(
                            controller: _notesCtrl,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: context.l10n.tr('Notes (optional)'),
                              prefixIcon: Icon(Icons.notes_rounded),
                            ),
                          ),
                          SizedBox(height: 12),
                          FilterChip(
                            selected: _personalRecord,
                            showCheckmark: false,
                            avatar: Icon(
                              Icons.bolt_rounded,
                              size: 16,
                              color: _personalRecord
                                  ? cs.onSecondaryContainer
                                  : cs.onSurfaceVariant,
                            ),
                            label: Text(context.l10n.tr('Personal Record')),
                            onSelected: (value) =>
                                setState(() => _personalRecord = value),
                          ),
                          SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _editing = false),
                                child: Text(context.l10n.tr('Cancel')),
                              ),
                              SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(Icons.check_rounded),
                                label: Text(context.l10n.tr('Save Score')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : hasScore
                      ? Container(
                          key: ValueKey('score-display'),
                          width: double.infinity,
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor),
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFFF59E0B).withAlpha(16),
                                cs.primary.withAlpha(10),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: Color(0xFFF59E0B).withAlpha(20),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      Icons.emoji_events_rounded,
                                      color: Color(0xFFF59E0B),
                                      size: 28,
                                    ),
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.myScore!.score,
                                          style: TextStyle(
                                            fontSize: 32,
                                            height: 1,
                                            fontWeight: FontWeight.w900,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          widget.myScore!.loggedAt != null
                                              ? '${context.l10n.tr('Logged')} ${DateFormat('MMM d, yyyy • h:mm a').format(widget.myScore!.loggedAt!)}'
                                              : context.l10n
                                                  .tr('Logged recently'),
                                          style: TextStyle(
                                            color: cs.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.myScore!.notes.isNotEmpty) ...[
                                SizedBox(height: 14),
                                Text(
                                  widget.myScore!.notes,
                                  style: TextStyle(
                                    height: 1.6,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              SizedBox(height: 14),
                              FilterChip(
                                selected: _personalRecord,
                                showCheckmark: false,
                                avatar: Icon(
                                  Icons.bolt_rounded,
                                  size: 16,
                                  color: _personalRecord
                                      ? cs.onSecondaryContainer
                                      : cs.onSurfaceVariant,
                                ),
                                label: Text(context.l10n.tr('Personal Record')),
                                onSelected: (value) =>
                                    setState(() => _personalRecord = value),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          key: ValueKey('score-empty'),
                          width: double.infinity,
                          padding: EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor),
                            color: cs.surfaceContainerLowest,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.sports_score_rounded,
                                size: 44,
                                color: cs.primary,
                              ),
                              SizedBox(height: 12),
                              Text(
                                context.l10n.tr('No score yet — be the first!'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                context.l10n.tr(
                                    'Track your result and build your training history.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                              SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      setState(() => _editing = true),
                                  icon: Icon(Icons.add_rounded),
                                  label: Text(context.l10n.tr('Log My Score')),
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Common UI atoms ──────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.bg,
    required this.fg,
    this.icon,
  });

  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.index, required this.exercise});

  final int index;
  final WodExercise exercise;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final detailParts = [
      if (exercise.sets.isNotEmpty) '${exercise.sets} sets',
      if (exercise.reps.isNotEmpty) '${exercise.reps} reps',
      if (exercise.weight.isNotEmpty) exercise.weight,
    ];

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(150),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withAlpha(110)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.primary,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                if (detailParts.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    detailParts.join(' • '),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ] else if (exercise.shortLabel.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    exercise.shortLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (exercise.notes.isNotEmpty) ...[
                  SizedBox(height: 6),
                  Text(
                    exercise.notes,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
