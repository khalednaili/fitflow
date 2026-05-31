import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/booking.dart';
import '../../models/gym_class.dart';
import '../../models/personal_training.dart';
import '../../models/user_subscription.dart';
import '../../models/waitlist_entry.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import '../../services/member_service.dart';
import '../../services/personal_training_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/user_avatar.dart';
import '../admin/admin_calendar_screen.dart';
import '../admin/member_detail_screen.dart';
import '../admin/tabs/admin_personal_training_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

class CoachPortalScreen extends StatelessWidget {
  const CoachPortalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
          body: Center(child: Text(context.l10n.tr('Not signed in.'))));
    }
    return StreamBuilder<AppUser?>(
      stream: MemberService().streamUser(uid),
      builder: (context, snap) {
        final coach = snap.data;
        if (coach == null) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!coach.isAdmin && !coach.isStaff && coach.role != 'coach') {
          return Scaffold(
              body: Center(
                  child:
                      Text(context.l10n.tr('Access restricted to coaches.'))));
        }
        return _CoachPortalBody(coach: coach);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────────────

class _CoachPortalBody extends StatefulWidget {
  const _CoachPortalBody({required this.coach});
  final AppUser coach;

  @override
  State<_CoachPortalBody> createState() => _CoachPortalBodyState();
}

class _CoachPortalBodyState extends State<_CoachPortalBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tc = TabController(length: 7, vsync: this);
  late final _classService = ClassService(gymId: widget.coach.gymId);

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final coach = widget.coach;
    final name = coach.displayName.isNotEmpty ? coach.displayName : coach.email;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: Column(
        children: [
          // ── Gradient profile banner ──────────────────────────────────
          _CoachBanner(coach: coach, name: name, classService: _classService),
          // ── Pinned tab bar ───────────────────────────────────────────
          Container(
            color: Color(0xFF0F766E),
            child: TabBar(
              controller: _tc,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wb_sunny_outlined, size: 15),
                    SizedBox(width: 6),
                    Text(context.l10n.tr('Today')),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.calendar_view_week_outlined, size: 15),
                    SizedBox(width: 6),
                    Text(context.l10n.tr('Week')),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history_outlined, size: 15),
                    SizedBox(width: 6),
                    Text(context.l10n.tr('History')),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.calendar_month_outlined, size: 15),
                    SizedBox(width: 6),
                    Text(context.l10n.tr('Calendar')),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_person_outlined, size: 15),
                    SizedBox(width: 6),
                    Text(context.l10n.tr('Private PT')),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bar_chart_rounded, size: 15),
                    SizedBox(width: 6),
                    Text(context.l10n.tr('Stats')),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.swap_horiz_outlined, size: 15),
                    SizedBox(width: 6),
                    Text(context.l10n.tr('Cover')),
                  ]),
                ),
              ],
            ),
          ),
          // ── Tab content ──────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tc,
              children: [
                _TodayTab(coachId: coach.id, classService: _classService),
                _WeekTab(coachId: coach.id, classService: _classService),
                _HistoryTab(coachId: coach.id, classService: _classService),
                AdminCalendarScreen(
                  gymId: coach.gymId,
                  readOnly: true,
                  ptCoachId: coach.id,
                ),
                _CoachPtTab(
                  coachId: coach.id,
                  gymId: coach.gymId,
                ),
                _StatsTab(coachId: coach.id, classService: _classService),
                _CoverTab(
                  coach: coach,
                  classService: _classService,
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
// Week stats chip (# classes this week)
// ─────────────────────────────────────────────────────────────────────────────

class _WeekStatsChip extends StatelessWidget {
  const _WeekStatsChip({required this.coachId, required this.classService});
  final String coachId;
  final ClassService classService;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(Duration(days: 6, hours: 23, minutes: 59));

    return StreamBuilder<List<GymClass>>(
      stream: classService.streamAllClassesForCoach(coachId),
      builder: (ctx, snap) {
        final thisWeek = (snap.data ?? [])
            .where((c) =>
                c.startTime.isAfter(monday.subtract(Duration(seconds: 1))) &&
                c.startTime.isBefore(sunday))
            .length;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$thisWeek',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              Text(context.l10n.tr('this week'),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8), fontSize: 9)),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coach profile banner (replaces FlexibleSpaceBar)
// ─────────────────────────────────────────────────────────────────────────────

class _CoachBanner extends StatelessWidget {
  const _CoachBanner({
    required this.coach,
    required this.name,
    required this.classService,
  });
  final AppUser coach;
  final String name;
  final ClassService classService;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          // Avatar
          UserAvatar(
            photoUrl: coach.photoUrl,
            initials: name.isNotEmpty ? name[0].toUpperCase() : 'C',
            color: Colors.white,
            radius: 26,
          ),
          SizedBox(width: 14),
          // Name + role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.tr('Welcome back,'),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11)),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                _RoleBadge(role: coach.role),
              ],
            ),
          ),
          SizedBox(width: 12),
          // Week stats
          _WeekStatsChip(coachId: coach.id, classService: classService),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TODAY TAB
// ─────────────────────────────────────────────────────────────────────────────

class _TodayTab extends StatelessWidget {
  const _TodayTab({required this.coachId, required this.classService});
  final String coachId;
  final ClassService classService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();

    return StreamBuilder<List<GymClass>>(
      stream: classService.streamAllClassesForCoach(coachId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        final all = snap.data ?? [];
        final todayClasses = all
            .where((c) => DateUtils.isSameDay(c.startTime, today))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            // ── Next class countdown ────────────────────────────────
            _NextClassBanner(classes: todayClasses),
            SizedBox(height: 16),

            // ── Today summary stats ─────────────────────────────────
            _TodayStatRow(classes: todayClasses),
            SizedBox(height: 20),

            // ── Section label ───────────────────────────────────────
            _SectionHeader(
              icon: Icons.today,
              label:
                  '${context.l10n.tr('Today')} · ${DateFormat('EEEE d MMMM').format(today)}',
              color: cs.primary,
            ),
            SizedBox(height: 10),

            // ── Class cards ─────────────────────────────────────────
            if (todayClasses.isEmpty)
              _EmptyState(
                icon: Icons.free_breakfast_outlined,
                message: context.l10n.tr('No classes scheduled for today.'),
                sub: context.l10n.tr('Enjoy your rest day! 🧘'),
              )
            else
              ...todayClasses.map((c) => _ClassCard(gymClass: c)),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEEK TAB
// ─────────────────────────────────────────────────────────────────────────────

class _WeekTab extends StatefulWidget {
  const _WeekTab({required this.coachId, required this.classService});
  final String coachId;
  final ClassService classService;

  @override
  State<_WeekTab> createState() => _WeekTabState();
}

class _WeekTabState extends State<_WeekTab> {
  // Week offset: 0 = current week, 1 = next week, -1 = last week
  int _weekOffset = 0;
  int _selectedDayIndex = DateTime.now().weekday - 1; // 0=Mon … 6=Sun

  DateTime get _monday {
    final now = DateTime.now();
    final thisMonday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(thisMonday.year, thisMonday.month, thisMonday.day)
        .add(Duration(days: _weekOffset * 7));
  }

  List<DateTime> get _weekDays =>
      List.generate(7, (i) => _monday.add(Duration(days: i)));

  DateTime get _selectedDay => _weekDays[_selectedDayIndex];

  String get _weekLabel {
    final m = _monday;
    final sun = m.add(Duration(days: 6));
    return '${DateFormat('MMM d').format(m)} – ${DateFormat('MMM d').format(sun)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<GymClass>>(
      stream: widget.classService.streamAllClassesForCoach(widget.coachId),
      builder: (context, snap) {
        final all = snap.data ?? [];

        // Group by day of week index (0=Mon)
        final byDay = <int, List<GymClass>>{};
        for (final c in all) {
          final day =
              _weekDays.indexWhere((d) => DateUtils.isSameDay(d, c.startTime));
          if (day >= 0) byDay.putIfAbsent(day, () => []).add(c);
        }

        final dayClasses = (byDay[_selectedDayIndex] ?? [])
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        return Column(
          children: [
            // ── Week navigation bar ──────────────────────────────────
            Container(
              color: cs.surface,
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _weekOffset--),
                    tooltip: context.l10n.tr('Previous week'),
                  ),
                  Expanded(
                    child: Text(_weekLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right),
                    onPressed: () => setState(() => _weekOffset++),
                    tooltip: context.l10n.tr('Next week'),
                  ),
                  if (_weekOffset != 0)
                    TextButton(
                      onPressed: () => setState(() {
                        _weekOffset = 0;
                        _selectedDayIndex = DateTime.now().weekday - 1;
                      }),
                      child: Text(context.l10n.tr('Today')),
                    ),
                ],
              ),
            ),

            // ── Day selector pills ────────────────────────────────────
            Container(
              color: cs.surface,
              padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: List.generate(7, (i) {
                  final d = _weekDays[i];
                  final isSelected = i == _selectedDayIndex;
                  final isToday = DateUtils.isSameDay(d, DateTime.now());
                  final count = byDay[i]?.length ?? 0;
                  final hasClass = count > 0;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedDayIndex = i),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 180),
                        margin: EdgeInsets.symmetric(horizontal: 3),
                        padding: EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : isToday
                                  ? cs.primaryContainer
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              DateFormat('E').format(d)[0],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? cs.onPrimary
                                    : isToday
                                        ? cs.onPrimaryContainer
                                        : cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              d.day.toString(),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? cs.onPrimary : cs.onSurface,
                              ),
                            ),
                            SizedBox(height: 3),
                            // Count badge — shows number when there are classes
                            AnimatedSwitcher(
                              duration: Duration(milliseconds: 180),
                              child: hasClass
                                  ? Container(
                                      key: ValueKey(count),
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? cs.onPrimary
                                                .withValues(alpha: 0.25)
                                            : cs.primary
                                                .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        count > 9 ? '9+' : '$count',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: isSelected
                                              ? cs.onPrimary
                                              : cs.primary,
                                        ),
                                      ),
                                    )
                                  : SizedBox(height: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            Divider(height: 1),

            // ── Day's classes ─────────────────────────────────────────
            Expanded(
              child: dayClasses.isEmpty
                  ? _EmptyState(
                      icon: Icons.event_available_outlined,
                      message:
                          '${context.l10n.tr('No classes on')} ${DateFormat('EEEE').format(_selectedDay)}.',
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 80),
                      children: [
                        _DayTimeline(classes: dayClasses),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HISTORY TAB
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.coachId, required this.classService});
  final String coachId;
  final ClassService classService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GymClass>>(
      stream: classService.streamAllClassesForCoach(coachId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        final now = DateTime.now();
        final past = (snap.data ?? [])
            .where((c) => c.endTime.isBefore(now))
            .toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));

        if (past.isEmpty) {
          return _EmptyState(
            icon: Icons.history_edu_outlined,
            message: context.l10n.tr('No past classes yet.'),
          );
        }

        // Group by month
        final grouped = <String, List<GymClass>>{};
        for (final c in past) {
          final key = DateFormat('MMMM yyyy').format(c.startTime);
          grouped.putIfAbsent(key, () => []).add(c);
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 80),
          children: [
            for (final entry in grouped.entries) ...[
              _SectionHeader(
                  icon: Icons.calendar_month_outlined, label: entry.key),
              SizedBox(height: 6),
              // Monthly summary row
              _MonthSummaryRow(classes: entry.value),
              SizedBox(height: 8),
              ...entry.value.map((c) => _ClassCard(gymClass: c, isPast: true)),
              SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Next class banner
// ─────────────────────────────────────────────────────────────────────────────

class _NextClassBanner extends StatefulWidget {
  const _NextClassBanner({required this.classes});
  final List<GymClass> classes;

  @override
  State<_NextClassBanner> createState() => _NextClassBannerState();
}

class _NextClassBannerState extends State<_NextClassBanner> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final next =
        widget.classes.where((c) => c.startTime.isAfter(now)).firstOrNull;

    if (next == null) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: Colors.green.shade600, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.classes.isEmpty
                    ? context.l10n.tr('No classes today — enjoy your day!')
                    : context.l10n.tr('All classes done for today 🎉'),
                style: TextStyle(
                    color: Colors.green.shade800, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final diff = next.startTime.difference(now);
    final hoursLeft = diff.inHours;
    final minsLeft = diff.inMinutes % 60;

    String timeLabel;
    if (diff.inMinutes < 1) {
      timeLabel = context.l10n.tr('Starting now!');
    } else if (hoursLeft == 0) {
      timeLabel =
          '${context.l10n.tr('in')} $minsLeft ${context.l10n.tr('min')}';
    } else if (minsLeft == 0) {
      timeLabel = '${context.l10n.tr('in')} ${hoursLeft}h';
    } else {
      timeLabel = '${context.l10n.tr('in')} ${hoursLeft}h ${minsLeft}m';
    }

    final fillPct = next.capacity > 0
        ? (next.bookedCount / next.capacity * 100).round()
        : 0;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.75)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: cs.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.tr('Next class'),
                    style: TextStyle(
                        color: cs.onPrimary.withValues(alpha: 0.8),
                        fontSize: 12)),
                SizedBox(height: 4),
                Text(next.title,
                    style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.schedule,
                      size: 13, color: cs.onPrimary.withValues(alpha: 0.8)),
                  SizedBox(width: 4),
                  Text(DateFormat('HH:mm').format(next.startTime),
                      style: TextStyle(
                          color: cs.onPrimary.withValues(alpha: 0.9),
                          fontSize: 12)),
                  SizedBox(width: 12),
                  Icon(Icons.people_outline,
                      size: 13, color: cs.onPrimary.withValues(alpha: 0.8)),
                  SizedBox(width: 4),
                  Text('${next.bookedCount}/${next.capacity}',
                      style: TextStyle(
                          color: cs.onPrimary.withValues(alpha: 0.9),
                          fontSize: 12)),
                  SizedBox(width: 8),
                  // Fill rate pill
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$fillPct%',
                        style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(timeLabel,
                    style: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ),
              SizedBox(height: 6),
              // Mini capacity bar
              SizedBox(
                width: 80,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: next.capacity > 0
                        ? (next.bookedCount / next.capacity).clamp(0.0, 1.0)
                        : 0,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    color: next.isFull
                        ? Colors.orange
                        : Colors.white.withValues(alpha: 0.85),
                    minHeight: 5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Today stat row
// ─────────────────────────────────────────────────────────────────────────────

class _TodayStatRow extends StatelessWidget {
  const _TodayStatRow({required this.classes});
  final List<GymClass> classes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalCapacity = classes.fold(0, (s, c) => s + c.capacity);
    final totalBooked = classes.fold(0, (s, c) => s + c.bookedCount);
    final fillRate = totalCapacity > 0
        ? (totalBooked / totalCapacity * 100).round().clamp(0, 100)
        : 0;

    final stats = [
      _Stat(context.l10n.tr('Classes'), classes.length.toString(), Icons.event),
      _Stat(context.l10n.tr('Members'), totalBooked.toString(), Icons.people),
      _Stat(
          context.l10n.tr('Fill rate'), '$fillRate%', Icons.bar_chart_outlined),
    ];

    return Row(
      children: [
        for (int i = 0; i < stats.length; i++)
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 4),
              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                children: [
                  Icon(stats[i].icon,
                      color: i == 2
                          ? (fillRate >= 90
                              ? Colors.orange
                              : fillRate >= 70
                                  ? Colors.amber.shade700
                                  : cs.primary)
                          : cs.primary,
                      size: 20),
                  SizedBox(height: 6),
                  Text(stats[i].value,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: i == 2
                              ? (fillRate >= 90
                                  ? Colors.orange
                                  : fillRate >= 70
                                      ? Colors.amber.shade700
                                      : cs.onSurface)
                              : cs.onSurface)),
                  Text(stats[i].label,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

// ─────────────────────────────────────────────────────────────────────────────
// Day timeline (week view)
// ─────────────────────────────────────────────────────────────────────────────

class _DayTimeline extends StatelessWidget {
  const _DayTimeline({required this.classes});
  final List<GymClass> classes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (int i = 0; i < classes.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time column
              SizedBox(
                width: 52,
                child: Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    DateFormat('HH:mm').format(classes[i].startTime),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.primary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // Line + dot
              Column(
                children: [
                  SizedBox(height: 18),
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: cs.primary, shape: BoxShape.circle)),
                  if (i < classes.length - 1)
                    Container(
                        width: 2,
                        height: 80,
                        color: cs.primary.withValues(alpha: 0.2)),
                ],
              ),
              SizedBox(width: 10),
              // Card
              Expanded(
                child: _ClassCard(gymClass: classes[i]),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Class card
// ─────────────────────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.gymClass, this.isPast = false});
  final GymClass gymClass;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(gymClass.startTime, now);
    final isNow =
        gymClass.startTime.isBefore(now) && gymClass.endTime.isAfter(now);
    final color = gymClass.classColorValue != null
        ? Color(gymClass.classColorValue!)
        : cs.primary;

    return Card(
      margin: EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isNow
              ? color
              : isToday
                  ? color.withValues(alpha: 0.4)
                  : cs.outlineVariant,
          width: isNow ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isNow)
                    _StatusBadge(
                        label: context.l10n.tr('IN PROGRESS'), color: color),
                  if (!isNow && isToday && !isPast)
                    _StatusBadge(
                        label: context.l10n.tr('TODAY'), color: cs.primary),
                  Expanded(
                    child: Text(gymClass.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  if (isPast)
                    Icon(Icons.check_circle,
                        size: 18, color: Colors.green.shade600),
                ],
              ),
              SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.schedule_outlined,
                      size: 13, color: cs.onSurfaceVariant),
                  SizedBox(width: 4),
                  Text(
                    '${DateFormat('HH:mm').format(gymClass.startTime)} – ${DateFormat('HH:mm').format(gymClass.endTime)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  Spacer(),
                  Icon(Icons.people_outline,
                      size: 13, color: cs.onSurfaceVariant),
                  SizedBox(width: 4),
                  Text('${gymClass.bookedCount}/${gymClass.capacity}',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: gymClass.capacity > 0
                      ? gymClass.bookedCount / gymClass.capacity
                      : 0,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: gymClass.isFull ? Colors.orange : color,
                  minHeight: 4,
                ),
              ),
              SizedBox(height: 10),
              if (gymClass.coachNote.isNotEmpty) ...[
                Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sticky_note_2_outlined,
                          size: 13, color: cs.onSurfaceVariant),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          gymClass.coachNote,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openRoster(context),
                      icon: Icon(Icons.people_outline, size: 15),
                      label: Text(context.l10n.tr('Roster'),
                          style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (!isPast) ...[
                    SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openCheckIn(context),
                        icon: Icon(Icons.how_to_reg_outlined, size: 15),
                        label: Text(context.l10n.tr('Check-in'),
                            style: TextStyle(fontSize: 13)),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => _openNoteEditor(context),
                    icon: Icon(
                      gymClass.coachNote.isNotEmpty
                          ? Icons.edit_note
                          : Icons.add_comment_outlined,
                      size: 18,
                    ),
                    tooltip: context.l10n.tr('Edit note'),
                    style: IconButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                      padding: EdgeInsets.all(6),
                      minimumSize: Size(32, 32),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _openNotifyDialog(context),
                    icon: Icon(Icons.campaign_outlined, size: 18),
                    tooltip: context.l10n.tr('Notify members'),
                    style: IconButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                      padding: EdgeInsets.all(6),
                      minimumSize: Size(32, 32),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ClassDetailSheet(gymClass: gymClass),
    );
  }

  void _openRoster(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RosterSheet(gymClass: gymClass),
    );
  }

  void _openCheckIn(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CheckInSheet(gymClass: gymClass),
    );
  }

  void _openNoteEditor(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NoteEditorSheet(gymClass: gymClass),
    );
  }

  void _openNotifyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _NotifyDialog(gymClass: gymClass),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(right: 8),
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Roster bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _RosterSheet extends StatefulWidget {
  const _RosterSheet({required this.gymClass});
  final GymClass gymClass;

  @override
  State<_RosterSheet> createState() => _RosterSheetState();
}

class _RosterSheetState extends State<_RosterSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openBookMember(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BookMemberSheet(gymClass: widget.gymClass),
    );
  }

  void _openMemberProfile(BuildContext context, AppUser? user, String name) {
    if (user == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _MemberProfileSheet(user: user, gymId: widget.gymClass.gymId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookingService = BookingService(gymId: widget.gymClass.gymId);
    final memberService = MemberService(gymId: widget.gymClass.gymId);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, ctrl) => DefaultTabController(
        length: 2,
        child: Column(
          children: [
            _SheetHandle(),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.people_outline, color: cs.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${context.l10n.tr('Roster')} — ${widget.gymClass.title}',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                      '${widget.gymClass.bookedCount}/${widget.gymClass.capacity}',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openBookMember(context),
                    icon: Icon(Icons.person_add_outlined, size: 16),
                    label: Text(context.l10n.tr('Book Member')),
                    style: FilledButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: StreamBuilder<List<Booking>>(
              stream: bookingService.streamBookingsForClass(widget.gymClass.id),
              builder: (context, bookingsSnap) {
                final bookings = bookingsSnap.data ?? [];
                return StreamBuilder<List<WaitlistEntry>>(
                  stream:
                      bookingService.streamWaitlistForClass(widget.gymClass.id),
                  builder: (context, waitlistSnap) {
                    final waitlist = waitlistSnap.data ?? [];
                    return StreamBuilder<Set<String>>(
                      stream: bookingService
                          .streamCheckedInUserIds(widget.gymClass.id),
                      builder: (context, checkedInSnap) {
                        final checkedInIds = checkedInSnap.data ?? <String>{};
                        return StreamBuilder<List<AppUser>>(
                          stream: memberService.streamMembers(),
                          builder: (context, membersSnap) {
                            final memberMap = {
                              for (final m in membersSnap.data ?? <AppUser>[])
                                m.id: m,
                            };
                            final filtered = _query.isEmpty
                                ? bookings
                                : bookings.where((b) {
                                    final u = memberMap[b.userId];
                                    final nameLower =
                                        (u?.displayName.isNotEmpty == true
                                                ? u!.displayName
                                                : u?.email ?? b.userId)
                                            .toLowerCase();
                                    return nameLower.contains(_query) ||
                                        (u?.email ?? '')
                                            .toLowerCase()
                                            .contains(_query);
                                  }).toList();

                            return Column(
                              children: [
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                                    child: TabBar(
                                      tabs: [
                                        Tab(
                                          text:
                                              '${context.l10n.tr('Booked')} (${bookings.length})',
                                        ),
                                        Tab(
                                          text:
                                              '${context.l10n.tr('Waitlist')} (${waitlist.length})',
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      children: [
                                        Column(
                                          children: [
                                            Padding(
                                              padding: EdgeInsets.fromLTRB(
                                                  16, 0, 16, 8),
                                              child: TextField(
                                                controller: _searchCtrl,
                                                onChanged: (v) => setState(() =>
                                                    _query =
                                                        v.trim().toLowerCase()),
                                                decoration: InputDecoration(
                                                  hintText: context.l10n
                                                      .tr('Search member…'),
                                                  prefixIcon: Icon(Icons.search,
                                                      size: 20),
                                                  suffixIcon: _query.isNotEmpty
                                                      ? IconButton(
                                                          icon: Icon(
                                                              Icons.clear,
                                                              size: 18),
                                                          onPressed: () {
                                                            _searchCtrl.clear();
                                                            setState(() =>
                                                                _query = '');
                                                          },
                                                        )
                                                      : null,
                                                  isDense: true,
                                                  filled: true,
                                                  fillColor:
                                                      cs.surfaceContainerLowest,
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    borderSide: BorderSide(
                                                        color:
                                                            cs.outlineVariant),
                                                  ),
                                                  enabledBorder:
                                                      OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    borderSide: BorderSide(
                                                        color:
                                                            cs.outlineVariant),
                                                  ),
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          vertical: 10),
                                                ),
                                              ),
                                            ),
                                            Divider(height: 1),
                                            Expanded(
                                              child: bookings.isEmpty
                                                  ? Center(
                                                      child: Text(
                                                        context.l10n.tr(
                                                            'No bookings yet.'),
                                                        style: TextStyle(
                                                            color: cs
                                                                .onSurfaceVariant),
                                                      ),
                                                    )
                                                  : filtered.isEmpty
                                                      ? Center(
                                                          child: Text(
                                                            context.l10n.tr(
                                                                'No members found.'),
                                                            style: TextStyle(
                                                                color: cs
                                                                    .onSurfaceVariant),
                                                          ),
                                                        )
                                                      : ListView.builder(
                                                          controller: ctrl,
                                                          itemCount:
                                                              filtered.length,
                                                          itemBuilder: (_, i) {
                                                            final b =
                                                                filtered[i];
                                                            final u = memberMap[
                                                                b.userId];
                                                            final name = (u
                                                                        ?.displayName
                                                                        .isNotEmpty ==
                                                                    true)
                                                                ? u!.displayName
                                                                : u?.email ??
                                                                    b.userId;
                                                            final isCheckedIn =
                                                                checkedInIds
                                                                    .contains(b
                                                                        .userId);
                                                            return ListTile(
                                                              onTap: () =>
                                                                  _openMemberProfile(
                                                                      context,
                                                                      u,
                                                                      name),
                                                              leading:
                                                                  _MemberAvatar(
                                                                user: u,
                                                                name: name,
                                                                checkedIn:
                                                                    isCheckedIn,
                                                              ),
                                                              title: Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: Text(
                                                                      name,
                                                                      style: TextStyle(
                                                                          fontWeight:
                                                                              FontWeight.w600),
                                                                    ),
                                                                  ),
                                                                  if (isCheckedIn) ...[
                                                                    Icon(
                                                                      Icons
                                                                          .check_circle,
                                                                      size: 14,
                                                                      color: Colors
                                                                          .green
                                                                          .shade600,
                                                                    ),
                                                                    SizedBox(
                                                                        width:
                                                                            4),
                                                                    Text(
                                                                      context
                                                                          .l10n
                                                                          .tr('Present'),
                                                                      style:
                                                                          TextStyle(
                                                                        fontSize:
                                                                            11,
                                                                        color: Colors
                                                                            .green
                                                                            .shade600,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                    SizedBox(
                                                                        width:
                                                                            6),
                                                                  ],
                                                                  if (b
                                                                      .isDropIn) ...[
                                                                    Container(
                                                                      padding: EdgeInsets.symmetric(
                                                                          horizontal:
                                                                              6,
                                                                          vertical:
                                                                              2),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: Color(
                                                                            0xFFEA580C),
                                                                        borderRadius:
                                                                            BorderRadius.circular(5),
                                                                      ),
                                                                      child:
                                                                          Text(
                                                                        context
                                                                            .l10n
                                                                            .tr('Drop-in'),
                                                                        style: TextStyle(
                                                                            color: Colors
                                                                                .white,
                                                                            fontSize:
                                                                                10,
                                                                            fontWeight:
                                                                                FontWeight.w700),
                                                                      ),
                                                                    ),
                                                                    SizedBox(
                                                                        width:
                                                                            6),
                                                                    Icon(
                                                                      b.dropInPaymentStatus ==
                                                                              'paid'
                                                                          ? Icons
                                                                              .check_circle
                                                                          : Icons
                                                                              .monetization_on_outlined,
                                                                      size: 16,
                                                                      color: b.dropInPaymentStatus ==
                                                                              'paid'
                                                                          ? Color(
                                                                              0xFF059669)
                                                                          : Color(
                                                                              0xFFEA580C),
                                                                    ),
                                                                  ],
                                                                ],
                                                              ),
                                                              subtitle: Text(
                                                                u?.email ?? '',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        12),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                            ),
                                          ],
                                        ),
                                        _WaitlistTab(
                                          gymClass: widget.gymClass,
                                          memberMap: memberMap,
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Check-in bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet({required this.gymClass});
  final GymClass gymClass;

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookingService = BookingService(gymId: widget.gymClass.gymId);
    final memberService = MemberService(gymId: widget.gymClass.gymId);
    final coachId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, ctrl) => StreamBuilder<List<Booking>>(
        stream: bookingService.streamBookingsForClass(widget.gymClass.id),
        builder: (context, bookingsSnap) {
          final bookings = bookingsSnap.data ?? <Booking>[];
          return StreamBuilder<Set<String>>(
            stream: bookingService.streamCheckedInUserIds(widget.gymClass.id),
            builder: (context, checkedInSnap) {
              final checkedInIds = checkedInSnap.data ?? <String>{};
              return StreamBuilder<Set<String>>(
                stream: bookingService.streamAbsentUserIds(widget.gymClass.id),
                builder: (context, absentSnap) {
                  final absentIds = absentSnap.data ?? <String>{};
                  return StreamBuilder<List<AppUser>>(
                    stream: memberService.streamMembers(),
                    builder: (context, membersSnap) {
                      final memberMap = {
                        for (final m in membersSnap.data ?? <AppUser>[])
                          m.id: m,
                      };
                      final checkedCount = bookings
                          .where((b) => checkedInIds.contains(b.userId))
                          .length;
                      final filtered = _query.isEmpty
                          ? bookings
                          : bookings.where((b) {
                              final u = memberMap[b.userId];
                              final nameLower =
                                  (u?.displayName.isNotEmpty == true
                                          ? u!.displayName
                                          : u?.email ?? b.userId)
                                      .toLowerCase();
                              return nameLower.contains(_query) ||
                                  (u?.email ?? '')
                                      .toLowerCase()
                                      .contains(_query);
                            }).toList();

                      return Column(
                        children: [
                          _SheetHandle(),
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Row(
                              children: [
                                Icon(Icons.how_to_reg_outlined,
                                    color: cs.primary),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${context.l10n.tr('Check-in')} — ${widget.gymClass.title}',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: Duration(milliseconds: 300),
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: bookings.isNotEmpty &&
                                            checkedCount == bookings.length
                                        ? Colors.green.shade100
                                        : cs.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '$checkedCount / ${bookings.length}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: bookings.isNotEmpty &&
                                              checkedCount == bookings.length
                                          ? Colors.green.shade700
                                          : cs.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (bookings.isNotEmpty &&
                              checkedCount < bookings.length)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(12, 4, 16, 0),
                                child: TextButton.icon(
                                  onPressed: () async {
                                    for (final userId in absentIds) {
                                      await bookingService.undoAbsent(
                                        classId: widget.gymClass.id,
                                        userId: userId,
                                      );
                                    }
                                    await bookingService.bulkCheckInAll(
                                      classId: widget.gymClass.id,
                                      bookings: bookings,
                                      checkedInBy: coachId,
                                    );
                                  },
                                  icon: Icon(Icons.done_all, size: 16),
                                  label: Text(context.l10n.tr('Check in all')),
                                  style: TextButton.styleFrom(
                                    foregroundColor: cs.primary,
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    textStyle: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (v) => setState(
                                  () => _query = v.trim().toLowerCase()),
                              decoration: InputDecoration(
                                hintText: context.l10n.tr('Search member…'),
                                prefixIcon: Icon(Icons.search, size: 20),
                                suffixIcon: _query.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _query = '');
                                        },
                                      )
                                    : null,
                                isDense: true,
                                filled: true,
                                fillColor: cs.surfaceContainerLowest,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: cs.outlineVariant),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: cs.outlineVariant),
                                ),
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          Divider(height: 1),
                          Expanded(
                            child: bookings.isEmpty
                                ? Center(
                                    child: Text(
                                      context.l10n.tr('No bookings.'),
                                      style:
                                          TextStyle(color: cs.onSurfaceVariant),
                                    ),
                                  )
                                : filtered.isEmpty
                                    ? Center(
                                        child: Text(
                                          context.l10n.tr('No members found.'),
                                          style: TextStyle(
                                              color: cs.onSurfaceVariant),
                                        ),
                                      )
                                    : ListView.builder(
                                        controller: ctrl,
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 16),
                                        itemCount: filtered.length,
                                        itemBuilder: (_, i) {
                                          final b = filtered[i];
                                          final u = memberMap[b.userId];
                                          final isCheckedIn =
                                              checkedInIds.contains(b.userId);
                                          final isAbsent =
                                              absentIds.contains(b.userId);
                                          final name =
                                              (u?.displayName.isNotEmpty ==
                                                      true)
                                                  ? u!.displayName
                                                  : u?.email ?? b.userId;
                                          return _CheckInRow(
                                            name: name,
                                            user: u,
                                            userId: b.userId,
                                            isCheckedIn: isCheckedIn,
                                            isAbsent: isAbsent,
                                            onToggle: () async {
                                              if (isCheckedIn) {
                                                await bookingService
                                                    .undoCheckIn(
                                                  classId: widget.gymClass.id,
                                                  userId: b.userId,
                                                );
                                              } else {
                                                if (isAbsent) {
                                                  await bookingService
                                                      .undoAbsent(
                                                    classId: widget.gymClass.id,
                                                    userId: b.userId,
                                                  );
                                                }
                                                await bookingService
                                                    .checkInMember(
                                                  classId: widget.gymClass.id,
                                                  userId: b.userId,
                                                  checkedInBy: coachId,
                                                );
                                              }
                                            },
                                            onToggleAbsent: () async {
                                              if (isAbsent) {
                                                await bookingService.undoAbsent(
                                                  classId: widget.gymClass.id,
                                                  userId: b.userId,
                                                );
                                              } else {
                                                await bookingService.markAbsent(
                                                  classId: widget.gymClass.id,
                                                  userId: b.userId,
                                                  markedBy: coachId,
                                                );
                                              }
                                            },
                                          );
                                        },
                                      ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _CheckInRow extends StatefulWidget {
  const _CheckInRow({
    required this.name,
    required this.user,
    required this.userId,
    required this.isCheckedIn,
    required this.isAbsent,
    required this.onToggle,
    required this.onToggleAbsent,
  });
  final String name;
  final AppUser? user;
  final String userId;
  final bool isCheckedIn;
  final bool isAbsent;
  final Future<void> Function() onToggle;
  final Future<void> Function() onToggleAbsent;

  @override
  State<_CheckInRow> createState() => _CheckInRowState();
}

class _CheckInRowState extends State<_CheckInRow> {
  bool _loading = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _MemberAvatar(
            user: widget.user,
            name: widget.name,
            checkedIn: widget.isCheckedIn,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(widget.name,
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (_loading)
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (widget.isCheckedIn)
            FilledButton.tonalIcon(
              onPressed: () => _run(widget.onToggle),
              icon: Icon(Icons.check_circle, size: 16),
              label: Text(context.l10n.tr('Present')),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.green.shade700,
                backgroundColor: Colors.green.shade100,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonal(
                  onPressed: () => _run(widget.onToggle),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  child: Text(context.l10n.tr('Mark in')),
                ),
                SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _run(widget.onToggleAbsent),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.isAbsent
                        ? Colors.deepOrange.shade700
                        : cs.onSurfaceVariant,
                    side: BorderSide(
                      color: widget.isAbsent
                          ? Colors.deepOrange.shade300
                          : cs.outlineVariant,
                    ),
                    backgroundColor:
                        widget.isAbsent ? Colors.deepOrange.shade50 : null,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  child: Text(context.l10n.tr('Absent')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Book member sheet
// ─────────────────────────────────────────────────────────────────────────────

class _BookMemberSheet extends StatefulWidget {
  const _BookMemberSheet({required this.gymClass});
  final GymClass gymClass;

  @override
  State<_BookMemberSheet> createState() => _BookMemberSheetState();
}

class _BookMemberSheetState extends State<_BookMemberSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  final Map<String, bool> _loadingMap = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookingService = BookingService(gymId: widget.gymClass.gymId);
    final memberService = MemberService(gymId: widget.gymClass.gymId);
    final coachId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, ctrl) => Column(
        children: [
          _SheetHandle(),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.person_add_outlined, color: cs.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.tr('Book Member'),
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        widget.gymClass.title,
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: context.l10n.tr('Search by name or email…'),
                prefixIcon: Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<AppUser>>(
              stream: memberService.streamMembers(),
              builder: (context, mSnap) {
                if (mSnap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                final allMembers = mSnap.data ?? [];
                return StreamBuilder<List<Booking>>(
                  stream:
                      bookingService.streamBookingsForClass(widget.gymClass.id),
                  builder: (context, bSnap) {
                    final bookedUserIds = {
                      for (final b in bSnap.data ?? []) b.userId
                    };
                    final filtered = allMembers.where((m) {
                      if (_query.isEmpty) return true;
                      return m.displayName.toLowerCase().contains(_query) ||
                          m.email.toLowerCase().contains(_query);
                    }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          context.l10n.tr('No members found.'),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: ctrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final member = filtered[i];
                        final alreadyBooked = bookedUserIds.contains(member.id);
                        final isLoading = _loadingMap[member.id] ?? false;
                        final name = member.displayName.isNotEmpty
                            ? member.displayName
                            : member.email;

                        return ListTile(
                          leading: _MemberAvatar(
                            user: member,
                            name: name,
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: alreadyBooked
                                  ? cs.onSurface.withValues(alpha: 0.45)
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            member.email,
                            style: TextStyle(
                              fontSize: 12,
                              color: alreadyBooked
                                  ? cs.onSurface.withValues(alpha: 0.35)
                                  : null,
                            ),
                          ),
                          trailing: alreadyBooked
                              ? Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.green.shade300),
                                  ),
                                  child: Text(
                                    context.l10n.tr('Booked'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                )
                              : isLoading
                                  ? SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : FilledButton(
                                      onPressed: () async {
                                        setState(() =>
                                            _loadingMap[member.id] = true);
                                        try {
                                          await bookingService
                                              .forceBookAndCheckIn(
                                            classId: widget.gymClass.id,
                                            userId: member.id,
                                            adminId: coachId,
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '$name ${context.l10n.tr('booked & checked in')}',
                                                ),
                                                backgroundColor:
                                                    Colors.green.shade700,
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(e.toString()),
                                                backgroundColor: cs.error,
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() =>
                                                _loadingMap.remove(member.id));
                                          }
                                        }
                                      },
                                      style: FilledButton.styleFrom(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                        textStyle: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(context.l10n.tr('Book')),
                                    ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.user, required this.name, this.checkedIn});
  final AppUser? user;
  final String name;
  final bool? checkedIn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photoUrl = user?.photoUrl ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final isIn = checkedIn ?? false;
    return UserAvatar(
      photoUrl: photoUrl,
      initials: initial,
      color: isIn ? Colors.green : cs.primary,
      radius: 18,
    );
  }
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 10),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Monthly summary row (history tab)
// ─────────────────────────────────────────────────────────────────────────────

class _MonthSummaryRow extends StatelessWidget {
  const _MonthSummaryRow({required this.classes});
  final List<GymClass> classes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalBooked = classes.fold(0, (s, c) => s + c.bookedCount);
    final totalCapacity = classes.fold(0, (s, c) => s + c.capacity);
    final avgFill = totalCapacity > 0
        ? (totalBooked / totalCapacity * 100).round().clamp(0, 100)
        : 0;

    return Container(
      margin: EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _MiniStat(
              icon: Icons.event_outlined,
              label:
                  '${classes.length} ${context.l10n.tr(classes.length == 1 ? 'class' : 'classes')}'),
          SizedBox(width: 16),
          _MiniStat(
              icon: Icons.people_outline,
              label: '$totalBooked ${context.l10n.tr('bookings')}'),
          SizedBox(width: 16),
          _MiniStat(icon: Icons.bar_chart_outlined, label: 'avg $avgFill%'),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: cs.onSurfaceVariant),
        SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 15, color: color ?? cs.onSurfaceVariant),
        SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: color ?? cs.onSurfaceVariant,
                letterSpacing: 0.3)),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(role.toUpperCase(),
          style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message, this.sub});
  final IconData icon;
  final String message;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: cs.onSurface.withValues(alpha: 0.25)),
            SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.5))),
            if (sub != null) ...[
              SizedBox(height: 6),
              Text(sub!,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.coachId, required this.classService});
  final String coachId;
  final ClassService classService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<GymClass>>(
      stream: classService.streamAllClassesForCoach(coachId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        final now = DateTime.now();
        final all = snap.data ?? <GymClass>[];
        final past = all.where((c) => c.endTime.isBefore(now)).toList();
        final totalClasses = past.length;
        final totalMembers = past.fold(0, (s, c) => s + c.bookedCount);
        final totalHours = past.fold(
          0.0,
          (s, c) => s + c.endTime.difference(c.startTime).inMinutes / 60.0,
        );
        final fillRateClasses = past.where((c) => c.capacity > 0).toList();
        final avgFillRate = fillRateClasses.isEmpty
            ? 0.0
            : fillRateClasses.fold(
                    0.0, (s, c) => s + c.bookedCount / c.capacity) /
                fillRateClasses.length;
        final months = <String, int>{};
        for (var i = 5; i >= 0; i--) {
          final d = DateTime(now.year, now.month - i, 1);
          months[DateFormat('MMM yy').format(d)] = 0;
        }
        for (final c in past) {
          final key = DateFormat('MMM yy').format(c.startTime);
          if (months.containsKey(key)) {
            months[key] = (months[key] ?? 0) + 1;
          }
        }
        final maxMonthly = months.values.fold<int>(0, (a, b) => a > b ? a : b);

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            _SectionHeader(
                icon: Icons.auto_graph, label: context.l10n.tr('All time')),
            SizedBox(height: 12),
            Row(
              children: [
                _StatCard(
                  label: context.l10n.tr('Classes'),
                  value: '$totalClasses',
                  icon: Icons.event,
                  color: cs.primary,
                ),
                SizedBox(width: 10),
                _StatCard(
                  label: context.l10n.tr('Members'),
                  value: '$totalMembers',
                  icon: Icons.people,
                  color: Colors.teal,
                ),
                SizedBox(width: 10),
                _StatCard(
                  label: context.l10n.tr('Hours'),
                  value: totalHours.toStringAsFixed(0),
                  icon: Icons.timer_outlined,
                  color: Colors.indigo,
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.airline_seat_recline_normal,
                          size: 16, color: cs.primary),
                      SizedBox(width: 8),
                      Text(
                        context.l10n.tr('Avg fill rate'),
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      Spacer(),
                      Text(
                        '${(avgFillRate * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                            fontSize: 16),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: avgFillRate.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: avgFillRate > 0.8 ? Colors.green : cs.primary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            _SectionHeader(
              icon: Icons.calendar_month_outlined,
              label: context.l10n.tr('Last 6 months'),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: SizedBox(
                height: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: months.entries.map((e) {
                    final frac = maxMonthly > 0 ? e.value / maxMonthly : 0.0;
                    final isCurrentMonth =
                        e.key == DateFormat('MMM yy').format(now);
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (e.value > 0)
                              Text(
                                '${e.value}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isCurrentMonth
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            SizedBox(height: 2),
                            AnimatedContainer(
                              duration: Duration(milliseconds: 400),
                              height: (frac * 80).clamp(4.0, 80.0),
                              decoration: BoxDecoration(
                                color: isCurrentMonth
                                    ? cs.primary
                                    : cs.primary.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              e.key.split(' ')[0],
                              style: TextStyle(
                                fontSize: 10,
                                color: isCurrentMonth
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                                fontWeight: isCurrentMonth
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            Text(label,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _NoteEditorSheet extends StatefulWidget {
  const _NoteEditorSheet({required this.gymClass});
  final GymClass gymClass;

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.gymClass.coachNote);
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHandle(),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.sticky_note_2_outlined, color: cs.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.tr('Class note'),
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(widget.gymClass.title,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 4,
              maxLength: 300,
              decoration: InputDecoration(
                hintText:
                    context.l10n.tr('Add WOD, warmup notes, or class details…'),
                filled: true,
                fillColor: cs.surfaceContainerLowest,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Row(
              children: [
                if (widget.gymClass.coachNote.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              setState(() => _saving = true);
                              await ClassService(gymId: widget.gymClass.gymId)
                                  .updateCoachNote(
                                      classId: widget.gymClass.id, note: '');
                              if (context.mounted) Navigator.of(context).pop();
                            },
                      icon: Icon(Icons.delete_outline, size: 16),
                      label: Text(context.l10n.tr('Clear')),
                      style:
                          OutlinedButton.styleFrom(foregroundColor: cs.error),
                    ),
                  ),
                if (widget.gymClass.coachNote.isNotEmpty) SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            await ClassService(gymId: widget.gymClass.gymId)
                                .updateCoachNote(
                              classId: widget.gymClass.id,
                              note: _ctrl.text.trim(),
                            );
                            if (context.mounted) Navigator.of(context).pop();
                          },
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(context.l10n.tr('Save')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifyDialog extends StatefulWidget {
  const _NotifyDialog({required this.gymClass});
  final GymClass gymClass;

  @override
  State<_NotifyDialog> createState() => _NotifyDialogState();
}

class _NotifyDialogState extends State<_NotifyDialog> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSend =
        _titleCtrl.text.trim().isNotEmpty && _bodyCtrl.text.trim().isNotEmpty;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.campaign_outlined, color: cs.primary, size: 20),
          SizedBox(width: 8),
          Text(context.l10n.tr('Notify members'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.gymClass.title,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.l10n.tr('Title'),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: _bodyCtrl,
            onChanged: (_) => setState(() {}),
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.l10n.tr('Message'),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.tr('Cancel')),
        ),
        FilledButton(
          onPressed: _sending || !canSend
              ? null
              : () async {
                  setState(() => _sending = true);
                  try {
                    final svc = BookingService(gymId: widget.gymClass.gymId);
                    final bookingsSnap = await FirebaseFirestore.instance
                        .collection('bookings')
                        .where('classId', isEqualTo: widget.gymClass.id)
                        .get();
                    final bookings = bookingsSnap.docs
                        .map((d) => Booking.fromSnapshot(d))
                        .toList();
                    await svc.notifyClassMembers(
                      bookings: bookings,
                      title: _titleCtrl.text.trim(),
                      body: _bodyCtrl.text.trim(),
                      classId: widget.gymClass.id,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '${bookings.length} ${context.l10n.tr('members notified')}'),
                          backgroundColor: Colors.green.shade700,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _sending = false);
                  }
                },
          child: _sending
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(context.l10n.tr('Send')),
        ),
      ],
    );
  }
}

class _MemberProfileSheet extends StatelessWidget {
  const _MemberProfileSheet({required this.user, required this.gymId});
  final AppUser user;
  final String gymId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = user.displayName.isNotEmpty ? user.displayName : user.email;
    final subsService = SubscriptionService(gymId: gymId);
    final bookingSvc = BookingService(gymId: gymId);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, ctrl) => SingleChildScrollView(
        controller: ctrl,
        child: Column(
          children: [
            _SheetHandle(),
            SizedBox(height: 8),
            UserAvatar(
              photoUrl: user.photoUrl,
              initials: name.isNotEmpty ? name[0].toUpperCase() : '?',
              color: cs.primary,
              radius: 34,
            ),
            SizedBox(height: 10),
            Text(name,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(user.email,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            SizedBox(height: 4),
            if (user.fitnessLevel.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(user.fitnessLevel,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600)),
              ),
            Divider(height: 24),
            StreamBuilder<UserSubscription?>(
              stream: subsService.streamUserSubscription(user.id),
              builder: (context, snap) {
                final sub = snap.data;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(Icons.card_membership_outlined,
                          size: 16, color: cs.primary),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('Subscription'),
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      Spacer(),
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (sub?.status == 'active')
                              ? Colors.green.shade100
                              : cs.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sub?.status ?? user.subscriptionStatus,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: (sub?.status == 'active')
                                ? Colors.green.shade700
                                : cs.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: 12),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: bookingSvc.streamAttendanceForUser(user.id),
              builder: (context, snap) {
                final count = snap.data?.length ?? 0;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(Icons.how_to_reg_outlined,
                          size: 16, color: Colors.teal),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('Total check-ins'),
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      Spacer(),
                      Text('$count',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface)),
                    ],
                  ),
                );
              },
            ),
            if (user.joinDate != null) ...[
              SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 16, color: cs.onSurfaceVariant),
                    SizedBox(width: 8),
                    Text(context.l10n.tr('Member since'),
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Spacer(),
                    Text(DateFormat('d MMM yyyy').format(user.joinDate!),
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _WaitlistTab extends StatelessWidget {
  const _WaitlistTab({required this.gymClass, required this.memberMap});
  final GymClass gymClass;
  final Map<String, AppUser> memberMap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookingService = BookingService(gymId: gymClass.gymId);
    return StreamBuilder<List<WaitlistEntry>>(
      stream: bookingService.streamWaitlistForClass(gymClass.id),
      builder: (context, snap) {
        final entries = snap.data ?? <WaitlistEntry>[];
        if (entries.isEmpty) {
          return Center(
            child: Text(
              context.l10n.tr('No one on the waitlist.'),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          );
        }
        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final entry = entries[i];
            final user = memberMap[entry.userId];
            final fallbackName =
                entry.memberName.isNotEmpty ? entry.memberName : entry.userId;
            final name = (user?.displayName.isNotEmpty == true)
                ? user!.displayName
                : (user?.email ?? fallbackName);
            bool loading = false;
            return StatefulBuilder(
              builder: (context, setRowState) => ListTile(
                leading: _MemberAvatar(user: user, name: name),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('#${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                subtitle:
                    Text(user?.email ?? '', style: TextStyle(fontSize: 12)),
                trailing: loading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton.tonal(
                        onPressed: () async {
                          setRowState(() => loading = true);
                          try {
                            await bookingService.promoteWaitlistedEntry(
                              classId: gymClass.id,
                              entryId: entry.id,
                              userId: entry.userId,
                              memberName: entry.memberName,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '$name ${context.l10n.tr('promoted to booked')}'),
                                  backgroundColor: Colors.green.shade700,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error,
                                ),
                              );
                            }
                          } finally {
                            setRowState(() => loading = false);
                          }
                        },
                        style: FilledButton.styleFrom(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        child: Text(context.l10n.tr('Promote')),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COACH PRIVATE PT TAB
// ─────────────────────────────────────────────────────────────────────────────

class _CoachPtTab extends StatefulWidget {
  const _CoachPtTab({required this.coachId, required this.gymId});
  final String coachId;
  final String gymId;

  @override
  State<_CoachPtTab> createState() => _CoachPtTabState();
}

class _CoachPtTabState extends State<_CoachPtTab> {
  static const _purple = Color(0xFF7C3AED);
  late final _svc = PersonalTrainingService(gymId: widget.gymId);
  bool _showPast = false;

  void _openEditor(BuildContext context, {PersonalTraining? existing}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PtEditorSheet(
        existing: existing,
        gymId: widget.gymId,
      ),
    );
  }

  void _openDetail(BuildContext context, PersonalTraining session) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PtDetailSheet(
        session: session,
        onEdit: () {
          Navigator.of(context).pop();
          _openEditor(context, existing: session);
        },
        onDelete: () async {
          Navigator.of(context).pop();
          await _confirmDelete(context, session);
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, PersonalTraining s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.delete_outline, color: Colors.red, size: 22),
          SizedBox(width: 8),
          Text(context.l10n.tr('Delete session?'),
              style: TextStyle(fontSize: 17)),
        ]),
        content: Text(
          '${context.l10n.tr('Remove')} "${s.title}" ${context.l10n.tr('on')} '
          '${DateFormat('EEE d MMM').format(s.startTime)}? '
          '${context.l10n.tr('Members will no longer see it.')}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _svc.delete(s.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: Icon(Icons.add_rounded),
        label: Text(context.l10n.tr('New Session'),
            style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => _openEditor(context),
      ),
      body: StreamBuilder<List<PersonalTraining>>(
        stream: _svc.streamForCoach(widget.coachId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final now = DateTime.now();
          final all = snap.data ?? [];
          final upcoming = all.where((s) => s.endTime.isAfter(now)).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
          final past = all.where((s) => !s.endTime.isAfter(now)).toList()
            ..sort((a, b) => b.startTime.compareTo(a.startTime));

          // Group upcoming by date
          final grouped = <String, List<PersonalTraining>>{};
          for (final s in upcoming) {
            final key = DateFormat('yyyy-MM-dd').format(s.startTime);
            grouped.putIfAbsent(key, () => []).add(s);
          }

          // Unique members coached
          final uniqueMembers = <String>{
            for (final s in upcoming) ...s.memberIds,
          };

          final statsBanner = _PtStatsBanner(
            upcomingCount: upcoming.length,
            membersCount: uniqueMembers.length,
            totalCount: all.length,
          );

          if (all.isEmpty) {
            return CustomScrollView(slivers: [
              SliverToBoxAdapter(child: statsBanner),
              SliverFillRemaining(
                hasScrollBody: false,
                child: _PtEmptyState(onAdd: () => _openEditor(context)),
              ),
            ]);
          }

          final today = DateTime(now.year, now.month, now.day);
          final tomorrow = today.add(Duration(days: 1));

          final items = <Widget>[statsBanner];

          if (upcoming.isEmpty) {
            items.add(
              Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(context.l10n.tr('No upcoming sessions'),
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic)),
              ),
            );
          } else {
            for (final dateKey in grouped.keys) {
              final date = DateTime.parse(dateKey);
              final isToday = DateUtils.isSameDay(date, today);
              final isTomorrow = DateUtils.isSameDay(date, tomorrow);
              final label = isToday
                  ? '${context.l10n.tr('Today')} · ${DateFormat('EEEE d MMMM').format(date)}'
                  : isTomorrow
                      ? '${context.l10n.tr('Tomorrow')} · ${DateFormat('EEEE d MMMM').format(date)}'
                      : DateFormat('EEEE · d MMMM').format(date);

              items.add(_PtDateHeader(label: label, isToday: isToday));
              for (final s in grouped[dateKey]!) {
                items.add(_PtSessionCard(
                  session: s,
                  isPast: false,
                  onTap: () => _openDetail(context, s),
                  onEdit: () => _openEditor(context, existing: s),
                  onDelete: () => _confirmDelete(context, s),
                ));
              }
            }
          }

          if (past.isNotEmpty) {
            items.add(_PtPastToggle(
              count: past.length,
              expanded: _showPast,
              onTap: () => setState(() => _showPast = !_showPast),
            ));
            if (_showPast) {
              for (final s in past) {
                items.add(_PtSessionCard(
                  session: s,
                  isPast: true,
                  onTap: () => _openDetail(context, s),
                  onEdit: () => _openEditor(context, existing: s),
                  onDelete: () => _confirmDelete(context, s),
                ));
              }
            }
          }

          items.add(SizedBox(height: 100));

          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (_, i) => items[i],
          );
        },
      ),
    );
  }
}

// ─── Stats banner ─────────────────────────────────────────────────────────────

class _PtStatsBanner extends StatelessWidget {
  const _PtStatsBanner({
    required this.upcomingCount,
    required this.membersCount,
    required this.totalCount,
  });

  final int upcomingCount;
  final int membersCount;
  final int totalCount;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _purple.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.lock_person_outlined,
                    color: Colors.white, size: 20),
              ),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.tr('My Private Sessions'),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  Text(context.l10n.tr('Personal training sessions'),
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              _PtStatCell(
                  value: '$upcomingCount',
                  label: context.l10n.tr('Upcoming'),
                  icon: Icons.upcoming_outlined),
              _PtDivider(),
              _PtStatCell(
                  value: '$membersCount',
                  label: context.l10n.tr('Members'),
                  icon: Icons.people_outline),
              _PtDivider(),
              _PtStatCell(
                  value: '$totalCount',
                  label: context.l10n.tr('All time'),
                  icon: Icons.history_outlined),
            ],
          ),
        ],
      ),
    );
  }
}

class _PtStatCell extends StatelessWidget {
  const _PtStatCell(
      {required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _PtDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 32,
        color: Colors.white.withValues(alpha: 0.25),
      );
}

// ─── Date header ──────────────────────────────────────────────────────────────

class _PtDateHeader extends StatelessWidget {
  const _PtDateHeader({required this.label, required this.isToday});
  final String label;
  final bool isToday;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isToday ? _purple : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isToday ? Colors.white : Colors.grey.shade700),
            ),
          ),
          SizedBox(width: 10),
          Expanded(child: Divider(color: Colors.grey.shade200, height: 1)),
        ],
      ),
    );
  }
}

// ─── Past toggle ──────────────────────────────────────────────────────────────

class _PtPastToggle extends StatelessWidget {
  const _PtPastToggle(
      {required this.count, required this.expanded, required this.onTap});
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey.shade600, size: 18),
              SizedBox(width: 8),
              Text(
                '${context.l10n.tr('Past Sessions')} ($count)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Session card ─────────────────────────────────────────────────────────────

class _PtSessionCard extends StatelessWidget {
  const _PtSessionCard({
    required this.session,
    required this.isPast,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final PersonalTraining session;
  final bool isPast;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dur = session.endTime.difference(session.startTime).inMinutes;
    final isToday = DateUtils.isSameDay(session.startTime, DateTime.now());

    return Opacity(
      opacity: isPast ? 0.7 : 1.0,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPast ? cs.outlineVariant : _purple.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: isPast
              ? []
              : [
                  BoxShadow(
                    color: _purple.withValues(alpha: 0.07),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Left time column ──────────────────────────────────
                  Container(
                    width: 72,
                    padding: EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                    decoration: BoxDecoration(
                      color: isPast
                          ? cs.surfaceContainerHighest
                          : _purple.withValues(alpha: 0.09),
                      borderRadius:
                          BorderRadius.horizontal(left: Radius.circular(17)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(session.startTime),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: isPast ? Colors.grey : _purple,
                              height: 1.1),
                        ),
                        SizedBox(height: 6),
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPast
                                ? Colors.grey.withValues(alpha: 0.15)
                                : _purple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${dur}m',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isPast ? Colors.grey : _purple),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Right content ─────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title + today badge
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  session.title,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: isPast
                                          ? cs.onSurfaceVariant
                                          : cs.onSurface),
                                ),
                              ),
                              if (isToday) ...[
                                SizedBox(width: 6),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade600,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(context.l10n.tr('TODAY'),
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ],
                          ),

                          if (session.location.isNotEmpty) ...[
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.place_outlined,
                                    size: 12, color: cs.onSurfaceVariant),
                                SizedBox(width: 4),
                                Text(session.location,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ],

                          SizedBox(height: 8),

                          // Member avatar row
                          _PtMemberAvatars(
                              names: session.memberNames, isPast: isPast),

                          if (session.notes.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Text(
                              session.notes,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                  height: 1.4),
                            ),
                          ],

                          SizedBox(height: 6),

                          // Action row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: onEdit,
                                icon: Icon(Icons.edit_outlined,
                                    size: 14,
                                    color: isPast ? Colors.grey : _purple),
                                label: Text(context.l10n.tr('Edit'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isPast ? Colors.grey : _purple)),
                                style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              SizedBox(width: 4),
                              TextButton.icon(
                                onPressed: onDelete,
                                icon: Icon(Icons.delete_outline,
                                    size: 14, color: Colors.red),
                                label: Text(context.l10n.tr('Delete'),
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.red)),
                                style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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
}

// ─── Member avatars ───────────────────────────────────────────────────────────

class _PtMemberAvatars extends StatelessWidget {
  const _PtMemberAvatars({required this.names, required this.isPast});
  final List<String> names;
  final bool isPast;

  static const _purple = Color(0xFF7C3AED);

  String _initials(String name) => name
      .trim()
      .split(' ')
      .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
      .take(2)
      .join();

  @override
  Widget build(BuildContext context) {
    const maxShow = 3;
    final shown = names.take(maxShow).toList();
    final extra = names.length - maxShow;
    final stackWidth = (shown.length * 20.0) + 8.0 + (extra > 0 ? 30.0 : 0.0);

    return Row(
      children: [
        SizedBox(
          height: 26,
          width: stackWidth,
          child: Stack(
            children: [
              ...shown.asMap().entries.map((e) => Positioned(
                    left: e.key * 18.0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: isPast
                            ? Colors.grey.withValues(alpha: 0.25)
                            : _purple.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(e.value),
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isPast ? Colors.grey : _purple),
                      ),
                    ),
                  )),
              if (extra > 0)
                Positioned(
                  left: shown.length * 18.0,
                  child: Container(
                    height: 26,
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isPast
                          ? Colors.grey.withValues(alpha: 0.1)
                          : _purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text('+$extra',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isPast ? Colors.grey : _purple)),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(width: 8),
        Text(
          names.isEmpty
              ? context.l10n.tr('No members')
              : names.length == 1
                  ? names.first
                  : '${names.length} ${context.l10n.tr('members')}',
          style: TextStyle(
              fontSize: 12,
              fontWeight: names.length == 1 ? FontWeight.w600 : FontWeight.w400,
              color: isPast
                  ? Colors.grey
                  : names.length == 1
                      ? _purple
                      : Colors.grey.shade600),
        ),
      ],
    );
  }
}

// ─── PT Detail sheet ─────────────────────────────────────────────────────────

class _PtDetailSheet extends StatelessWidget {
  const _PtDetailSheet({
    required this.session,
    required this.onEdit,
    required this.onDelete,
  });

  final PersonalTraining session;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dur = session.endTime.difference(session.startTime).inMinutes;
    final isToday = DateUtils.isSameDay(session.startTime, DateTime.now());
    final isPast = session.endTime.isBefore(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header gradient
          Container(
            margin: EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPast
                    ? [Colors.grey.shade500, Colors.grey.shade600]
                    : [_purple, Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        session.title,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.2),
                      ),
                    ),
                    if (isToday)
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade400,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(context.l10n.tr('TODAY'),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                    if (isPast && !isToday)
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(context.l10n.tr('PAST'),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    // Date
                    _InfoChip(
                      icon: Icons.calendar_today_outlined,
                      label: DateFormat('EEE d MMM').format(session.startTime),
                    ),
                    SizedBox(width: 8),
                    // Time range
                    _InfoChip(
                      icon: Icons.schedule_outlined,
                      label:
                          '${DateFormat('HH:mm').format(session.startTime)} → ${DateFormat('HH:mm').format(session.endTime)}',
                    ),
                    SizedBox(width: 8),
                    // Duration
                    _InfoChip(
                      icon: Icons.timer_outlined,
                      label: '$dur min',
                    ),
                  ],
                ),
                if (session.location.isNotEmpty) ...[
                  SizedBox(height: 8),
                  _InfoChip(
                    icon: Icons.place_outlined,
                    label: session.location,
                  ),
                ],
              ],
            ),
          ),

          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Coach ──────────────────────────────────────────
                  _DetailSection(
                    icon: Icons.sports_outlined,
                    label: context.l10n.tr('Coach'),
                    child: _CoachRow(
                      coachId: session.coachId,
                      coachName: session.coachName,
                    ),
                  ),
                  SizedBox(height: 16),

                  // ── Members ────────────────────────────────────────
                  _DetailSection(
                    icon: Icons.people_outline,
                    label:
                        '${context.l10n.tr('Members')} (${session.memberIds.length})',
                    child: Column(
                      children: [
                        for (var i = 0; i < session.memberIds.length; i++)
                          _MemberRow(
                            memberId: session.memberIds[i],
                            memberName: i < session.memberNames.length
                                ? session.memberNames[i]
                                : '',
                          ),
                      ],
                    ),
                  ),

                  // ── Notes ──────────────────────────────────────────
                  if (session.notes.isNotEmpty) ...[
                    SizedBox(height: 16),
                    _DetailSection(
                      icon: Icons.notes_outlined,
                      label: context.l10n.tr('Session Notes'),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          session.notes,
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                              height: 1.5),
                        ),
                      ),
                    ),
                  ],

                  SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Action footer
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon:
                        Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    label: Text(context.l10n.tr('Delete'),
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side:
                          BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: Icon(Icons.edit_outlined, size: 16),
                    label: Text(context.l10n.tr('Edit Session'),
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header info chip ─────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Detail section ───────────────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  const _DetailSection(
      {required this.icon, required this.label, required this.child});
  final IconData icon;
  final String label;
  final Widget child;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: _purple),
            SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: _purple)),
          ],
        ),
        SizedBox(height: 10),
        child,
      ],
    );
  }
}

// ─── Coach row ────────────────────────────────────────────────────────────────

class _CoachRow extends StatelessWidget {
  const _CoachRow({required this.coachId, required this.coachName});
  final String coachId;
  final String coachName;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final initials = coachName
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .take(2)
        .join();
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: _purple.withValues(alpha: 0.12),
          child: Text(initials,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: _purple)),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(coachName,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text(context.l10n.tr('Coach'),
                style: TextStyle(
                    fontSize: 11, color: _purple, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}

// ─── Member row (tappable → MemberDetailScreen) ───────────────────────────────

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.memberId, required this.memberName});
  final String memberId;
  final String memberName;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<AppUser?>(
      stream: MemberService().streamUser(memberId),
      builder: (context, snap) {
        final user = snap.data;
        final name = user != null
            ? (user.displayName.isNotEmpty ? user.displayName : user.email)
            : memberName;
        final initials = name
            .trim()
            .split(' ')
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .take(2)
            .join();

        return InkWell(
          onTap: user == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => MemberDetailScreen(member: user)),
                  ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                UserAvatar(
                  photoUrl: user?.photoUrl ?? '',
                  initials: initials,
                  color: _purple,
                  radius: 20,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      if (user != null)
                        Text(user.email,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (user != null)
                  Icon(Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant, size: 20),
                if (user == null)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _PtEmptyState extends StatelessWidget {
  const _PtEmptyState({required this.onAdd});
  final VoidCallback onAdd;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _purple.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(Icons.lock_person_outlined,
                  size: 48, color: Colors.white),
            ),
            SizedBox(height: 24),
            Text(context.l10n.tr('No Private Sessions Yet'),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            SizedBox(height: 10),
            Text(
              context.l10n.tr(
                  'Schedule your first one-on-one or small group session. Members will see it directly in their schedule.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade600, height: 1.5),
            ),
            SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                padding: EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: onAdd,
              icon: Icon(Icons.add_rounded, size: 20),
              label: Text(context.l10n.tr('Schedule First Session'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COVER TAB  –  lets a coach take over a class from an absent colleague
// ─────────────────────────────────────────────────────────────────────────────

class _CoverTab extends StatefulWidget {
  const _CoverTab({required this.coach, required this.classService});
  final AppUser coach;
  final ClassService classService;

  @override
  State<_CoverTab> createState() => _CoverTabState();
}

class _CoverTabState extends State<_CoverTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<GymClass>>(
      stream: widget.classService.streamUpcomingClassesForGym(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final all = snap.data ?? [];
        // Classes NOT yet assigned to this coach — those are the ones to cover.
        final coverableAll =
            all.where((c) => !c.coachIds.contains(widget.coach.id)).toList();
        // Apply search filter
        final coverable = _query.isEmpty
            ? coverableAll
            : coverableAll
                .where((c) =>
                    c.title.toLowerCase().contains(_query) ||
                    c.coachName.toLowerCase().contains(_query))
                .toList();
        // Classes this coach already covers (as a second coach).
        final covering = all
            .where((c) =>
                c.coachIds.contains(widget.coach.id) && c.coachIds.length > 1)
            .toList();

        // Group coverable by normalized date
        final grouped = <DateTime, List<GymClass>>{};
        for (final c in coverable) {
          final key =
              DateTime(c.startTime.year, c.startTime.month, c.startTime.day);
          grouped.putIfAbsent(key, () => []).add(c);
        }
        final sortedDates = grouped.keys.toList()..sort();

        return Column(
          children: [
            // ── Search bar ────────────────────────────────────────────
            Container(
              color: cs.surface,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: context.l10n.tr('Search classes…'),
                  prefixIcon: Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: cs.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            Divider(height: 1),

            Expanded(
              child: all.isEmpty
                  ? _EmptyState(
                      icon: Icons.event_busy_outlined,
                      message: context.l10n.tr('No upcoming classes.'),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 80),
                      children: [
                        // ── Info banner ─────────────────────────────────
                        Container(
                          padding: EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: cs.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 18, color: cs.primary),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  context.l10n.tr(
                                      'Cover a class when a colleague is absent. You will be added as a co-coach for that specific session only.'),
                                  style: TextStyle(
                                      fontSize: 12, color: cs.onSurface),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),

                        // ── Classes you already cover ────────────────────
                        if (covering.isNotEmpty) ...[
                          _SectionHeader(
                            icon: Icons.check_circle_outline,
                            label: context.l10n.tr('Already covering'),
                            color: Colors.green.shade600,
                          ),
                          SizedBox(height: 10),
                          ...covering.map((c) => _CoverCard(
                                gymClass: c,
                                coach: widget.coach,
                                classService: widget.classService,
                                alreadyCovering: true,
                              )),
                          SizedBox(height: 20),
                        ],

                        // ── Available to cover (date-grouped) ────────────
                        _SectionHeader(
                          icon: Icons.swap_horiz_outlined,
                          label: context.l10n.tr('Available to cover'),
                          color: cs.primary,
                        ),
                        SizedBox(height: 10),

                        if (coverable.isEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 24),
                            child: _EmptyState(
                              icon: _query.isNotEmpty
                                  ? Icons.search_off_outlined
                                  : Icons.celebration_outlined,
                              message: _query.isNotEmpty
                                  ? context.l10n
                                      .tr('No classes match your search.')
                                  : context.l10n
                                      .tr('All classes are fully covered.'),
                            ),
                          )
                        else
                          for (final date in sortedDates) ...[
                            // Date header pill
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      DateFormat('EEEE d MMMM').format(date),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...grouped[date]!.map((c) => _CoverCard(
                                  gymClass: c,
                                  coach: widget.coach,
                                  classService: widget.classService,
                                  alreadyCovering: false,
                                )),
                            SizedBox(height: 8),
                          ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cover card
// ─────────────────────────────────────────────────────────────────────────────

class _CoverCard extends StatefulWidget {
  const _CoverCard({
    required this.gymClass,
    required this.coach,
    required this.classService,
    required this.alreadyCovering,
  });
  final GymClass gymClass;
  final AppUser coach;
  final ClassService classService;
  final bool alreadyCovering;

  @override
  State<_CoverCard> createState() => _CoverCardState();
}

class _CoverCardState extends State<_CoverCard> {
  bool _loading = false;

  Future<void> _cover(BuildContext context) async {
    final coachName = widget.coach.displayName.isNotEmpty
        ? widget.coach.displayName
        : widget.coach.email;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Cover this class?')),
        content: Text(
          '${widget.gymClass.title}\n'
          '${DateFormat('EEE d MMM · HH:mm').format(widget.gymClass.startTime)} – '
          '${DateFormat('HH:mm').format(widget.gymClass.endTime)}',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Cover')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await widget.classService.coverClass(
        classId: widget.gymClass.id,
        coachId: widget.coach.id,
        coachName: coachName,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.tr('You are now covering this class.')),
          backgroundColor: Colors.green.shade700,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uncover(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Remove yourself from this class?')),
        content: Text(
          '${widget.gymClass.title}\n'
          '${DateFormat('EEE d MMM · HH:mm').format(widget.gymClass.startTime)}',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(context.l10n.tr('Remove')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await widget.classService.uncoverClass(
        classId: widget.gymClass.id,
        coachId: widget.coach.id,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(context.l10n.tr('You have been removed from this class.')),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gc = widget.gymClass;
    final color =
        gc.classColorValue != null ? Color(gc.classColorValue!) : cs.primary;
    final currentCoaches =
        gc.coachNames.isNotEmpty ? gc.coachNames.join(', ') : gc.coachName;

    return Card(
      margin: EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: widget.alreadyCovering
              ? Colors.green.shade300
              : cs.outlineVariant,
          width: widget.alreadyCovering ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                if (widget.alreadyCovering)
                  Container(
                    margin: EdgeInsets.only(right: 8),
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      context.l10n.tr('COVERING'),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                Expanded(
                  child: Text(gc.title,
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
            SizedBox(height: 6),

            // Time
            Row(
              children: [
                Icon(Icons.schedule_outlined,
                    size: 13, color: cs.onSurfaceVariant),
                SizedBox(width: 4),
                Text(
                  '${DateFormat('EEE d MMM').format(gc.startTime)}  ·  '
                  '${DateFormat('HH:mm').format(gc.startTime)} – '
                  '${DateFormat('HH:mm').format(gc.endTime)}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            SizedBox(height: 4),

            // Current coaches
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 13, color: cs.onSurfaceVariant),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    currentCoaches.isEmpty
                        ? context.l10n.tr('No coach assigned')
                        : currentCoaches,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.people_outline,
                    size: 13, color: cs.onSurfaceVariant),
                SizedBox(width: 4),
                Text('${gc.bookedCount}/${gc.capacity}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            SizedBox(height: 10),

            // Capacity bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: gc.capacity > 0 ? gc.bookedCount / gc.capacity : 0,
                backgroundColor: cs.surfaceContainerHighest,
                color: gc.isFull ? Colors.orange : color,
                minHeight: 4,
              ),
            ),
            SizedBox(height: 12),

            // Action button
            SizedBox(
              width: double.infinity,
              child: _loading
                  ? Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : widget.alreadyCovering
                      ? OutlinedButton.icon(
                          onPressed: () => _uncover(context),
                          icon: Icon(Icons.person_remove_outlined, size: 16),
                          label: Text(context.l10n.tr('Remove myself'),
                              style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.error,
                            side: BorderSide(color: cs.error),
                            padding: EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: () => _cover(context),
                          icon: Icon(Icons.swap_horiz_outlined, size: 16),
                          label: Text(context.l10n.tr('Cover this class'),
                              style: TextStyle(fontSize: 13)),
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Class detail bottom sheet (coach view)
// ─────────────────────────────────────────────────────────────────────────────

class _ClassDetailSheet extends StatelessWidget {
  const _ClassDetailSheet({required this.gymClass});
  final GymClass gymClass;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isNow =
        gymClass.startTime.isBefore(now) && gymClass.endTime.isAfter(now);
    final isPast = gymClass.endTime.isBefore(now);
    final isToday = DateUtils.isSameDay(gymClass.startTime, now);
    final color = gymClass.classColorValue != null
        ? Color(gymClass.classColorValue!)
        : cs.primary;
    final duration = gymClass.endTime.difference(gymClass.startTime);
    final durationLabel = duration.inMinutes >= 60
        ? '${duration.inHours}h${duration.inMinutes % 60 > 0 ? ' ${duration.inMinutes % 60}m' : ''}'
        : '${duration.inMinutes}m';
    final availableSpots = gymClass.capacity - gymClass.bookedCount;
    final fillPercent =
        gymClass.capacity > 0 ? gymClass.bookedCount / gymClass.capacity : 0.0;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, ctrl) => ListView(
        controller: ctrl,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _SheetHandle(),
          SizedBox(height: 8),

          // ── Colored title block ───────────────────────────────────
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isNow)
                      _StatusBadge(
                          label: context.l10n.tr('IN PROGRESS'), color: color),
                    if (!isNow && isToday && !isPast)
                      _StatusBadge(
                          label: context.l10n.tr('TODAY'), color: cs.primary),
                    if (isPast)
                      _StatusBadge(
                          label: context.l10n.tr('PAST'),
                          color: cs.onSurfaceVariant),
                    Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(durationLabel,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(gymClass.title,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 14, color: cs.onSurfaceVariant),
                  SizedBox(width: 6),
                  Text(
                    DateFormat('EEEE, d MMMM yyyy').format(gymClass.startTime),
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ]),
                SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.schedule_outlined,
                      size: 14, color: cs.onSurfaceVariant),
                  SizedBox(width: 6),
                  Text(
                    '${DateFormat('HH:mm').format(gymClass.startTime)} – ${DateFormat('HH:mm').format(gymClass.endTime)}',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ]),
              ],
            ),
          ),

          SizedBox(height: 16),

          // ── Capacity section ──────────────────────────────────────
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.tr('Capacity'),
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                SizedBox(height: 12),
                Row(
                  children: [
                    _CapacityStat(
                      icon: Icons.how_to_reg,
                      label: context.l10n.tr('Booked'),
                      value: gymClass.bookedCount.toString(),
                      color: cs.primary,
                    ),
                    _CapacityStat(
                      icon: Icons.event_seat_outlined,
                      label: context.l10n.tr('Available'),
                      value: availableSpots > 0
                          ? availableSpots.toString()
                          : context.l10n.tr('Full'),
                      color: availableSpots > 0
                          ? Colors.green.shade600
                          : Colors.orange.shade700,
                    ),
                    _CapacityStat(
                      icon: Icons.people_outline,
                      label: context.l10n.tr('Total'),
                      value: gymClass.capacity.toString(),
                      color: cs.onSurfaceVariant,
                    ),
                    if (gymClass.waitlistCount > 0)
                      _CapacityStat(
                        icon: Icons.hourglass_empty,
                        label: context.l10n.tr('Waitlist'),
                        value: gymClass.waitlistCount.toString(),
                        color: Colors.orange.shade700,
                      ),
                  ],
                ),
                SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fillPercent.clamp(0.0, 1.0),
                    backgroundColor: cs.surfaceContainerHighest,
                    color: gymClass.isFull ? Colors.orange : color,
                    minHeight: 8,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  gymClass.isFull
                      ? context.l10n.tr('Class is full')
                      : '${(fillPercent * 100).round()}% ${context.l10n.tr('full')}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // ── Description ───────────────────────────────────────────
          if (gymClass.description.trim().isNotEmpty) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.tr('Description'),
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  SizedBox(height: 8),
                  Text(gymClass.description,
                      style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                          height: 1.5)),
                ],
              ),
            ),
          ],

          // ── Coaches ───────────────────────────────────────────────
          if (gymClass.coachNames.isNotEmpty) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.tr('Coaches'),
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: gymClass.coachNames
                        .map((name) => Chip(
                              avatar: Icon(Icons.sports, size: 14),
                              label: Text(name, style: TextStyle(fontSize: 12)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ],

          SizedBox(height: 20),

          // ── Action buttons ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => _RosterSheet(gymClass: gymClass),
                    );
                  },
                  icon: Icon(Icons.people_outline, size: 16),
                  label: Text(context.l10n.tr('Roster')),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (!isPast) ...[
                SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20))),
                        builder: (_) => _CheckInSheet(gymClass: gymClass),
                      );
                    },
                    icon: Icon(Icons.how_to_reg_outlined, size: 16),
                    label: Text(context.l10n.tr('Check-in')),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
// Roster tab — all unique members who have booked this coach's classes
// ─────────────────────────────────────────────────────────────────────────────

class _CoachRosterTab extends StatefulWidget {
  const _CoachRosterTab({
    required this.coachId,
    required this.gymId,
    required this.classService,
  });
  final String coachId;
  final String gymId;
  final ClassService classService;

  @override
  State<_CoachRosterTab> createState() => _CoachRosterTabState();
}

class _CoachRosterTabState extends State<_CoachRosterTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Cache the counts future so it isn't rebuilt on every stream tick.
  List<String> _lastClassIds = [];
  Future<Map<String, int>>? _countsFuture;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, int>> _fetchSessionCounts(List<String> classIds) async {
    final service = BookingService(gymId: widget.gymId);
    final counts = <String, int>{};
    for (final id in classIds) {
      final bookings = await service.streamBookingsForClass(id).first;
      for (final b in bookings) {
        if (b.userId.isNotEmpty) {
          counts[b.userId] = (counts[b.userId] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  Future<Map<String, int>> _countsFor(List<String> ids) {
    if (_countsFuture == null || !_sameIds(ids, _lastClassIds)) {
      _lastClassIds = List.unmodifiable(ids);
      _countsFuture = _fetchSessionCounts(ids);
    }
    return _countsFuture!;
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final setA = a.toSet();
    return b.every(setA.contains);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Search bar ────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: context.l10n.tr('Search member…'),
              prefixIcon: Icon(Icons.search, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        Divider(height: 1),

        // ── Content ───────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<GymClass>>(
            stream:
                widget.classService.streamAllClassesForCoach(widget.coachId),
            builder: (context, classSnap) {
              if (classSnap.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              final classIds = (classSnap.data ?? []).map((c) => c.id).toList();

              if (classIds.isEmpty) {
                return _EmptyState(
                  icon: Icons.group_outlined,
                  message: context.l10n.tr('No classes assigned yet.'),
                  sub: context.l10n
                      .tr('Members will appear here once you have classes.'),
                );
              }

              return FutureBuilder<Map<String, int>>(
                future: _countsFor(classIds),
                builder: (context, countSnap) {
                  if (countSnap.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  final sessionCounts = countSnap.data ?? {};

                  return StreamBuilder<List<AppUser>>(
                    stream: MemberService(gymId: widget.gymId).streamMembers(),
                    builder: (context, memberSnap) {
                      if (memberSnap.connectionState ==
                          ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }

                      var roster = (memberSnap.data ?? [])
                          .where((m) => sessionCounts.containsKey(m.id))
                          .toList()
                        ..sort((a, b) => (sessionCounts[b.id] ?? 0)
                            .compareTo(sessionCounts[a.id] ?? 0));

                      if (_query.isNotEmpty) {
                        roster = roster.where((m) {
                          final name = (m.displayName.isNotEmpty
                                  ? m.displayName
                                  : m.email)
                              .toLowerCase();
                          return name.contains(_query) ||
                              m.email.toLowerCase().contains(_query);
                        }).toList();
                      }

                      if (roster.isEmpty) {
                        return _EmptyState(
                          icon: _query.isNotEmpty
                              ? Icons.search_off_outlined
                              : Icons.group_outlined,
                          message: _query.isNotEmpty
                              ? context.l10n.tr('No members found.')
                              : context.l10n.tr(
                                  'No members have booked your classes yet.'),
                        );
                      }

                      return Column(
                        children: [
                          // Summary chip
                          Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Icon(Icons.group,
                                    size: 15, color: cs.onSurfaceVariant),
                                SizedBox(width: 6),
                                Text(
                                  '${roster.length} ${context.l10n.tr(_query.isEmpty ? 'members' : 'results')}',
                                  style: TextStyle(
                                      fontSize: 13, color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 80),
                              itemCount: roster.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, indent: 60),
                              itemBuilder: (_, i) {
                                final member = roster[i];
                                final sessions = sessionCounts[member.id] ?? 0;
                                final name = member.displayName.isNotEmpty
                                    ? member.displayName
                                    : member.email;
                                return ListTile(
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 6, horizontal: 0),
                                  leading: UserAvatar(
                                    photoUrl: member.photoUrl,
                                    initials: name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    radius: 22,
                                  ),
                                  title: Text(name,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(member.email,
                                      style: TextStyle(fontSize: 12)),
                                  trailing: Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '$sessions',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              color: cs.primary),
                                        ),
                                        Text(
                                          sessions == 1
                                              ? context.l10n.tr('session')
                                              : context.l10n.tr('sessions'),
                                          style: TextStyle(
                                              fontSize: 9, color: cs.primary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          MemberDetailScreen(member: member),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Capacity stat cell
// ─────────────────────────────────────────────────────────────────────────────

class _CapacityStat extends StatelessWidget {
  const _CapacityStat({
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
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
