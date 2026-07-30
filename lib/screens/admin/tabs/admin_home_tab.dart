import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/booking.dart';
import '../../../models/gym_class.dart';
import '../../../models/user_subscription.dart';
import '../../../models/wod_entry.dart';
import '../../../services/booking_service.dart';
import '../../../services/class_service.dart';
import '../../../services/member_service.dart';
import '../../../services/subscription_service.dart';
import '../../../services/wod_service.dart';
import '../../../widgets/user_avatar.dart';

/// Admin landing page: a "Dashboard" overview of the gym's day-to-day
/// activity — today's booking stats, the schedule, workouts, and rosters of
/// members that need attention (birthdays, non-attendance, expiring
/// contracts, new sign-ups, health notes).
class AdminHomeTab extends StatefulWidget {
  const AdminHomeTab({super.key, required this.gymId, this.firestore});

  final String gymId;

  /// Injectable Firestore instance for tests (defaults to
  /// [FirebaseFirestore.instance] when null).
  final FirebaseFirestore? firestore;

  @override
  State<AdminHomeTab> createState() => _AdminHomeTabState();
}

class _AdminHomeTabState extends State<AdminHomeTab> {
  late final _memberService =
      MemberService(gymId: widget.gymId, firestore: widget.firestore);
  late final _classService =
      ClassService(gymId: widget.gymId, firestore: widget.firestore);
  late final _bookingService =
      BookingService(gymId: widget.gymId, firestore: widget.firestore);
  late final _wodService =
      WodService(gymId: widget.gymId, firestore: widget.firestore);
  late final _subscriptionService =
      SubscriptionService(gymId: widget.gymId, firestore: widget.firestore);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: _memberService.streamMembers(),
      builder: (context, memberSnap) {
        final members = memberSnap.data ?? const <AppUser>[];
        return StreamBuilder<List<GymClass>>(
          stream: _classService.streamAllClasses(),
          builder: (context, classSnap) {
            final classes = classSnap.data ?? const <GymClass>[];
            return StreamBuilder<List<Booking>>(
              stream: _bookingService.streamAllBookingsForGym(),
              builder: (context, bookingSnap) {
                final bookings = bookingSnap.data ?? const <Booking>[];
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _bookingService.streamLateCancellationsForGym(),
                  builder: (context, cancelSnap) {
                    final cancellations =
                        cancelSnap.data ?? const <Map<String, dynamic>>[];
                    return StreamBuilder<List<UserSubscription>>(
                      stream: _subscriptionService.streamAllUserSubscriptions(),
                      builder: (context, subSnap) {
                        final subscriptions =
                            subSnap.data ?? const <UserSubscription>[];
                        final loading = memberSnap.connectionState ==
                                ConnectionState.waiting &&
                            members.isEmpty;
                        if (loading) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        return _DashboardBody(
                          gymId: widget.gymId,
                          members: members,
                          classes: classes,
                          bookings: bookings,
                          cancellations: cancellations,
                          subscriptions: subscriptions,
                          wodService: _wodService,
                        );
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

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.gymId,
    required this.members,
    required this.classes,
    required this.bookings,
    required this.cancellations,
    required this.subscriptions,
    required this.wodService,
  });

  final String gymId;
  final List<AppUser> members;
  final List<GymClass> classes;
  final List<Booking> bookings;
  final List<Map<String, dynamic>> cancellations;
  final List<UserSubscription> subscriptions;
  final WodService wodService;

  @override
  Widget build(BuildContext context) {
    final columnA = <Widget>[
      _ClassStatsCard(bookings: bookings, cancellations: cancellations),
      const SizedBox(height: 16),
      _ScheduleCard(classes: classes),
      const SizedBox(height: 16),
      _WorkoutsCard(wodService: wodService),
    ];
    final columnB = <Widget>[
      _BirthdaysCard(members: members),
      const SizedBox(height: 16),
      _NonAttendanceCard(members: members, bookings: bookings),
      const SizedBox(height: 16),
      _ContractsExpiringCard(members: members, subscriptions: subscriptions),
    ];
    final columnC = <Widget>[
      _HealthNotesCard(members: members),
      const SizedBox(height: 16),
      _NewSignUpsCard(members: members),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1100;
      final medium = constraints.maxWidth >= 760;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: columnA)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(children: columnB)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(children: columnC)),
                ],
              )
            : medium
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Column(children: [...columnA, ...columnC])),
                      const SizedBox(width: 16),
                      Expanded(child: Column(children: columnB)),
                    ],
                  )
                : Column(children: [...columnA, ...columnB, ...columnC]),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared card chrome
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.color, required this.child});

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.tr(title),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        context.l10n.tr(label),
        style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13),
      ),
    );
  }
}

