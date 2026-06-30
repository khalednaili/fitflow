import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/gym_class.dart';
import '../../models/personal_training.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import '../../services/personal_training_service.dart';
import '../../utils/app_time.dart';
import '../../utils/currency.dart';
import 'class_details_screen.dart';
import 'membership_screen.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key, this.gymId = '', this.appUser});

  final String gymId;
  final AppUser? appUser;

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  late final _classService = ClassService(gymId: widget.gymId);
  late final _bookingService = BookingService(gymId: widget.gymId);
  late DateTime _selectedDay;
  late DateTime _weekStart;
  int _minAdvanceMinutes = 0;
  bool _hideWithoutSub = false;

  late final Stream<List<GymClass>> _upcomingClassesStream;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _weekStart = _startOfWeek(_selectedDay);
    _upcomingClassesStream = _classService.streamUpcomingClasses();
    _bookingService.getMinAdvanceBookingMinutes().then((v) {
      if (mounted) setState(() => _minAdvanceMinutes = v);
    });
    _bookingService.getHideClassesWithoutSubscription().then((v) {
      if (mounted) setState(() => _hideWithoutSub = v);
    });
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized
        .subtract(Duration(days: normalized.weekday - DateTime.monday));
  }

  void _goToPreviousWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(Duration(days: 7));
      _selectedDay = _weekStart;
    });
  }

  void _goToNextWeek() {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7));
      _selectedDay = _weekStart;
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = DateTime(day.year, day.month, day.day);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedDay = today;
      _weekStart = _startOfWeek(today);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isCurrentWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekStart = _startOfWeek(today);
    return _weekStart == currentWeekStart;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(child: Text(l10n.tr('Please sign in to view classes.'))),
      );
    }

    // ── Subscription gate ──────────────────────────────────────────────────
    final hasActiveSub = widget.appUser != null &&
        widget.appUser!.subscriptionStatus == 'active';
    if (_hideWithoutSub && !hasActiveSub) {
      return _NoSubscriptionGate(gymId: widget.gymId);
    }
    // ──────────────────────────────────────────────────────────────────────
    final screenW = MediaQuery.sizeOf(context).width;
    final isTablet = screenW >= 700;
    final isDesktop = screenW >= 1050;
    final weekEnd = _weekStart.add(Duration(days: 6));
    final sameMonth =
        _weekStart.month == weekEnd.month && _weekStart.year == weekEnd.year;
    final weekLabel = sameMonth
        ? '${DateFormat('d', localeCode).format(_weekStart)} – ${DateFormat('d MMMM yyyy', localeCode).format(weekEnd)}'
        : '${DateFormat('d MMM', localeCode).format(_weekStart)} – ${DateFormat('d MMM yyyy', localeCode).format(weekEnd)}';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.tr('Classes'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            Text(
              DateFormat('EEEE, d MMMM', localeCode).format(_selectedDay),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
        centerTitle: false,
        scrolledUnderElevation: 2,
        actions: <Widget>[
          if (!_isCurrentWeek())
            FilledButton.tonalIcon(
              onPressed: _goToToday,
              icon: Icon(Icons.today_outlined, size: 16),
              label: Text(context.l10n.tr('Today')),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          SizedBox(width: 8),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: isDesktop
                  ? 1060
                  : isTablet
                      ? 740
                      : double.infinity),
          child: Column(
            children: <Widget>[
              // ── Week navigation ────────────────────────────────────────
              Container(
                color: Theme.of(context).colorScheme.surface,
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: _goToPreviousWeek,
                      icon: Icon(Icons.chevron_left_rounded),
                      tooltip: context.l10n.tr('Previous week'),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          weekLabel,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _goToNextWeek,
                      icon: Icon(Icons.chevron_right_rounded),
                      tooltip: context.l10n.tr('Next week'),
                    ),
                  ],
                ),
              ),

              // ── Day strip ──────────────────────────────────────────────
              StreamBuilder<List<GymClass>>(
                stream: _upcomingClassesStream,
                builder: (context, classSnapshot) {
                  final allClasses = classSnapshot.data ?? <GymClass>[];
                  final classCounts = <DateTime, int>{};
                  for (final c in allClasses) {
                    final key = DateTime(
                        c.startTime.year, c.startTime.month, c.startTime.day);
                    classCounts[key] = (classCounts[key] ?? 0) + 1;
                  }

                  Widget buildChip(int index) {
                    final day = _weekStart.add(Duration(days: index));
                    final isSelected = _isSameDay(day, _selectedDay);
                    final isToday = _isSameDay(day, DateTime.now());
                    final dayKey = DateTime(day.year, day.month, day.day);
                    final count = classCounts[dayKey] ?? 0;
                    final hasClasses = count > 0;

                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _selectDay(day),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 180),
                        padding:
                            EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : isToday
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.08)
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isToday && !isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              DateFormat('EEE', localeCode)
                                  .format(day)
                                  .substring(0, 3)
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              DateFormat('d').format(day),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: isTablet ? 20 : 18,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : isToday
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                              ),
                            ),
                            SizedBox(height: 4),
                            AnimatedOpacity(
                              duration: Duration(milliseconds: 200),
                              opacity: hasClasses ? 1.0 : 0.0,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onPrimary
                                          .withValues(alpha: 0.25)
                                      : Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // On tablet+: all 7 chips fill the width as a Row
                  // On mobile: horizontal scrollable strip
                  return Container(
                    color: Theme.of(context).colorScheme.surface,
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: isTablet
                        ? IntrinsicHeight(
                            child: Row(
                              children: List.generate(
                                7,
                                (i) => Expanded(
                                  child: Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 3),
                                    child: buildChip(i),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : SizedBox(
                            height: 88,
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              scrollDirection: Axis.horizontal,
                              itemCount: 7,
                              itemBuilder: (_, i) => Padding(
                                padding: EdgeInsets.symmetric(horizontal: 3),
                                child: SizedBox(width: 56, child: buildChip(i)),
                              ),
                            ),
                          ),
                  );
                },
              ),

              Divider(height: 1),

              // ── Class list ─────────────────────────────────────────────
              Expanded(
                child: _DayClassList(
                  selectedDay: _selectedDay,
                  userId: user.uid,
                  localeCode: localeCode,
                  gymId: widget.gymId,
                  minAdvanceMinutes: _minAdvanceMinutes,
                  isDesktop: isDesktop,
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
// Day class + PT list (merged)
// ─────────────────────────────────────────────────────────────────────────────

class _DayClassList extends StatefulWidget {
  const _DayClassList({
    required this.selectedDay,
    required this.userId,
    required this.localeCode,
    this.gymId = '',
    this.minAdvanceMinutes = 0,
    this.isDesktop = false,
  });

  final DateTime selectedDay;
  final String userId;
  final String localeCode;
  final String gymId;
  final int minAdvanceMinutes;
  final bool isDesktop;

  @override
  State<_DayClassList> createState() => _DayClassListState();
}

class _DayClassListState extends State<_DayClassList> {
  late final _classService = ClassService(gymId: widget.gymId);
  late final _bookingService = BookingService(gymId: widget.gymId);
  late final _ptService = PersonalTrainingService(gymId: widget.gymId);

  // Cached streams — stable so StreamBuilder never cancels/recreates Firestore
  // listeners when the parent rebuilds with a new selectedDay. Filtering by
  // day is done inside the builder callbacks, not by recreating the stream.
  late final Stream<List<GymClass>> _classesStream;
  late final Stream<List<PersonalTraining>> _ptStream;
  late final Stream<Set<String>> _bookedClassIdsStream;
  late final Stream<Set<String>> _waitlistedClassIdsStream;

  @override
  void initState() {
    super.initState();
    _classesStream = _classService.streamUpcomingClasses();
    _ptStream = _ptService.streamForMember(widget.userId);
    _bookedClassIdsStream = _bookingService.streamBookedClassIds(widget.userId);
    _waitlistedClassIdsStream =
        _bookingService.streamWaitlistedClassIds(widget.userId);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GymClass>>(
      stream: _classesStream,
      builder: (context, classSnap) {
        return StreamBuilder<List<PersonalTraining>>(
          stream: _ptStream,
          builder: (context, ptSnap) {
            if (classSnap.hasError || ptSnap.hasError) {
              return _DayErrorState(
                onRetry: () => setState(() {}),
              );
            }
            if (classSnap.connectionState == ConnectionState.waiting ||
                ptSnap.connectionState == ConnectionState.waiting) {
              return const _DayLoadingSkeleton();
            }

            final classes = (classSnap.data ?? <GymClass>[])
                .where((c) => _isSameDay(c.startTime, widget.selectedDay))
                .toList();
            final ptSessions = (ptSnap.data ?? <PersonalTraining>[])
                .where((s) => _isSameDay(s.startTime, widget.selectedDay))
                .toList();

            if (classes.isEmpty && ptSessions.isEmpty) {
              return _EmptyDayState(
                day: widget.selectedDay,
                localeCode: widget.localeCode,
                isToday: _isSameDay(widget.selectedDay, DateTime.now()),
              );
            }

            // Merge and sort by start time
            final items = <_DayItem>[
              ...classes.map((c) => _DayItem.gymClass(c)),
              ...ptSessions.map((s) => _DayItem.pt(s)),
            ]..sort((a, b) => a.startTime.compareTo(b.startTime));

            return StreamBuilder<Set<String>>(
              stream: _bookedClassIdsStream,
              builder: (context, bookedSnap) {
                final booked = bookedSnap.data ?? {};
                return StreamBuilder<Set<String>>(
                  stream: _waitlistedClassIdsStream,
                  builder: (context, waitSnap) {
                    final waitlisted = waitSnap.data ?? {};

                    Widget buildItem(_DayItem item) {
                      if (item.gymClass != null) {
                        return _ClassCard(
                          gymClass: item.gymClass!,
                          isBooked: booked.contains(item.gymClass!.id),
                          isWaitlisted: waitlisted.contains(item.gymClass!.id),
                          gymId: widget.gymId,
                          minAdvanceMinutes: widget.minAdvanceMinutes,
                        );
                      }
                      return _PtSessionCard(session: item.pt!);
                    }

                    // Desktop: 2-column grid using item pairs
                    if (widget.isDesktop && items.length > 1) {
                      final pairs = <List<_DayItem>>[];
                      for (var i = 0; i < items.length; i += 2) {
                        pairs.add(
                            items.sublist(i, (i + 2).clamp(0, items.length)));
                      }
                      return ListView.builder(
                        padding: EdgeInsets.only(top: 12, bottom: 24),
                        itemCount: pairs.length,
                        itemBuilder: (_, i) {
                          final pair = pairs[i];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: buildItem(pair[0])),
                              if (pair.length > 1)
                                Expanded(child: buildItem(pair[1]))
                              else
                                Expanded(child: SizedBox.shrink()),
                            ],
                          );
                        },
                      );
                    }

                    // Mobile/tablet: single column, grouped by time of day.
                    final clock = GymClock();
                    final rows = <Object>[];
                    SchedulePeriod? lastPeriod;
                    for (final item in items) {
                      final p = clock.gymPeriodOf(item.startTime);
                      if (p != lastPeriod) {
                        rows.add(p);
                        lastPeriod = p;
                      }
                      rows.add(item);
                    }
                    return ListView.builder(
                      padding: EdgeInsets.only(top: 4, bottom: 24),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        if (row is SchedulePeriod) {
                          return _PeriodHeader(period: row);
                        }
                        return buildItem(row as _DayItem);
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

// Lightweight union type for merged list
class _DayItem {
  _DayItem._({this.gymClass, this.pt, required this.startTime});
  factory _DayItem.gymClass(GymClass c) =>
      _DayItem._(gymClass: c, startTime: c.startTime);
  factory _DayItem.pt(PersonalTraining s) =>
      _DayItem._(pt: s, startTime: s.startTime);
  final GymClass? gymClass;
  final PersonalTraining? pt;
  final DateTime startTime;
}

// ─────────────────────────────────────────────────────────────────────────────
// PT Session card (member view)
// ─────────────────────────────────────────────────────────────────────────────

class _PtSessionCard extends StatelessWidget {
  const _PtSessionCard({required this.session});
  final PersonalTraining session;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dur = session.endTime.difference(session.startTime).inMinutes;
    final timeRange = '${DateFormat('HH:mm').format(session.startTime)} – '
        '${DateFormat('HH:mm').format(session.endTime)}';

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _purple.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _purple.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header strip
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _purple.withValues(alpha: 0.12),
                  Color(0xFF4F46E5).withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person_outlined, color: _purple, size: 16),
                ),
                SizedBox(width: 8),
                Text(
                  context.l10n.tr('Private Session'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _purple,
                      letterSpacing: 0.3),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_outlined, size: 11, color: _purple),
                      SizedBox(width: 4),
                      Text(timeRange,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _purple)),
                      SizedBox(width: 4),
                      Text('· $dur ${context.l10n.tr('min')}',
                          style: TextStyle(
                              fontSize: 10,
                              color: _purple.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.title,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),

                SizedBox(height: 6),

                // Coach row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: _purple.withValues(alpha: 0.15),
                      child: Text(
                        session.coachName.isNotEmpty
                            ? session.coachName[0].toUpperCase()
                            : 'C',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: _purple),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '${context.l10n.tr('with')} ${session.coachName}',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),

                if (session.location.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.place_outlined,
                          size: 13, color: cs.onSurfaceVariant),
                      SizedBox(width: 4),
                      Text(session.location,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ],

                if (session.notes.isNotEmpty) ...[
                  SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _purple.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: _purple.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes_outlined,
                            size: 13, color: _purple.withValues(alpha: 0.7)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(session.notes,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.8),
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  ),
                ],

                SizedBox(height: 10),

                // Confirmed badge
                Row(
                  children: [
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 13, color: Colors.green.shade700),
                          SizedBox(width: 5),
                          Text(context.l10n.tr("You're scheduled"),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green.shade700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDayState extends StatelessWidget {
  const _EmptyDayState({
    required this.day,
    required this.localeCode,
    required this.isToday,
  });

  final DateTime day;
  final String localeCode;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dayLabel =
        isToday
            ? context.l10n.tr('Today')
            : DateFormat('EEEE, d MMM', localeCode).format(day);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_available_outlined,
                size: 48,
                color: cs.primary.withValues(alpha: 0.5),
              ),
            ),
            SizedBox(height: 20),
            Text(
              '${context.l10n.tr('No classes on')} $dayLabel',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              context.l10n.tr('Check another day or come back later.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Time-of-day section header ────────────────────────────────────────────────

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.period});
  final SchedulePeriod period;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (IconData icon, String label) = switch (period) {
      SchedulePeriod.morning => (
          Icons.wb_twilight_rounded,
          context.l10n.tr('Morning')
        ),
      SchedulePeriod.afternoon => (
          Icons.wb_sunny_outlined,
          context.l10n.tr('Afternoon')
        ),
      SchedulePeriod.evening => (
          Icons.nightlight_outlined,
          context.l10n.tr('Evening')
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
                height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

// ── Loading skeleton (shown while the day's classes load) ─────────────────────

class _DayLoadingSkeleton extends StatelessWidget {
  const _DayLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              bar(46, 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(150, 14),
                    const SizedBox(height: 8),
                    bar(90, 11),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            bar(double.infinity, 38),
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _DayErrorState extends StatelessWidget {
  const _DayErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              context.l10n.tr("Couldn't load classes"),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.tr('Check your connection and try again.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.l10n.tr('Retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassCard extends StatefulWidget {
  const _ClassCard({
    required this.gymClass,
    required this.isBooked,
    required this.isWaitlisted,
    this.gymId = '',
    this.minAdvanceMinutes = 0,
  });

  final GymClass gymClass;
  final bool isBooked;
  final bool isWaitlisted;
  final String gymId;
  final int minAdvanceMinutes;

  @override
  State<_ClassCard> createState() => _ClassCardState();
}

class _ClassCardState extends State<_ClassCard> {
  late final _bookingService = BookingService(gymId: widget.gymId);
  bool _isWorking = false;

  String _friendlyBookingError(Object error) {
    final raw = error.toString();

    if (raw.contains('You need an active assigned offer to book classes.')) {
      return context.l10n.tr('You need an active offer to book this class.');
    }

    if (raw.contains('This class requires a specific offer.')) {
      return context.l10n
          .tr('You do not have the required offer for this class.');
    }

    if (raw.contains('Your assigned offer is not valid for this class date.')) {
      return context.l10n
          .tr('Your offer is expired or not valid for this class date.');
    }

    if (raw.startsWith('Exception: ')) {
      return raw.replaceFirst('Exception: ', '');
    }

    return raw;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _openDetails() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassDetailsScreen(
          gymClass: widget.gymClass,
          gymId: widget.gymId,
        ),
      ),
    );
  }

  Future<void> _bookClass() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() {
      _isWorking = true;
    });

    try {
      final result = await _bookingService.bookClass(
        userId: user.uid,
        classId: widget.gymClass.id,
      );

      if (!mounted) {
        return;
      }

      final message = result == BookingResult.booked
          ? context.l10n.tr('Class booked successfully.')
          : context.l10n.tr('Class is full. You were added to the waitlist.');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar(_friendlyBookingError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Future<void> _cancelBooking() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() {
      _isWorking = true;
    });

    try {
      await _bookingService.cancelBooking(
        userId: user.uid,
        classId: widget.gymClass.id,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('Booking cancelled.'))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar(_friendlyBookingError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Future<void> _leaveWaitlist() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() {
      _isWorking = true;
    });

    try {
      await _bookingService.leaveWaitlist(
        userId: user.uid,
        classId: widget.gymClass.id,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('Removed from waitlist.'))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar(_friendlyBookingError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final gc = widget.gymClass;
    final now = DateTime.now();
    final isNow = now.isAfter(gc.startTime) && now.isBefore(gc.endTime);
    final isPast = gc.endTime.isBefore(now);

    final hasCustomColor = gc.classColorValue != null;
    final accentColor = hasCustomColor
        ? Color(gc.classColorValue!)
        : Theme.of(context).colorScheme.primary;
    final cardBg = hasCustomColor
        ? Color(gc.classColorValue!)
        : Theme.of(context).colorScheme.surface;
    final useDarkText = cardBg.computeLuminance() > 0.45;
    final textColor = useDarkText ? Colors.black87 : Colors.white;
    final mutedColor =
        useDarkText ? Colors.black54 : Colors.white.withValues(alpha: 0.75);

    final durationMin = gc.endTime.difference(gc.startTime).inMinutes;
    final spotsLeft = gc.capacity - gc.bookedCount;
    final occupancyRatio =
        gc.capacity <= 0 ? 0.0 : (gc.bookedCount / gc.capacity).clamp(0.0, 1.0);
    final isAlmostFull = !gc.isFull && spotsLeft <= 3;

    // Coaches display
    final coaches = gc.coachNames.isNotEmpty
        ? gc.coachNames
        : gc.coachName
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
    final coachDisplay = coaches.isEmpty
        ? ''
        : coaches.take(2).join(', ') +
            (coaches.length > 2 ? ' +${coaches.length - 2}' : '');

    // Button state
    String buttonLabel = context.l10n.tr('Book');
    IconData buttonIcon = Icons.add_circle_outline;
    VoidCallback? onPressed = _bookClass;
    Color? btnBg;
    Color? btnFg;

    if (widget.isBooked) {
      buttonLabel = context.l10n.tr('Cancel');
      buttonIcon = Icons.cancel_outlined;
      onPressed = _cancelBooking;
      btnBg = Colors.red.shade600;
      btnFg = Colors.white;
    } else if (widget.isWaitlisted) {
      buttonLabel = context.l10n.tr('Leave waitlist');
      buttonIcon = Icons.remove_circle_outline;
      onPressed = _leaveWaitlist;
      btnBg = Colors.orange.shade700;
      btnFg = Colors.white;
    } else if (gc.isFull) {
      buttonLabel = context.l10n.tr('Join waitlist');
      buttonIcon = Icons.queue_outlined;
      onPressed = _bookClass;
    } else if (hasCustomColor) {
      btnBg = useDarkText ? Colors.black87 : Colors.white;
      btnFg = useDarkText ? Colors.white : Colors.black87;
    }

    // Booking window check: block if too far in advance
    if (!widget.isBooked && !widget.isWaitlisted && !isPast) {
      final minAdv = widget.minAdvanceMinutes;
      if (minAdv > 0) {
        final minutesUntilClass = gc.startTime.difference(now).inMinutes;
        if (minutesUntilClass > minAdv) {
          final opensAt = gc.startTime.subtract(Duration(minutes: minAdv));
          final hm =
              '${opensAt.hour.toString().padLeft(2, '0')}:${opensAt.minute.toString().padLeft(2, '0')}';
          buttonLabel = '${context.l10n.tr('Opens at')} $hm';
          buttonIcon = Icons.schedule;
          onPressed = null;
          btnBg = Colors.grey.shade300;
          btnFg = Colors.grey.shade700;
        }
      }
    }

    // Past classes: show a clear "ended" state rather than a dead Cancel button.
    if (isPast) {
      buttonLabel = context.l10n.tr('Class ended');
      buttonIcon = Icons.check_circle_outline;
      btnBg = Colors.grey.shade300;
      btnFg = Colors.grey.shade700;
    }
    if (_isWorking || isPast) onPressed = null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 140),
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isPast
              ? (hasCustomColor
                  ? cardBg.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.surfaceContainerLowest)
              : cardBg,
          borderRadius: BorderRadius.circular(18),
          border: hasCustomColor
              ? (_isHovered
                  ? Border.all(
                      color: accentColor.withValues(alpha: 0.6), width: 1.5)
                  : null)
              : Border.all(
                  color: isNow
                      ? accentColor.withValues(alpha: 0.5)
                      : _isHovered
                          ? accentColor.withValues(alpha: 0.4)
                          : Theme.of(context).colorScheme.outlineVariant,
                  width: isNow || _isHovered ? 1.5 : 1,
                ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(
                  alpha: hasCustomColor ? 0.12 : (_isHovered ? 0.08 : 0.04)),
              blurRadius: _isHovered ? 16 : (hasCustomColor ? 14 : 6),
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: _openDetails,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ── Left accent bar ──────────────────────────────────
                  Container(
                    width: 5,
                    color: isPast
                        ? accentColor.withValues(alpha: 0.35)
                        : accentColor.withValues(
                            alpha: hasCustomColor ? 0.5 : 1.0),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // ── Top row: time + duration + badges ─────────
                          Row(
                            children: <Widget>[
                              _InfoPill(
                                icon: Icons.access_time,
                                label:
                                    '${DateFormat('HH:mm', localeCode).format(gc.startTime)} → ${DateFormat('HH:mm', localeCode).format(gc.endTime)}',
                                textColor: textColor,
                                bgColor: useDarkText
                                    ? Colors.black.withValues(alpha: 0.07)
                                    : Colors.white.withValues(alpha: 0.18),
                              ),
                              SizedBox(width: 5),
                              _InfoPill(
                                icon: Icons.timer_outlined,
                                label: '$durationMin${context.l10n.tr('min')}',
                                textColor: mutedColor,
                                bgColor: Colors.transparent,
                              ),
                              Spacer(),
                              if (isNow) _LiveNowBadge(color: textColor),
                              if (isPast && !isNow)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    context.l10n.tr('PAST'),
                                    style: TextStyle(
                                      color: mutedColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              if (!isNow && !isPast) _buildStatusBadge(context),
                            ],
                          ),
                          SizedBox(height: 10),

                          // ── Title ──────────────────────────────────────
                          Text(
                            gc.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: isPast ? mutedColor : textColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          SizedBox(height: 5),

                          // ── Coach row ──────────────────────────────────
                          if (coachDisplay.isNotEmpty)
                            Row(
                              children: <Widget>[
                                Icon(Icons.person_outline,
                                    size: 14, color: mutedColor),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    coachDisplay,
                                    style: TextStyle(
                                        color: mutedColor, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                          if (gc.requiredOfferPlanId.isNotEmpty) ...<Widget>[
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.workspace_premium_outlined,
                                    size: 13, color: mutedColor),
                                SizedBox(width: 4),
                                Text(
                                  context.l10n.tr('Offer required'),
                                  style: TextStyle(
                                      color: mutedColor, fontSize: 12),
                                ),
                              ],
                            ),
                          ],

                          if (gc.dropInEnabled) ...<Widget>[
                            SizedBox(height: 4),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    Color(0xFFEA580C).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Color(0xFFEA580C)
                                        .withValues(alpha: 0.35)),
                              ),
                              child: Text(
                                '${context.l10n.tr('Drop-in')} · ${Currency.format(gc.dropInPrice, null)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFEA580C),
                                ),
                              ),
                            ),
                          ],

                          if (gc.description.isNotEmpty) ...<Widget>[
                            SizedBox(height: 6),
                            Text(
                              gc.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: mutedColor, fontSize: 13),
                            ),
                          ],

                          SizedBox(height: 12),

                          // ── Occupancy bar ──────────────────────────────
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: occupancyRatio,
                              minHeight: 5,
                              backgroundColor: useDarkText
                                  ? Colors.black.withValues(alpha: 0.1)
                                  : Colors.white.withValues(alpha: 0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _occupancyColor(occupancyRatio, useDarkText),
                              ),
                            ),
                          ),
                          SizedBox(height: 8),

                          // ── Bottom row: spots + action button ──────────
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      '${gc.bookedCount}/${gc.capacity} ${context.l10n.tr('booked')}',
                                      style: TextStyle(
                                          color: mutedColor, fontSize: 12),
                                    ),
                                    if (isAlmostFull)
                                      Text(
                                        '$spotsLeft ${context.l10n.tr('spots left')}!',
                                        style: TextStyle(
                                          color: useDarkText
                                              ? Colors.orange.shade800
                                              : Colors.yellow.shade200,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    else if (gc.waitlistCount > 0)
                                      Text(
                                        '+${gc.waitlistCount} ${context.l10n.tr('waitlisted')}',
                                        style: TextStyle(
                                            color: mutedColor, fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                              if (!isPast)
                                FilledButton.icon(
                                  onPressed: onPressed,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: btnBg,
                                    foregroundColor: btnFg,
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: _isWorking
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Icon(buttonIcon, size: 16),
                                  label: Text(buttonLabel,
                                      style: TextStyle(fontSize: 13)),
                                )
                              else if (widget.isBooked)
                                // Past but was booked → attended badge
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade600
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.green.shade600
                                            .withValues(alpha: 0.35)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_outline,
                                          size: 13,
                                          color: Colors.green.shade600),
                                      SizedBox(width: 5),
                                      Text(
                                        context.l10n.tr('Attended'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.green.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _occupancyColor(double ratio, bool useDarkText) {
    if (ratio >= 1.0) {
      return useDarkText ? Colors.red.shade700 : Colors.red.shade300;
    }
    if (ratio >= 0.75) {
      return useDarkText ? Colors.orange.shade700 : Colors.orange.shade300;
    }
    return useDarkText ? Colors.black87 : Colors.white;
  }

  Widget _buildStatusBadge(BuildContext context) {
    if (widget.isBooked) {
      return _StatusBadge(
          label: context.l10n.tr('Booked'),
          bg: Colors.green.shade600,
          fg: Colors.white,
          icon: Icons.check_circle_outline);
    }
    if (widget.isWaitlisted) {
      return _StatusBadge(
          label: context.l10n.tr('Waitlist'),
          bg: Colors.orange.shade600,
          fg: Colors.white,
          icon: Icons.hourglass_top_outlined);
    }
    if (widget.gymClass.isFull) {
      return _StatusBadge(
          label: context.l10n.tr('Full'),
          bg: Colors.red.shade600,
          fg: Colors.white,
          icon: Icons.block_outlined);
    }
    return SizedBox.shrink();
  }
}

class _LiveNowBadge extends StatelessWidget {
  const _LiveNowBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: 4),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 5),
          Text(
            context.l10n.tr('LIVE'),
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.bgColor,
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: textColor),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.bg,
    required this.fg,
    required this.icon,
  });

  final String label;
  final Color bg;
  final Color fg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: fg),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscription gate — shown when hideClassesWithoutSubscription is enabled
// and the current member has no active subscription.
// ─────────────────────────────────────────────────────────────────────────────

class _NoSubscriptionGate extends StatelessWidget {
  const _NoSubscriptionGate({required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(l10n.tr('Classes'),
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 20)),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 56,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.tr('Subscription required'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.tr(
                    'You need an active membership to view and book classes. Contact your gym or browse available offers.'),
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MembershipScreen(gymId: gymId),
                  ),
                ),
                icon: const Icon(Icons.card_membership_outlined, size: 18),
                label: Text(l10n.tr('View membership offers')),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
