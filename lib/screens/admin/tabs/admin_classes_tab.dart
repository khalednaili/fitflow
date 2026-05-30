import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import 'package:fit_flow/utils/crash_logger.dart';
import '../../../models/app_user.dart';
import '../../../models/class_type.dart';
import '../../../models/gym_class.dart';
import '../../../models/membership_plan.dart';
import '../../../services/booking_service.dart';
import '../../../services/class_service.dart';
import '../../../services/class_type_service.dart';
import '../../../services/member_service.dart';
import '../../../services/subscription_service.dart';
import '../../../widgets/user_avatar.dart';
import '../manage_class_types_screen.dart';
import '../select_coaches_screen.dart';

/// Shows the Force Reservation dialog for [gymClass].
/// Accessible from both the classes list and the calendar.
Future<void> showForceReservationDialog(
  BuildContext context, {
  required GymClass gymClass,
  required String gymId,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ForceReservationDialog(gymClass: gymClass, gymId: gymId),
  );
}

Future<void> showClassEditorDialog(
  BuildContext context, {
  required String gymId,
  GymClass? existing,
  DateTime? initialStartDateTime,
  DateTime? initialEndDateTime,
  bool forceSingleClass = false,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ClassEditorDialog(
      gymId: gymId,
      existing: existing,
      initialStartDateTime: initialStartDateTime,
      initialEndDateTime: initialEndDateTime,
      forceSingleClass: forceSingleClass,
    ),
  );
}

enum _EditScope { thisOnly, thisAndFollowing, allInSeries }

class AdminClassesTab extends StatefulWidget {
  const AdminClassesTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminClassesTab> createState() => _AdminClassesTabState();
}

class _AdminClassesTabState extends State<AdminClassesTab> {
  late final _classService = ClassService(gymId: widget.gymId);
  final _searchController = TextEditingController();
  String _search = '';
  // 0=All, 1=Today, 2=Tomorrow, 3=This Week
  int _filter = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GymClass> _applyFilters(List<GymClass> all) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final weekEnd = todayStart.add(const Duration(days: 7));

    var filtered = all;

    // Date filter
    switch (_filter) {
      case 1: // Today
        filtered = filtered
            .where((c) =>
                !c.startTime.isBefore(todayStart) &&
                c.startTime.isBefore(tomorrowStart))
            .toList();
      case 2: // Tomorrow
        filtered = filtered
            .where((c) =>
                !c.startTime.isBefore(tomorrowStart) &&
                c.startTime
                    .isBefore(tomorrowStart.add(const Duration(days: 1))))
            .toList();
      case 3: // This Week
        filtered = filtered
            .where((c) =>
                !c.startTime.isBefore(todayStart) &&
                c.startTime.isBefore(weekEnd))
            .toList();
    }

