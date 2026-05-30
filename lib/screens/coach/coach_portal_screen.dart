import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/booking.dart';
import '../../models/gym_class.dart';
import '../../models/personal_training.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import '../../services/member_service.dart';
import '../../services/personal_training_service.dart';
import '../../widgets/user_avatar.dart';
import '../admin/admin_calendar_screen.dart';
import '../admin/member_detail_screen.dart';
import '../admin/tabs/admin_personal_training_tab.dart';
import '../../l10n/app_localizations.dart';

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
  late final TabController _tc = TabController(length: 5, vsync: this);
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
                  final hasClass = byDay.containsKey(i);

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
                            SizedBox(height: 4),
                            // Dot indicator
                            AnimatedContainer(
                              duration: Duration(milliseconds: 180),
                              width: hasClass ? 6 : 0,
                              height: hasClass ? 6 : 0,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? cs.onPrimary.withValues(alpha: 0.7)
                                    : cs.primary,
                                shape: BoxShape.circle,
                              ),
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

class _NextClassBanner extends StatelessWidget {
  const _NextClassBanner({required this.classes});
  final List<GymClass> classes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final next = classes.where((c) => c.startTime.isAfter(now)).firstOrNull;

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
                classes.isEmpty
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
                SizedBox(height: 4),
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
                ]),
              ],
            ),
          ),
          Column(
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

    final stats = [
      _Stat(context.l10n.tr('Classes'), classes.length.toString(), Icons.event),
      _Stat(context.l10n.tr('Members'), totalBooked.toString(), Icons.people),
      _Stat(context.l10n.tr('Capacity'), totalCapacity.toString(),
          Icons.airline_seat_recline_normal),
    ];

    return Row(
      children: stats
          .map((s) => Expanded(
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
                      Icon(s.icon, color: cs.primary, size: 20),
                      SizedBox(height: 6),
                      Text(s.value,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface)),
                      Text(s.label,
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ))
          .toList(),
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
        onTap: () => _openRoster(context),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title row ─────────────────────────────────────────
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

              // ── Time + capacity ───────────────────────────────────
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

              // ── Capacity bar ──────────────────────────────────────
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

              // ── Action buttons ────────────────────────────────────
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
            ],
          ),
        ),
      ),
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

class _RosterSheet extends StatelessWidget {
  const _RosterSheet({required this.gymClass});
  final GymClass gymClass;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookingService = BookingService(gymId: gymClass.gymId);
    final memberService = MemberService(gymId: gymClass.gymId);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, ctrl) => Column(
        children: [
          _SheetHandle(),
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.people_outline, color: cs.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                      '${context.l10n.tr('Roster')} — ${gymClass.title}',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Text('${gymClass.bookedCount}/${gymClass.capacity}',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Booking>>(
              stream: bookingService.streamBookingsForClass(gymClass.id),
              builder: (context, snap) {
                final bookings = snap.data ?? [];
                if (bookings.isEmpty) {
                  return Center(
                      child: Text(context.l10n.tr('No bookings yet.'),
                          style: TextStyle(color: cs.onSurfaceVariant)));
                }
                return ListView.builder(
                  controller: ctrl,
                  itemCount: bookings.length,
                  itemBuilder: (_, i) {
                    final b = bookings[i];
                    return StreamBuilder<AppUser?>(
                      stream: memberService.streamUser(b.userId),
                      builder: (_, uSnap) {
                        final u = uSnap.data;
                        final name = (u?.displayName.isNotEmpty == true)
                            ? u!.displayName
                            : u?.email ?? b.userId;
                        return ListTile(
                          leading: _MemberAvatar(user: u, name: name),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(name,
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              if (b.isDropIn) ...[
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Color(0xFFEA580C),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    context.l10n.tr('Drop-in'),
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
                                  b.dropInPaymentStatus == 'paid'
                                      ? Icons.check_circle
                                      : Icons.monetization_on_outlined,
                                  size: 16,
                                  color: b.dropInPaymentStatus == 'paid'
                                      ? Color(0xFF059669)
                                      : Color(0xFFEA580C),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(u?.email ?? '',
                              style: TextStyle(fontSize: 12)),
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
// Check-in bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CheckInSheet extends StatelessWidget {
  const _CheckInSheet({required this.gymClass});
  final GymClass gymClass;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookingService = BookingService(gymId: gymClass.gymId);
    final memberService = MemberService(gymId: gymClass.gymId);
    final coachId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, ctrl) => Column(
        children: [
          _SheetHandle(),
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.how_to_reg_outlined, color: cs.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                      '${context.l10n.tr('Check-in')} — ${gymClass.title}',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Booking>>(
              stream: bookingService.streamBookingsForClass(gymClass.id),
              builder: (context, bSnap) {
                final bookings = bSnap.data ?? [];
                return StreamBuilder<Set<String>>(
                  stream: bookingService.streamCheckedInUserIds(gymClass.id),
                  builder: (context, aSnap) {
                    final checkedInIds = aSnap.data ?? {};
                    if (bookings.isEmpty) {
                      return Center(
                          child: Text(context.l10n.tr('No bookings.'),
                              style: TextStyle(color: cs.onSurfaceVariant)));
                    }
                    return ListView.builder(
                      controller: ctrl,
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      itemCount: bookings.length,
                      itemBuilder: (_, i) {
                        final b = bookings[i];
                        final isCheckedIn = checkedInIds.contains(b.userId);
                        return StreamBuilder<AppUser?>(
                          stream: memberService.streamUser(b.userId),
                          builder: (_, uSnap) {
                            final u = uSnap.data;
                            final name = (u?.displayName.isNotEmpty == true)
                                ? u!.displayName
                                : u?.email ?? b.userId;
                            return _CheckInRow(
                              name: name,
                              user: u,
                              isCheckedIn: isCheckedIn,
                              onToggle: () async {
                                if (isCheckedIn) {
                                  await bookingService.undoCheckIn(
                                    classId: gymClass.id,
                                    userId: b.userId,
                                  );
                                } else {
                                  await bookingService.checkInMember(
                                    classId: gymClass.id,
                                    userId: b.userId,
                                    checkedInBy: coachId,
                                  );
                                }
                              },
                            );
                          },
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
// Check-in row
// ─────────────────────────────────────────────────────────────────────────────

class _CheckInRow extends StatefulWidget {
  const _CheckInRow({
    required this.name,
    required this.user,
    required this.isCheckedIn,
    required this.onToggle,
  });
  final String name;
  final AppUser? user;
  final bool isCheckedIn;
  final Future<void> Function() onToggle;

  @override
  State<_CheckInRow> createState() => _CheckInRowState();
}

class _CheckInRowState extends State<_CheckInRow> {
  bool _loading = false;

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
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            GestureDetector(
              onTap: () async {
                setState(() => _loading = true);
                await widget.onToggle();
                if (mounted) setState(() => _loading = false);
              },
              child: AnimatedContainer(
                duration: Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: widget.isCheckedIn
                      ? Colors.green.shade100
                      : cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.isCheckedIn
                        ? Colors.green.shade400
                        : cs.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.isCheckedIn
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: widget.isCheckedIn
                          ? Colors.green.shade700
                          : cs.primary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      widget.isCheckedIn
                          ? context.l10n.tr('Present')
                          : context.l10n.tr('Mark in'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: widget.isCheckedIn
                            ? Colors.green.shade700
                            : cs.primary,
                      ),
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