/// Horizontal pill selector used by the "N weeks" widgets.
class _WeekTabs extends StatelessWidget {
  const _WeekTabs({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [1, 2, 3, 4].map((w) {
        final selected = w == value;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => onChanged(w),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$w ${context.l10n.tr(w == 1 ? 'Week' : 'Weeks')}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onPrimaryContainer : cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.user, required this.subtitle});

  final AppUser user;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.trim().isNotEmpty ? user.displayName : user.email;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          UserAvatar(
            photoUrl: user.photoUrl,
            initials: initials,
            color: const Color(0xFF0F766E),
            radius: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Class Stats
// ─────────────────────────────────────────────────────────────────────────────

class _ClassStatsCard extends StatelessWidget {
  const _ClassStatsCard({required this.bookings, required this.cancellations});

  final List<Booking> bookings;
  final List<Map<String, dynamic>> cancellations;

  bool _isToday(DateTime? d) {
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todaysBookings = bookings.where((b) => _isToday(b.classStartTime)).toList();
    final bookedToday = todaysBookings.length;
    final noShows = todaysBookings
        .where((b) => b.classEndTime != null && b.classEndTime!.isBefore(now) && !b.checkedIn)
        .length;
    final cancelledToday = cancellations.where((c) {
      final ts = c['cancelledAt'];
      final d = ts is DateTime ? ts : (ts?.toDate() as DateTime?);
      return _isToday(d);
    }).length;

    return _Card(
      title: 'Class Stats',
      icon: Icons.insights_outlined,
      color: const Color(0xFF0F766E),
      child: Row(
        children: [
          Expanded(child: _StatBlock(value: '$bookedToday', label: 'Bookings', color: const Color(0xFF0F766E))),
          Expanded(child: _StatBlock(value: '$cancelledToday', label: 'Cancellations', color: const Color(0xFFF97316))),
          Expanded(child: _StatBlock(value: '$noShows', label: 'No Shows', color: const Color(0xFFDC2626))),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(context.l10n.tr(label),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleCard extends StatefulWidget {
  const _ScheduleCard({required this.classes});
  final List<GymClass> classes;

  @override
  State<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<_ScheduleCard> {
  DateTime _day = DateTime.now();

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final todays = widget.classes.where((c) => _isSameDay(c.startTime, _day)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return _Card(
      title: 'Schedule',
      icon: Icons.event_note_outlined,
      color: const Color(0xFF0F766E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))),
              ),
              Text(DateFormat('EEE d MMM').format(_day),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => setState(() => _day = _day.add(const Duration(days: 1))),
              ),
            ],
          ),
          if (todays.isEmpty)
            const _EmptyRow('No classes scheduled')
          else
            ...todays.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${c.title} (${DateFormat('HH:mm').format(c.startTime)} - ${DateFormat('HH:mm').format(c.endTime)})',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            Text(
                              c.coachName.isNotEmpty ? c.coachName : context.l10n.tr('Unassigned'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
                            ),
                          ],
                        ),
                      ),
                      Text('${c.bookedCount} / ${c.capacity}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Workouts
// ─────────────────────────────────────────────────────────────────────────────

class _WorkoutsCard extends StatefulWidget {
  const _WorkoutsCard({required this.wodService});
  final WodService wodService;

  @override
  State<_WorkoutsCard> createState() => _WorkoutsCardState();
}

class _WorkoutsCardState extends State<_WorkoutsCard> {
  DateTime _day = DateTime.now();
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Workouts',
      icon: Icons.local_fire_department_outlined,
      color: const Color(0xFFF97316),
      child: StreamBuilder<List<WodEntry>>(
        stream: widget.wodService.streamForDate(_day),
        builder: (context, snap) {
          final wods = snap.data ?? const <WodEntry>[];
          if (_selected >= wods.length) _selected = 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () =>
                        setState(() => _day = _day.subtract(const Duration(days: 1))),
                  ),
                  Text(DateFormat('EEE d MMM').format(_day),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => setState(() => _day = _day.add(const Duration(days: 1))),
                  ),
                ],
              ),
              if (wods.isEmpty)
                const _EmptyRow('No workout logged for this day')
              else ...[
                if (wods.length > 1)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(wods.length, (i) {
                        final selected = i == _selected;
                        final label = wods[i].classTypeName.isNotEmpty
                            ? wods[i].classTypeName
                            : wods[i].title;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6, bottom: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _selected = i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(label,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Theme.of(context).colorScheme.onPrimaryContainer
                                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                _WorkoutContent(wod: wods[_selected]),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WorkoutContent extends StatelessWidget {
  const _WorkoutContent({required this.wod});
  final WodEntry wod;

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[
      Text(wod.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
    ];
    if (wod.warmUp.trim().isNotEmpty) {
      lines.add(const SizedBox(height: 6));
      lines.add(Text(context.l10n.tr('Warm Up'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)));
      lines.add(Text(wod.warmUp, style: const TextStyle(fontSize: 12.5)));
    }
    if (wod.parts.isNotEmpty) {
      for (final part in wod.parts) {
        lines.add(const SizedBox(height: 8));
        lines.add(Text(part.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)));
        if (part.description.trim().isNotEmpty) {
          lines.add(Text(part.description, style: const TextStyle(fontSize: 12.5)));
        }
        for (final ex in part.exercises) {
          final label = ex.shortLabel;
          lines.add(Text(
            label.isNotEmpty ? '${ex.name} — $label' : ex.name,
            style: const TextStyle(fontSize: 12.5),
          ));
        }
      }
    } else if (wod.exercises.isNotEmpty) {
      for (final ex in wod.exercises) {
        final label = ex.shortLabel;
        lines.add(Text(
          label.isNotEmpty ? '${ex.name} — $label' : ex.name,
          style: const TextStyle(fontSize: 12.5),
        ));
      }
    } else if (wod.description.trim().isNotEmpty) {
      lines.add(Text(wod.description, style: const TextStyle(fontSize: 12.5)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upcoming Birthdays
// ─────────────────────────────────────────────────────────────────────────────

class _BirthdaysCard extends StatelessWidget {
  const _BirthdaysCard({required this.members});
  final List<AppUser> members;

  /// Days from today until the member's next birthday (0-365).
  int _daysUntilNextBirthday(DateTime dob, DateTime now) {
    var next = DateTime(now.year, dob.month, dob.day);
    final today = DateTime(now.year, now.month, now.day);
    if (next.isBefore(today)) next = DateTime(now.year + 1, dob.month, dob.day);
    return next.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final withBirthdays = members.where((m) => m.dateOfBirth != null).toList()
      ..sort((a, b) => _daysUntilNextBirthday(a.dateOfBirth!, now)
          .compareTo(_daysUntilNextBirthday(b.dateOfBirth!, now)));
    final upcoming = withBirthdays
        .where((m) => _daysUntilNextBirthday(m.dateOfBirth!, now) <= 30)
        .take(5)
        .toList();

    return _Card(
      title: 'Upcoming Birthdays',
      icon: Icons.cake_outlined,
      color: const Color(0xFFDB2777),
      child: upcoming.isEmpty
          ? const _EmptyRow('No birthdays in the next 30 days')
          : Column(
              children: upcoming.map((m) {
                final dob = m.dateOfBirth!;
                final next = DateTime(now.year, dob.month, dob.day)
                    .isBefore(DateTime(now.year, now.month, now.day))
                        ? DateTime(now.year + 1, dob.month, dob.day)
                        : DateTime(now.year, dob.month, dob.day);
                final ageTurning = next.year - dob.year;
                return _MemberRow(
                  user: m,
                  subtitle: '${DateFormat('d MMM').format(next)} ($ageTurning)',
                );
              }).toList(),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Non-Attendance
// ─────────────────────────────────────────────────────────────────────────────

class _NonAttendanceCard extends StatefulWidget {
  const _NonAttendanceCard({required this.members, required this.bookings});
  final List<AppUser> members;
  final List<Booking> bookings;

  @override
  State<_NonAttendanceCard> createState() => _NonAttendanceCardState();
}

class _NonAttendanceCardState extends State<_NonAttendanceCard> {
  int _weeks = 1;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lastAttended = <String, DateTime>{};
    for (final b in widget.bookings) {
      final start = b.classStartTime;
      if (start == null || start.isAfter(now)) continue;
      final current = lastAttended[b.userId];
      if (current == null || start.isAfter(current)) lastAttended[b.userId] = start;
    }
    final cutoff = now.subtract(Duration(days: 7 * _weeks));
    final active = widget.members.where((m) => m.subscriptionStatus == 'active');
    final nonAttendees = active.where((m) {
      final last = lastAttended[m.id];
      return last == null || last.isBefore(cutoff);
    }).toList()
      ..sort((a, b) {
        final la = lastAttended[a.id];
        final lb = lastAttended[b.id];
        if (la == null && lb == null) return 0;
        if (la == null) return 1;
        if (lb == null) return -1;
        return lb.compareTo(la);
      });

    return _Card(
      title: 'Non-Attendance',
      icon: Icons.event_busy_outlined,
      color: const Color(0xFFDC2626),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeekTabs(value: _weeks, onChanged: (w) => setState(() => _weeks = w)),
          const SizedBox(height: 8),
          if (nonAttendees.isEmpty)
            const _EmptyRow('No inactive members in this period')
          else
            ...nonAttendees.take(5).map((m) {
              final last = lastAttended[m.id];
              final subtitle = last == null
                  ? context.l10n.tr('No recorded attendance')
                  : '${context.l10n.tr('Last Attended')}: ${DateFormat('d MMM').format(last)}';
              return _MemberRow(user: m, subtitle: subtitle);
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New Sign Ups
// ─────────────────────────────────────────────────────────────────────────────

class _NewSignUpsCard extends StatefulWidget {
  const _NewSignUpsCard({required this.members});
  final List<AppUser> members;

  @override
  State<_NewSignUpsCard> createState() => _NewSignUpsCardState();
}

class _NewSignUpsCardState extends State<_NewSignUpsCard> {
  int _weeks = 1;

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(Duration(days: 7 * _weeks));
    final recent = widget.members.where((m) => m.joinDate != null && m.joinDate!.isAfter(cutoff)).toList()
      ..sort((a, b) => b.joinDate!.compareTo(a.joinDate!));

    return _Card(
      title: 'New Sign Ups',
      icon: Icons.person_add_alt_1_outlined,
      color: const Color(0xFF2563EB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeekTabs(value: _weeks, onChanged: (w) => setState(() => _weeks = w)),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            const _EmptyRow('No new sign-ups in this period')
          else
            ...recent.take(5).map((m) => _MemberRow(
                  user: m,
                  subtitle: '${context.l10n.tr('Joined')}: ${DateFormat('d MMM').format(m.joinDate!)}',
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contracts Expiring
// ─────────────────────────────────────────────────────────────────────────────

class _ContractsExpiringCard extends StatefulWidget {
  const _ContractsExpiringCard({required this.members, required this.subscriptions});
  final List<AppUser> members;
  final List<UserSubscription> subscriptions;

  @override
  State<_ContractsExpiringCard> createState() => _ContractsExpiringCardState();
}

class _ContractsExpiringCardState extends State<_ContractsExpiringCard> {
  int _weeks = 1;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final horizon = now.add(Duration(days: 7 * _weeks));
    final membersById = {for (final m in widget.members) m.id: m};

    final expiring = widget.subscriptions.where((s) {
      if (s.status != 'active' || s.endDate == null) return false;
      return s.endDate!.isAfter(now) && s.endDate!.isBefore(horizon);
    }).toList()
      ..sort((a, b) => a.endDate!.compareTo(b.endDate!));

    return _Card(
      title: 'Contracts Expiring',
      icon: Icons.assignment_late_outlined,
      color: const Color(0xFFEA580C),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeekTabs(value: _weeks, onChanged: (w) => setState(() => _weeks = w)),
          const SizedBox(height: 8),
          if (expiring.isEmpty)
            const _EmptyRow('No contracts expiring in this period')
          else
            ...expiring.take(5).map((s) {
              final member = membersById[s.userId];
              if (member == null) return const SizedBox.shrink();
              return _MemberRow(
                user: member,
                subtitle: '${context.l10n.tr('Expires')}: ${DateFormat('d MMM').format(s.endDate!)}',
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent Health Notes (this app tracks free-text health notes rather than
// structured injury records, so this widget surfaces members with a
// non-empty note instead of a dated injury log).
// ─────────────────────────────────────────────────────────────────────────────

class _HealthNotesCard extends StatelessWidget {
  const _HealthNotesCard({required this.members});
  final List<AppUser> members;

  @override
  Widget build(BuildContext context) {
    final withNotes = members.where((m) => m.healthNotes.trim().isNotEmpty).take(5).toList();

    return _Card(
      title: 'Recent Health Notes',
      icon: Icons.medical_information_outlined,
      color: const Color(0xFF9333EA),
      child: withNotes.isEmpty
          ? const _EmptyRow('No health notes on file')
          : Column(
              children: withNotes
                  .map((m) => _MemberRow(user: m, subtitle: m.healthNotes.trim()))
                  .toList(),
            ),
    );
  }
}