    // Search filter
    final q = _search.toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered
          .where((c) =>
              c.title.toLowerCase().contains(q) ||
              c.coachNames.any((n) => n.toLowerCase().contains(q)) ||
              c.coachName.toLowerCase().contains(q))
          .toList();
    }

    return filtered;
  }

  // Group classes by date label
  Map<String, List<GymClass>> _groupByDate(List<GymClass> classes) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    final grouped = <String, List<GymClass>>{};
    for (final c in classes) {
      final d = c.startTime;
      final dayKey = DateTime(d.year, d.month, d.day);
      String label;
      if (!dayKey.isBefore(todayStart) && dayKey.isBefore(tomorrowStart)) {
        label = context.l10n.tr('Today');
      } else if (!dayKey.isBefore(tomorrowStart) &&
          dayKey.isBefore(tomorrowStart.add(const Duration(days: 1)))) {
        label = context.l10n.tr('Tomorrow');
      } else {
        label = DateFormat('EEEE, d MMMM').format(d);
      }
      grouped.putIfAbsent(label, () => []).add(c);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 800;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: Column(
        children: [
          _ClassesHeader(
            controller: _searchController,
            filter: _filter,
            onSearch: (v) => setState(() => _search = v),
            onFilter: (i) => setState(() => _filter = i),
            isWide: isWide,
            onCreateClass: () => _openClassForm(context),
            onManageTypes: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ManageClassTypesScreen(gymId: widget.gymId),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<GymClass>>(
              stream: _classService.streamAllClasses(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snapshot.data ?? <GymClass>[];
                final filtered = _applyFilters(all);

                if (all.isEmpty) {
                  return _EmptyState(
                    icon: Icons.fitness_center_outlined,
                    title: context.l10n.tr('No classes yet'),
                    subtitle: context.l10n
                        .tr('Tap "Create Class" to schedule your first session.'),
                  );
                }

                if (filtered.isEmpty) {
                  return _EmptyState(
                    icon: Icons.search_off_rounded,
                    title: context.l10n.tr('No matching classes'),
                    subtitle: context.l10n.tr('Try a different search or filter.'),
                    actionLabel: context.l10n.tr('Clear filters'),
                    onAction: () => setState(() {
                      _filter = 0;
                      _search = '';
                      _searchController.clear();
                    }),
                  );
                }

                final now = DateTime.now();
                final todayStart = DateTime(now.year, now.month, now.day);
                final todayClasses = all.where((c) {
                  final d = c.startTime;
                  return d.year == now.year &&
                      d.month == now.month &&
                      d.day == now.day;
                }).toList();
                final totalBooked =
                    todayClasses.fold(0, (s, c) => s + c.bookedCount);
                final totalCap = todayClasses.fold(0, (s, c) => s + c.capacity);
                final weekEnd = todayStart.add(const Duration(days: 7));
                final upcomingCount = all
                    .where((c) =>
                        c.startTime.isAfter(now) &&
                        c.startTime.isBefore(weekEnd))
                    .length;

                final grouped = _groupByDate(filtered);

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 24 : 16,
                    0,
                    isWide ? 24 : 16,
                    100,
                  ),
                  children: [
                    if (_filter == 0 || _filter == 1)
                      _StatsGrid(
                        todayCount: todayClasses.length,
                        totalBooked: totalBooked,
                        totalCap: totalCap,
                        upcomingCount: upcomingCount,
                        isWide: isWide,
                      ),
                    ...grouped.entries.expand((entry) => [
                          _DateHeader(label: entry.key),
                          ...entry.value.map((gc) => _ClassCard(
                                gymClass: gc,
                                classService: _classService,
                                isWide: isWide,
                                onEdit: () =>
                                    _openClassForm(context, existing: gc),
                                onDelete: () => _confirmDelete(context, gc),
                                onBookForMember: () =>
                                    _showBookForMemberDialog(context, gc),
                                onForceReservation: () =>
                                    showForceReservationDialog(
                                  context,
                                  gymClass: gc,
                                  gymId: widget.gymId,
                                ),
                              )),
                        ]),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isWide
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                FloatingActionButton.small(
                  heroTag: 'manageClassTypes',
                  tooltip: context.l10n.tr('Manage class types'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ManageClassTypesScreen(gymId: widget.gymId),
                    ),
                  ),
                  child: const Icon(Icons.category_outlined),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'createClass',
                  onPressed: () => _openClassForm(context),
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.tr('Create Class')),
                ),
              ],
            ),
    );
  }

  Future<void> _openClassForm(BuildContext context,
      {GymClass? existing}) async {
    await showClassEditorDialog(
      context,
      gymId: widget.gymId,
      existing: existing,
    );
  }

  Future<void> _confirmDelete(BuildContext context, GymClass gc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Delete class?')),
        content: Text(
            '"${gc.title}" ${context.l10n.tr('on')} ${DateFormat('EEE d MMM, HH:mm').format(gc.startTime)} ${context.l10n.tr('will be permanently removed.')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.tr('Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: Text(context.l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _classService.deleteClass(gc.id);
    }
  }

  Future<void> _showBookForMemberDialog(
      BuildContext context, GymClass gc) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _BookForMemberDialog(
        gymClass: gc,
        gymId: widget.gymId,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header: search + filter + (web) action buttons
// ─────────────────────────────────────────────────────────────────────────────

class _ClassesHeader extends StatelessWidget {
  const _ClassesHeader({
    required this.controller,
    required this.filter,
    required this.onSearch,
    required this.onFilter,
    required this.isWide,
    required this.onCreateClass,
    required this.onManageTypes,
  });

  final TextEditingController controller;
  final int filter;
  final ValueChanged<String> onSearch;
  final ValueChanged<int> onFilter;
  final bool isWide;
  final VoidCallback onCreateClass;
  final VoidCallback onManageTypes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final labels = [
      l10n.tr('All'),
      l10n.tr('Today'),
      l10n.tr('Tomorrow'),
      l10n.tr('This Week'),
    ];

    final filterChips = labels.asMap().entries.map((e) {
      final i = e.key;
      final label = e.value;
      final selected = filter == i;
      return Padding(
        padding: EdgeInsets.only(right: isWide ? 0 : 8, left: isWide ? 6 : 0),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onFilter(i),
          selectedColor: const Color(0xFF0F4C45).withValues(alpha: 0.15),
          checkmarkColor: const Color(0xFF0F4C45),
          labelStyle: TextStyle(
            fontSize: 12,
            color: selected ? const Color(0xFF0F4C45) : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
            color: selected ? const Color(0xFF0F4C45) : cs.outlineVariant,
          ),
        ),
      );
    }).toList();

    final searchField = TextField(
      controller: controller,
      onChanged: onSearch,
      decoration: InputDecoration(
        hintText: l10n.tr('Search by class or coach…'),
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  controller.clear();
                  onSearch('');
                },
              )
            : null,
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );

    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 14, isWide ? 24 : 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isWide) ...[
            // Web: search + chips + buttons all in one row
            Row(
              children: [
                SizedBox(width: 280, child: searchField),
                const SizedBox(width: 8),
                ...filterChips,
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onManageTypes,
                  icon: const Icon(Icons.category_outlined, size: 15),
                  label: Text(l10n.tr('Class Types')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onCreateClass,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(context.l10n.tr('Create Class')),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F4C45),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Mobile: search then chips below
            searchField,
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: filterChips),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats: grid on web, compact strip on mobile
// ─────────────────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.todayCount,
    required this.totalBooked,
    required this.totalCap,
    required this.upcomingCount,
    required this.isWide,
  });

  final int todayCount;
  final int totalBooked;
  final int totalCap;
  final int upcomingCount;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final fillRate = totalCap > 0
        ? '${(totalBooked / totalCap * 100).toStringAsFixed(0)}%'
        : '—';
    final fillColor = totalCap > 0 && totalBooked / totalCap > 0.8
        ? Colors.red.shade600
        : Colors.green.shade600;

    final l10n = context.l10n;

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            _StatCard(
              icon: Icons.fitness_center_rounded,
              label: l10n.tr("Today's Classes"),
              value: '$todayCount',
              color: const Color(0xFF0F4C45),
            ),
            const SizedBox(width: 12),
            _StatCard(
              icon: Icons.people_rounded,
              label: l10n.tr('Booked Today'),
              value: '$totalBooked / $totalCap',
              color: Colors.blue.shade600,
            ),
            const SizedBox(width: 12),
            _StatCard(
              icon: Icons.bar_chart_rounded,
              label: l10n.tr('Fill Rate'),
              value: fillRate,
              color: fillColor,
            ),
            const SizedBox(width: 12),
            _StatCard(
              icon: Icons.event_outlined,
              label: l10n.tr('Next 7 Days'),
              value: '$upcomingCount',
              color: Colors.purple.shade600,
            ),
          ],
        ),
      );
    }

    // Mobile compact strip
    if (todayCount == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F4C45), Color(0xFF0D7377)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _StatItem(
            label: l10n.tr("Today's classes"),
            value: '$todayCount',
            icon: Icons.fitness_center,
          ),
          const SizedBox(width: 24),
          _StatItem(
            label: l10n.tr('Booked today'),
            value: '$totalBooked / $totalCap',
            icon: Icons.people_outline,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
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

class _StatItem extends StatelessWidget {
  const _StatItem(
      {required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date section header
// ─────────────────────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final isToday = label == context.l10n.tr('Today');
    final isTomorrow = label == context.l10n.tr('Tomorrow');
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          if (isToday || isTomorrow)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isToday
                    ? const Color(0xFF0F4C45)
                    : const Color(0xFF0D7377).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isToday ? Colors.white : const Color(0xFF0D7377),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.5),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rich class card — hover-aware, web action row
// ─────────────────────────────────────────────────────────────────────────────

class _ClassCard extends StatefulWidget {
  const _ClassCard({
    required this.gymClass,
    required this.classService,
    required this.isWide,
    required this.onEdit,
    required this.onDelete,
    required this.onBookForMember,
    required this.onForceReservation,
  });

  final GymClass gymClass;
  final ClassService classService;
  final bool isWide;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onBookForMember;
  final VoidCallback onForceReservation;

  @override
  State<_ClassCard> createState() => _ClassCardState();
}

class _ClassCardState extends State<_ClassCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gc = widget.gymClass;
    final now = DateTime.now();
    final isPast = gc.endTime.isBefore(now);
    final isNow = now.isAfter(gc.startTime) && now.isBefore(gc.endTime);
    final isFull = gc.isFull;
    final accentColor = gc.classColorValue != null
        ? Color(gc.classColorValue!)
        : const Color(0xFF0F4C45);
    final displayAccent =
        isPast ? accentColor.withValues(alpha: 0.45) : accentColor;
    final fillRatio = gc.capacity > 0 ? gc.bookedCount / gc.capacity : 0.0;
    final durationMin = gc.endTime.difference(gc.startTime).inMinutes;
    final l10n = context.l10n;

    final coaches = gc.coachNames.isNotEmpty
        ? gc.coachNames
        : gc.coachName
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isPast
              ? cs.surfaceContainerLowest
              : (_hovered ? cs.surfaceContainer : cs.surface),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isNow
                ? accentColor.withValues(alpha: 0.5)
                : _hovered
                    ? accentColor.withValues(alpha: 0.4)
                    : cs.outlineVariant.withValues(alpha: 0.4),
            width: isNow || _hovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? 0.08 : 0.04),
              blurRadius: _hovered ? 12 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Colored left accent strip ──────────────────────────
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: displayAccent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),

              // ── Card content ───────────────────────────────────────
              Expanded(
                child: Padding(
                  padding:
                      EdgeInsets.fromLTRB(14, 12, widget.isWide ? 14 : 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Title row ──────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              gc.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: widget.isWide ? 16 : 15,
                                color:
                                    isPast ? cs.onSurfaceVariant : cs.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isNow) _LiveBadge(),
                          if (isPast)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    cs.onSurfaceVariant.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                l10n.tr('PAST'),
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          // Mobile inline actions
                          if (!widget.isWide) ...[
                            _IconAction(
                              icon: Icons.person_add_outlined,
                              tooltip: l10n.tr('Book for member'),
                              color: Colors.teal.shade600,
                              onTap: widget.onBookForMember,
                            ),
                            _IconAction(
                              icon: Icons.bolt_rounded,
                              tooltip: l10n.tr('Force reservation'),
                              color: Colors.orange.shade700,
                              onTap: widget.onForceReservation,
                            ),
                            _IconAction(
                              icon: Icons.edit_outlined,
                              tooltip: l10n.tr('Edit'),
                              onTap: widget.onEdit,
                            ),
                            _IconAction(
                              icon: Icons.delete_outline,
                              tooltip: l10n.tr('Delete'),
                              color: Colors.red.shade400,
                              onTap: widget.onDelete,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),

                      // ── Time + duration ────────────────────────────
                      Row(
                        children: [
                          Icon(Icons.schedule_outlined,
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '${DateFormat('HH:mm').format(gc.startTime)} – ${DateFormat('HH:mm').format(gc.endTime)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· $durationMin ${l10n.tr('min')}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                          if (gc.repeatWeekly) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.repeat_rounded,
                                size: 13, color: cs.primary),
                            const SizedBox(width: 3),
                            Text(
                              l10n.tr('Weekly'),
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ── Coaches ────────────────────────────────────
                      if (coaches.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: coaches
                              .take(widget.isWide ? 6 : 3)
                              .map((name) =>
                                  _CoachPill(name: name, color: accentColor))
                              .toList(),
                        ),

                      const SizedBox(height: 10),

                      // ── Capacity + progress ────────────────────────
                      Row(
                        children: [
                          Icon(Icons.people_outline_rounded,
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '${gc.bookedCount}/${gc.capacity}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isFull
                                  ? Colors.red.shade600
                                  : cs.onSurfaceVariant,
                              fontWeight:
                                  isFull ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                          if (gc.waitlistCount > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '+${gc.waitlistCount} ${l10n.tr('waitlist')}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                          const SizedBox(width: 10),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: fillRatio.clamp(0.0, 1.0),
                                minHeight: 5,
                                backgroundColor:
                                    cs.outlineVariant.withValues(alpha: 0.3),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isFull
                                      ? Colors.red.shade500
                                      : fillRatio > 0.75
                                          ? Colors.orange.shade500
                                          : accentColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(fillRatio * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isFull
                                  ? Colors.red.shade600
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),

                      // ── Tags ───────────────────────────────────────
                      if (gc.hasOfferRequirement ||
                          isFull ||
                          gc.waitlistCount > 0 ||
                          gc.dropInEnabled) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (isFull)
                              _Tag(label: l10n.tr('Full'), color: Colors.red.shade600),
                            if (gc.hasOfferRequirement)
                              _Tag(
                                  label: l10n.tr('Offer Required'),
                                  color: Colors.purple.shade600),
                            if (gc.dropInEnabled)
                              _Tag(
                                label:
                                    '${l10n.tr('Drop-in')} €${gc.dropInPrice % 1 == 0 ? gc.dropInPrice.toInt() : gc.dropInPrice}',
                                color: const Color(0xFFEA580C),
                              ),
                          ],
                        ),
                      ],

                      // ── Web action row ─────────────────────────────
                      if (widget.isWide) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _WebActionBtn(
                              icon: Icons.person_add_outlined,
                              label: l10n.tr('Book Member'),
                              color: const Color(0xFF0F766E),
                              onTap: widget.onBookForMember,
                            ),
                            const SizedBox(width: 8),
                            _WebActionBtn(
                              icon: Icons.bolt_rounded,
                              label: l10n.tr('Force Reserve'),
                              color: Colors.orange.shade700,
                              onTap: widget.onForceReservation,
                            ),
                            const Spacer(),
                            _WebActionBtn(
                              icon: Icons.edit_outlined,
                              label: l10n.tr('Edit'),
                              color: cs.primary,
                              onTap: widget.onEdit,
                              outlined: true,
                            ),
                            const SizedBox(width: 8),
                            _WebActionBtn(
                              icon: Icons.delete_outline,
                              label: l10n.tr('Delete'),
                              color: Colors.red.shade600,
                              onTap: widget.onDelete,
                              outlined: true,
                            ),
                          ],
                        ),
                      ],
                    ],
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

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        context.l10n.tr('LIVE'),
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
      onPressed: onTap,
    );
  }
}

class _WebActionBtn extends StatelessWidget {
  const _WebActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _CoachPill extends StatelessWidget {
  const _CoachPill({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 8,
            backgroundColor: color.withValues(alpha: 0.3),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  fontSize: 8, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(width: 5),
          Text(name,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 13)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClassEditorDialog extends StatefulWidget {
  const _ClassEditorDialog({
    required this.gymId,
    this.existing,
    this.initialStartDateTime,
    this.initialEndDateTime,
    this.forceSingleClass = false,
  });

  final String gymId;
  final GymClass? existing;
  final DateTime? initialStartDateTime;
  final DateTime? initialEndDateTime;
  final bool forceSingleClass;

  @override
  State<_ClassEditorDialog> createState() => _ClassEditorDialogState();
}

class _ClassEditorDialogState extends State<_ClassEditorDialog> {
  late final _classService = ClassService(gymId: widget.gymId);
  late final _classTypeService = ClassTypeService(gymId: widget.gymId);
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);
  final _descriptionController = TextEditingController();
  final _capacityController = TextEditingController(text: '20');
  final _dropInPriceController = TextEditingController(text: '0');
  final List<CoachSelectionResult> _selectedCoaches = <CoachSelectionResult>[];

  // null means no type selected yet (waiting for stream)
  String? _selectedTypeId;
  // stored title of existing class that may not yet match a loaded type
  String? _existingTitle;

  DateTime _selectedDate = DateTime.now().add(const Duration(hours: 2));
  TimeOfDay _startTime = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(hours: 2)),
  );
  TimeOfDay _endTime = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(hours: 3)),
  );
  bool _repeatWeekly = false;
  final Set<int> _repeatWeekdays = <int>{};
  DateTime? _repeatEndDate;
  final Set<String> _requiredOfferPlanIds = <String>{};
  int? _selectedClassColorValue;
  bool _dropInEnabled = false;
  bool _isSaving = false;
  List<ClassType> _loadedClassTypes = <ClassType>[];
  _EditScope _editScope = _EditScope.thisOnly;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _existingTitle = existing.title;
      final initialCoaches = existing.coachNames.isNotEmpty
          ? existing.coachNames
          : existing.coachName
              .split(',')
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty)
              .toList(growable: false);
      _selectedCoaches
        ..clear()
        ..addAll(
          initialCoaches.asMap().entries.map(
                (entry) => CoachSelectionResult(
                  id: existing.coachIds.length > entry.key
                      ? existing.coachIds[entry.key]
                      : 'legacy_${entry.key}_${entry.value}',
                  name: entry.value,
                ),
              ),
        );
      _descriptionController.text = existing.description;
      _capacityController.text = existing.capacity.toString();
      _dropInEnabled = existing.dropInEnabled;
      _dropInPriceController.text = existing.dropInPrice.toString();
      _selectedDate = existing.startTime;
      _startTime = TimeOfDay.fromDateTime(existing.startTime);
      _endTime = TimeOfDay.fromDateTime(existing.endTime);
      _repeatWeekly = existing.repeatWeekly;
      _repeatWeekdays
        ..clear()
        ..addAll(existing.repeatWeekdays);
      _requiredOfferPlanIds
        ..clear()
        ..addAll(existing.requiredOfferPlanIds);
      _selectedClassColorValue = existing.classColorValue;
      _repeatEndDate = existing.recurrenceEndDate;
    } else {
      final initialStart = widget.initialStartDateTime;
      final initialEnd = widget.initialEndDateTime ??
          initialStart?.add(const Duration(hours: 1));
      if (initialStart != null) {
        _selectedDate = initialStart;
        _startTime = TimeOfDay.fromDateTime(initialStart);
      }
      if (initialEnd != null) {
        _endTime = TimeOfDay.fromDateTime(initialEnd);
      }
      if (widget.forceSingleClass) {
        _repeatWeekly = false;
      } else {
        _repeatEndDate = _selectedDate.add(const Duration(days: 56));
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _capacityController.dispose();
    _dropInPriceController.dispose();
    super.dispose();
  }

  Future<void> _pickCoaches() async {
    final selected = await pickCoaches(
      context: context,
      gymId: widget.gymId,
      initialSelection: List<CoachSelectionResult>.from(_selectedCoaches),
    );

    if (selected == null) return;

    setState(() {
      _selectedCoaches
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _pickRequiredOffers(List<MembershipPlan> offers) async {
    final tempSelected = Set<String>.from(_requiredOfferPlanIds);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(context.l10n.tr('Select required offers')),
              content: SizedBox(
                width: 420,
                child: offers.isEmpty
                    ? Text(context.l10n.tr('No active offers found.'))
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: offers
                              .map(
                                (offer) => CheckboxListTile(
                                  value: tempSelected.contains(offer.id),
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(offer.name),
                                  subtitle: Text(offer.checkinSummary),
                                  onChanged: (checked) {
                                    setDialogState(() {
                                      if (checked ?? false) {
                                        tempSelected.add(offer.id);
                                      } else {
                                        tempSelected.remove(offer.id);
                                      }
                                    });
                                  },
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.tr('Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(<String>{}),
                  child: Text(context.l10n.tr('Clear all')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(tempSelected),
                  child: Text(context.l10n.tr('Apply')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _requiredOfferPlanIds
        ..clear()
        ..addAll(result);
    });
  }

  List<MapEntry<int, String>> _weekdayChoices(AppLocalizations l10n) =>
      <MapEntry<int, String>>[
        MapEntry<int, String>(DateTime.monday, l10n.tr('Mon')),
        MapEntry<int, String>(DateTime.tuesday, l10n.tr('Tue')),
        MapEntry<int, String>(DateTime.wednesday, l10n.tr('Wed')),
        MapEntry<int, String>(DateTime.thursday, l10n.tr('Thu')),
        MapEntry<int, String>(DateTime.friday, l10n.tr('Fri')),
        MapEntry<int, String>(DateTime.saturday, l10n.tr('Sat')),
        MapEntry<int, String>(DateTime.sunday, l10n.tr('Sun')),
      ];

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: _selectedDate,
    );
    if (date == null) return;
    setState(() {
      _selectedDate = date;
      if (_repeatWeekly &&
          (_repeatEndDate == null || _repeatEndDate!.isBefore(_selectedDate))) {
        _repeatEndDate = _selectedDate.add(const Duration(days: 28));
      }
    });
  }

  Future<void> _pickRepeatDateRange() async {
    final initialEnd =
        _repeatEndDate == null || _repeatEndDate!.isBefore(_selectedDate)
            ? _selectedDate.add(const Duration(days: 28))
            : _repeatEndDate!;

    final l10n = context.l10n;
    final range = await showDateRangePicker(
      context: context,
      firstDate: _selectedDate,
      lastDate: _selectedDate.add(const Duration(days: 365 * 3)),
      initialDateRange: DateTimeRange(start: _selectedDate, end: initialEnd),
      helpText: l10n.tr('Select class duration'),
      saveText: l10n.tr('Apply'),
    );
    if (range == null) {
      return;
    }

    setState(() {
      _selectedDate = range.start;
      _repeatEndDate = range.end;
    });
  }

  Future<void> _pickStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (time == null) return;
    setState(() {
      _startTime = time;
      final startMinutes = time.hour * 60 + time.minute;
      final endMinutes = _endTime.hour * 60 + _endTime.minute;
      if (endMinutes <= startMinutes) {
        final newEnd = startMinutes + 60;
        _endTime = TimeOfDay(hour: (newEnd ~/ 60) % 24, minute: newEnd % 60);
      }
    });
  }

  Future<void> _pickEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (time == null) return;
    setState(() => _endTime = time);
  }

  DateTime _buildDateTime(TimeOfDay time) => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        time.hour,
        time.minute,
      );

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save(List<ClassType> classTypes) async {
    final selectedType = classTypes.cast<ClassType?>().firstWhere(
          (ct) => ct!.id == _selectedTypeId,
          orElse: () => null,
        );
    final title = selectedType?.name ?? '';
    final capacity = int.tryParse(_capacityController.text.trim());
    final selectedDateOnly =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final repeatEndDateOnly = _repeatEndDate == null
        ? null
        : DateTime(
            _repeatEndDate!.year,
            _repeatEndDate!.month,
            _repeatEndDate!.day,
          );

    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;

    final l10n = context.l10n;
    final errors = <String>[];
    if (_selectedTypeId == null) errors.add(l10n.tr('Please select a class type'));
    if (capacity == null) {
      errors.add(l10n.tr('Capacity must be a number'));
    } else if (capacity <= 0) {
      errors.add(l10n.tr('Capacity must be greater than 0'));
    }
    if (endMinutes <= startMinutes) {
      errors.add(l10n.tr('End time must be after start time'));
    }
    if (_repeatWeekly && _repeatWeekdays.isEmpty) {
      errors.add(l10n.tr('Select at least one day of the week for repeat'));
    }
    if (_repeatWeekly && repeatEndDateOnly == null) {
      errors.add(l10n.tr('Please set a repeat end date'));
    } else if (_repeatWeekly &&
        repeatEndDateOnly != null &&
        repeatEndDateOnly.isBefore(selectedDateOnly)) {
      errors.add(l10n.tr('Repeat end date must be after the class date'));
    }

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errors.first),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final existing = widget.existing;
      if (existing == null) {
        await _classService.createClass(
          title: title,
          coachName: _selectedCoaches.map((coach) => coach.name).join(', '),
          coachIds:
              _selectedCoaches.map((coach) => coach.id).toList(growable: false),
          coachNames: _selectedCoaches
              .map((coach) => coach.name)
              .toList(growable: false),
          description: _descriptionController.text.trim(),
          startTime: _buildDateTime(_startTime),
          endTime: _buildDateTime(_endTime),
          capacity: capacity!,
          requiredOfferPlanIds: _requiredOfferPlanIds.toList(growable: false),
          classColorValue: _selectedClassColorValue,
          repeatWeekly: widget.forceSingleClass ? false : _repeatWeekly,
          repeatWeekdays: _repeatWeekdays.toList(growable: false),
          recurrenceEndDate: _repeatWeekly ? repeatEndDateOnly : null,
          dropInEnabled: _dropInEnabled,
          dropInPrice:
              double.tryParse(_dropInPriceController.text.trim()) ?? 0.0,
        );
      } else if (existing.recurrenceGroupId != null &&
          _editScope != _EditScope.thisOnly) {
        if (_editScope == _EditScope.thisAndFollowing) {
          await _classService.updateSeriesFromDate(
            recurrenceGroupId: existing.recurrenceGroupId!,
            fromDate: existing.startTime,
            title: title,
            coachName: _selectedCoaches.map((c) => c.name).join(', '),
            coachIds: _selectedCoaches.map((c) => c.id).toList(growable: false),
            coachNames:
                _selectedCoaches.map((c) => c.name).toList(growable: false),
            description: _descriptionController.text.trim(),
            startTime: _buildDateTime(_startTime),
            endTime: _buildDateTime(_endTime),
            capacity: capacity!,
            requiredOfferPlanIds: _requiredOfferPlanIds.toList(growable: false),
            classColorValue: _selectedClassColorValue,
            dropInEnabled: _dropInEnabled,
            dropInPrice:
                double.tryParse(_dropInPriceController.text.trim()) ?? 0.0,
          );
        } else {
          await _classService.updateEntireSeries(
            recurrenceGroupId: existing.recurrenceGroupId!,
            title: title,
            coachName: _selectedCoaches.map((c) => c.name).join(', '),
            coachIds: _selectedCoaches.map((c) => c.id).toList(growable: false),
            coachNames:
                _selectedCoaches.map((c) => c.name).toList(growable: false),
            description: _descriptionController.text.trim(),
            startTime: _buildDateTime(_startTime),
            endTime: _buildDateTime(_endTime),
            capacity: capacity!,
            requiredOfferPlanIds: _requiredOfferPlanIds.toList(growable: false),
            classColorValue: _selectedClassColorValue,
            dropInEnabled: _dropInEnabled,
            dropInPrice:
                double.tryParse(_dropInPriceController.text.trim()) ?? 0.0,
          );
        }
      } else {
        await _classService.updateClass(
          classId: existing.id,
          title: title,
          coachName: _selectedCoaches.map((coach) => coach.name).join(', '),
          coachIds:
              _selectedCoaches.map((coach) => coach.id).toList(growable: false),
          coachNames: _selectedCoaches
              .map((coach) => coach.name)
              .toList(growable: false),
          description: _descriptionController.text.trim(),
          startTime: _buildDateTime(_startTime),
          endTime: _buildDateTime(_endTime),
          capacity: capacity!,
          requiredOfferPlanIds: _requiredOfferPlanIds.toList(growable: false),
          classColorValue: _selectedClassColorValue,
          dropInEnabled: _dropInEnabled,
          dropInPrice:
              double.tryParse(_dropInPriceController.text.trim()) ?? 0.0,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, s) {
      await CrashLogger.log(error, s, reason: 'saveClass');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('Error')}: $error'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Class count estimator ─────────────────────────────────────────────────

  int _estimatedClassCount() {
    if (!_repeatWeekly || _repeatWeekdays.isEmpty || _repeatEndDate == null) {
      return 1;
    }
    final start =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final end = DateTime(
        _repeatEndDate!.year, _repeatEndDate!.month, _repeatEndDate!.day);
    var count = 0;
    var current = start;
    while (!current.isAfter(end)) {
      if (_repeatWeekdays.contains(current.weekday)) count++;
      current = current.add(const Duration(days: 1));
    }
    return count;
  }

  // ── Section card helper ────────────────────────────────────────────────────

  Widget _buildSectionCard(
    String title,
    IconData icon,
    List<Widget> children,
    BuildContext context,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: cs.primary),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  // ── Dialog header ──────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final isEditing = widget.existing != null;
    final isSeriesClass =
        isEditing && widget.existing!.recurrenceGroupId != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_outlined : Icons.add_box_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Text(
            isEditing ? context.l10n.tr('Edit Class') : context.l10n.tr('New Class'),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (isSeriesClass) ...[
            SegmentedButton<_EditScope>(
              segments: <ButtonSegment<_EditScope>>[
                ButtonSegment<_EditScope>(
                  value: _EditScope.thisOnly,
                  label: Text(context.l10n.tr('This only')),
                  icon: Icon(Icons.event_outlined, size: 16),
                ),
                ButtonSegment<_EditScope>(
                  value: _EditScope.thisAndFollowing,
                  label: Text(context.l10n.tr('This & following')),
                  icon: Icon(Icons.event_repeat_outlined, size: 16),
                ),
                ButtonSegment<_EditScope>(
                  value: _EditScope.allInSeries,
                  label: Text(context.l10n.tr('All in series')),
                  icon: Icon(Icons.repeat, size: 16),
                ),
              ],
              selected: <_EditScope>{_editScope},
              onSelectionChanged: (Set<_EditScope> s) {
                if (s.isNotEmpty) setState(() => _editScope = s.first);
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ── Schedule section ───────────────────────────────────────────────────────

  Widget _buildScheduleSection(BuildContext context) {
    return _buildSectionCard(
      context.l10n.tr('SCHEDULE'),
      Icons.schedule_outlined,
      [
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: context.l10n.tr('Date'),
              prefixIcon: Icon(Icons.calendar_today),
            ),
            child: Text(
              DateFormat('EEEE, d MMMM yyyy').format(_selectedDate),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: _pickStartTime,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.l10n.tr('Start'),
                    prefixIcon: Icon(Icons.access_time),
                  ),
                  child: Text(_formatTime(_startTime)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: _pickEndTime,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.l10n.tr('End'),
                    prefixIcon: Icon(Icons.access_time_filled),
                  ),
                  child: Text(_formatTime(_endTime)),
                ),
              ),
            ),
          ],
        ),
      ],
      context,
    );
  }

  // ── Recurrence section ─────────────────────────────────────────────────────

  Widget _buildRecurrenceSection(BuildContext context) {
    if (widget.forceSingleClass) return const SizedBox.shrink();
    return _buildSectionCard(
      context.l10n.tr('RECURRENCE'),
      Icons.repeat_outlined,
      [
        SwitchListTile(
          value: _repeatWeekly,
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.tr('Repeat weekly')),
          subtitle: Text(context.l10n.tr('Create recurring classes on selected weekdays')),
          onChanged: (value) => setState(() => _repeatWeekly = value),
        ),
        if (_repeatWeekly) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _weekdayChoices(context.l10n)
                .map(
                  (entry) => FilterChip(
                    label: Text(entry.value),
                    selected: _repeatWeekdays.contains(entry.key),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _repeatWeekdays.add(entry.key);
                        } else {
                          _repeatWeekdays.remove(entry.key);
                        }
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickRepeatDateRange,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: context.l10n.tr('Class duration'),
                prefixIcon: Icon(Icons.date_range_outlined),
              ),
              child: Text(
                _repeatEndDate == null
                    ? context.l10n.tr('Select end date')
                    : '${DateFormat('d MMM yyyy').format(_selectedDate)}  ->  ${DateFormat('d MMM yyyy').format(_repeatEndDate!)}',
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ActionChip(
                label: Text(context.l10n.tr('4 weeks')),
                onPressed: () {
                  setState(() {
                    _repeatEndDate =
                        _selectedDate.add(const Duration(days: 28));
                  });
                },
              ),
              ActionChip(
                label: Text(context.l10n.tr('8 weeks')),
                onPressed: () {
                  setState(() {
                    _repeatEndDate =
                        _selectedDate.add(const Duration(days: 56));
                  });
                },
              ),
              ActionChip(
                label: Text(context.l10n.tr('12 weeks')),
                onPressed: () {
                  setState(() {
                    _repeatEndDate =
                        _selectedDate.add(const Duration(days: 84));
                  });
                },
              ),
            ],
          ),
        ],
      ],
      context,
    );
  }

  // ── Class details section ──────────────────────────────────────────────────

  Widget _buildClassDetailsSection(BuildContext context) {
    return _buildSectionCard(
      context.l10n.tr('CLASS DETAILS'),
      Icons.label_outline,
      [
        StreamBuilder<List<ClassType>>(
          stream: _classTypeService.streamClassTypes(),
          builder: (context, snapshot) {
            final classTypes = snapshot.data ?? <ClassType>[];

            // cache for _save()
            if (snapshot.hasData) {
              _loadedClassTypes = classTypes;
            }

            // Auto-select first type or match existing title once loaded
            if (classTypes.isNotEmpty && _selectedTypeId == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final match = classTypes.cast<ClassType?>().firstWhere(
                      (ct) => ct!.name == _existingTitle,
                      orElse: () => null,
                    );
                setState(() {
                  _selectedTypeId = match?.id ?? classTypes.first.id;
                  // apply color from matched/first type only when creating
                  if (widget.existing == null) {
                    _selectedClassColorValue =
                        (match ?? classTypes.first).colorValue;
                  }
                });
              });
            }

            final validId = classTypes.any((ct) => ct.id == _selectedTypeId)
                ? _selectedTypeId
                : null;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: validId,
                    decoration: InputDecoration(
                      labelText: context.l10n.tr('Class type'),
                    ),
                    hint: snapshot.connectionState == ConnectionState.waiting
                        ? Text(context.l10n.tr('Loading…'))
                        : classTypes.isEmpty
                            ? Text(context.l10n.tr('No types — add one first'))
                            : null,
                    items: classTypes
                        .map(
                          (ct) => DropdownMenuItem<String>(
                            value: ct.id,
                            child: Row(
                              children: <Widget>[
                                if (ct.colorValue != null)
                                  Container(
                                    width: 12,
                                    height: 12,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: Color(ct.colorValue!),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text(ct.name),
                              ],
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: classTypes.isEmpty
                        ? null
                        : (value) {
                            if (value == null) return;
                            final ct =
                                classTypes.firstWhere((c) => c.id == value);
                            setState(() {
                              _selectedTypeId = value;
                              // auto-apply the type's color
                              _selectedClassColorValue = ct.colorValue;
                            });
                          },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: context.l10n.tr('Manage class types'),
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ManageClassTypesScreen(gymId: widget.gymId),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (_selectedClassColorValue != null) ...[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(Icons.palette_outlined, size: 18),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Color(_selectedClassColorValue!),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.tr('Card color from class type'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        _CoachSelectorField(
          selectedCoaches: _selectedCoaches,
          onTap: _pickCoaches,
          onRemove: (id) =>
              setState(() => _selectedCoaches.removeWhere((c) => c.id == id)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _descriptionController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: context.l10n.tr('Description (optional)'),
          ),
        ),
      ],
      context,
    );
  }

  // ── Settings section ───────────────────────────────────────────────────────

  Widget _buildSettingsSection(BuildContext context) {
    return _buildSectionCard(
      context.l10n.tr('SETTINGS'),
      Icons.tune_outlined,
      [
        TextField(
          controller: _capacityController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.l10n.tr('Max joiners'),
            prefixIcon: Icon(Icons.people),
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<List<MembershipPlan>>(
          stream: _subscriptionService.streamPlans(),
          builder: (context, snapshot) {
            final offers = snapshot.data ?? <MembershipPlan>[];
            final selectedOffers = offers
                .where((offer) => _requiredOfferPlanIds.contains(offer.id))
                .toList(growable: false);

            return InputDecorator(
              decoration: InputDecoration(
                labelText: context.l10n.tr('Required offers'),
                prefixIcon: Icon(Icons.workspace_premium_outlined),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_requiredOfferPlanIds.isEmpty)
                    Text(
                      context.l10n.tr('Any offer can join'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectedOffers
                          .map(
                            (offer) => Chip(
                              label: Text(
                                  '${offer.name} • ${offer.checkinSummary}'),
                              onDeleted: () {
                                setState(() {
                                  _requiredOfferPlanIds.remove(offer.id);
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _pickRequiredOffers(offers),
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text(context.l10n.tr('Select offers')),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          value: _dropInEnabled,
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.tr('Allow Drop-ins')),
          subtitle: Text(context.l10n.tr('Non-members can join as drop-in guests')),
          onChanged: (v) => setState(() => _dropInEnabled = v),
        ),
        if (_dropInEnabled) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _dropInPriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.l10n.tr('Drop-in Price (€)'),
              prefixIcon: Icon(Icons.euro_outlined),
            ),
          ),
        ],
      ],
      context,
    );
  }

  // ── Dialog body ────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth >= 580;

        final scheduleSection = _buildScheduleSection(context);
        final recurrenceSection = _buildRecurrenceSection(context);
        final classDetailsSection = _buildClassDetailsSection(context);
        final settingsSection = _buildSettingsSection(context);

        if (twoColumn) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      scheduleSection,
                      recurrenceSection,
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      classDetailsSection,
                      settingsSection,
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                scheduleSection,
                recurrenceSection,
                classDetailsSection,
                settingsSection,
              ],
            ),
          );
        }
      },
    );
  }

  // ── Dialog footer ──────────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    final showCount =
        _repeatWeekly && _repeatWeekdays.isNotEmpty && _repeatEndDate != null;
    final count = showCount ? _estimatedClassCount() : 0;
    final isEditing = widget.existing != null;
    final isRecurring = !isEditing &&
        _repeatWeekly &&
        _repeatWeekdays.isNotEmpty &&
        _repeatEndDate != null;

    final String saveLabel;
    if (isEditing) {
      saveLabel = context.l10n.tr('Save changes');
    } else if (isRecurring) {
      saveLabel = '${context.l10n.tr('Create')} $count ${context.l10n.tr('classes')}';
    } else {
      saveLabel = context.l10n.tr('Create class');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          if (showCount)
            Text(
              '${context.l10n.tr('Creating')} ~$count ${context.l10n.tr('classes')}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: Text(context.l10n.tr('Cancel')),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _isSaving ? null : () => _save(_loadedClassTypes),
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(saveLabel),
          ),
        ],
      ),
    );
  }

  // ── Main build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Scaffold(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerLowest,
            body: Column(
              children: [
                _buildHeader(context),
                const Divider(height: 1),
                Expanded(child: _buildBody(context)),
                const Divider(height: 1),
                _buildFooter(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Coach selector field widget ───────────────────────────────────────────────

class _CoachSelectorField extends StatelessWidget {
  const _CoachSelectorField({
    required this.selectedCoaches,
    required this.onTap,
    required this.onRemove,
  });

  final List<CoachSelectionResult> selectedCoaches;
  final VoidCallback onTap;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasCoaches = selectedCoaches.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasCoaches
                ? cs.primary.withValues(alpha: 0.5)
                : cs.outlineVariant,
            width: hasCoaches ? 1.5 : 1,
          ),
          color: hasCoaches
              ? cs.primary.withValues(alpha: 0.04)
              : cs.surfaceContainerLow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.record_voice_over_outlined,
                  size: 20,
                  color: hasCoaches ? cs.primary : cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.tr('Coaches'),
                    style: TextStyle(
                      fontSize: 12,
                      color: hasCoaches ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (!hasCoaches)
                    Text(
                      context.l10n.tr('Tap to assign coaches…'),
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: selectedCoaches.map((coach) {
                        return Chip(
                          avatar: CircleAvatar(
                            backgroundColor: cs.primary,
                            child: Text(
                              coach.name.isNotEmpty
                                  ? coach.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          label: Text(coach.name,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => onRemove(coach.id),
                          backgroundColor:
                              cs.primaryContainer.withValues(alpha: 0.5),
                          side: BorderSide(
                              color: cs.primary.withValues(alpha: 0.3)),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: hasCoaches ? cs.primary : cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Book for member dialog
// ─────────────────────────────────────────────────────────────────────────────

class _BookForMemberDialog extends StatefulWidget {
  const _BookForMemberDialog({required this.gymClass, required this.gymId});
  final GymClass gymClass;
  final String gymId;

  @override
  State<_BookForMemberDialog> createState() => _BookForMemberDialogState();
}

class _BookForMemberDialogState extends State<_BookForMemberDialog> {
  late final _memberService = MemberService(gymId: widget.gymId);
  late final _bookingService = BookingService(gymId: widget.gymId);
  final _searchCtrl = TextEditingController();

  String? _selectedMemberId;
  String _selectedMemberName = '';
  String _search = '';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _book() async {
    if (_selectedMemberId == null) {
      setState(() => _error = context.l10n.tr('Please select a member.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _bookingService.bookClass(
        classId: widget.gymClass.id,
        userId: _selectedMemberId!,
        bypassDailyLimit: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('$_selectedMemberName ${context.l10n.tr('booked for')} ${widget.gymClass.title}'),
        backgroundColor: Colors.teal.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'forceReserveMember');
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gc = widget.gymClass;
    const accent = Color(0xFF0F766E);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_add_outlined,
                      color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.tr('Book for Member'),
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(gc.title,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Class info chip ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: accent.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_outlined, size: 14, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('EEE d MMM • HH:mm').format(gc.startTime),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent),
                  ),
                  const Spacer(),
                  Icon(Icons.people_outline_rounded,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${gc.bookedCount}/${gc.capacity}',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Member search + list ──────────────────────────────────
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: context.l10n.tr('Search member…'),
                prefixIcon: const Icon(Icons.search_rounded),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
            const SizedBox(height: 10),

            StreamBuilder<List<AppUser>>(
              stream: _memberService.streamMembers(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? [];
                final filtered = _search.isEmpty
                    ? all
                    : all.where((m) {
                        final name = m.displayName.toLowerCase();
                        final email = m.email.toLowerCase();
                        return name.contains(_search) ||
                            email.contains(_search);
                      }).toList();

                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(context.l10n.tr('No members found'),
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  );
                }

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final m = filtered[i];
                      final name =
                          m.displayName.isNotEmpty ? m.displayName : m.email;
                      final initials = name
                          .trim()
                          .split(' ')
                          .where((p) => p.isNotEmpty)
                          .take(2)
                          .map((p) => p[0].toUpperCase())
                          .join();
                      final isSelected = _selectedMemberId == m.id;

                      return ListTile(
                        dense: true,
                        onTap: () => setState(() {
                          _selectedMemberId = m.id;
                          _selectedMemberName = name;
                          _error = null;
                        }),
                        leading: UserAvatar(
                          photoUrl: m.photoUrl,
                          initials: initials,
                          color: isSelected ? accent : cs.primary,
                          radius: 18,
                        ),
                        title: Text(name,
                            style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.normal)),
                        subtitle: Text(m.email,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded,
                                color: accent)
                            : null,
                        selectedTileColor: accent.withAlpha(15),
                        selected: isSelected,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      );
                    },
                  ),
                );
              },
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ],

            const SizedBox(height: 20),

            // ── Action buttons ────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(context.l10n.tr('Cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _book,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(context.l10n.tr('Confirm Booking'),
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Force Reservation + Check-In dialog  (admin-only, bypasses all offer checks)
// ─────────────────────────────────────────────────────────────────────────────

class _ForceReservationDialog extends StatefulWidget {
  const _ForceReservationDialog({required this.gymClass, required this.gymId});
  final GymClass gymClass;
  final String gymId;

  @override
  State<_ForceReservationDialog> createState() =>
      _ForceReservationDialogState();
}

class _ForceReservationDialogState extends State<_ForceReservationDialog> {
  late final _memberService = MemberService(gymId: widget.gymId);
  late final _bookingService = BookingService(gymId: widget.gymId);
  final _searchCtrl = TextEditingController();

  String? _selectedMemberId;
  String _selectedMemberName = '';
  String _search = '';
  bool _saving = false;
  String? _error;

  static const _accent = Color(0xFFEA580C); // orange accent for force action

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _forceBook() async {
    if (_selectedMemberId == null) {
      setState(() => _error = context.l10n.tr('Please select a member.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _bookingService.forceBookAndCheckIn(
        classId: widget.gymClass.id,
        userId: _selectedMemberId!,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '$_selectedMemberName ${context.l10n.tr('force-reserved & checked in for')} ${widget.gymClass.title}'),
          backgroundColor: _accent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'forceReserveAndCheckIn');
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gc = widget.gymClass;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _accent.withAlpha(24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.bolt_rounded, color: _accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.tr('Force Reservation'),
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(gc.title,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Warning banner ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _accent.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: _accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${context.l10n.tr('Bypasses offer requirements & capacity.')} ${context.l10n.tr('Member will be booked and checked in immediately.')}',
                      style: TextStyle(
                          fontSize: 12,
                          color: _accent,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Class info chip ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _accent.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_outlined, size: 14, color: _accent),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('EEE d MMM • HH:mm').format(gc.startTime),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _accent),
                  ),
                  const Spacer(),
                  Icon(Icons.people_outline_rounded,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${gc.bookedCount}/${gc.capacity}',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Member search + list ──────────────────────────────────
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: context.l10n.tr('Search member…'),
                prefixIcon: const Icon(Icons.search_rounded),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
            const SizedBox(height: 10),

            StreamBuilder<List<AppUser>>(
              stream: _memberService.streamMembers(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? [];
                final filtered = _search.isEmpty
                    ? all
                    : all.where((m) {
                        final name = m.displayName.toLowerCase();
                        final email = m.email.toLowerCase();
                        return name.contains(_search) ||
                            email.contains(_search);
                      }).toList();

                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(context.l10n.tr('No members found'),
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  );
                }

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final m = filtered[i];
                      final name =
                          m.displayName.isNotEmpty ? m.displayName : m.email;
                      final initials = name
                          .trim()
                          .split(' ')
                          .where((p) => p.isNotEmpty)
                          .take(2)
                          .map((p) => p[0].toUpperCase())
                          .join();
                      final isSelected = _selectedMemberId == m.id;

                      return ListTile(
                        dense: true,
                        onTap: () => setState(() {
                          _selectedMemberId = m.id;
                          _selectedMemberName = name;
                          _error = null;
                        }),
                        leading: UserAvatar(
                          photoUrl: m.photoUrl,
                          initials: initials,
                          color: isSelected ? _accent : cs.primary,
                          radius: 18,
                        ),
                        title: Text(name,
                            style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.normal)),
                        subtitle: Text(m.email,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded,
                                color: _accent)
                            : null,
                        selectedTileColor: _accent.withAlpha(15),
                        selected: isSelected,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      );
                    },
                  ),
                );
              },
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ],

            const SizedBox(height: 20),

            // ── Action buttons ────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(context.l10n.tr('Cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _forceBook,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.bolt_rounded, size: 18),
                    label: Text(context.l10n.tr('Force Reserve & Check-In'),
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
