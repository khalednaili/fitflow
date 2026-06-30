import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import 'package:fit_flow/utils/app_time.dart';
import '../../models/app_user.dart';
import '../../models/gym_class.dart';
import '../../models/user_subscription.dart';
import '../../models/membership_plan.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import '../../services/member_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/announcement_banner.dart';
import '../super_admin/bootstrap_super_admin_screen.dart';
import 'class_details_screen.dart';
import 'membership_screen.dart';
import 'progress_dashboard_screen.dart';
import '../../l10n/app_localizations.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.gymId = '', this.onGoToClasses});

  final String gymId;

  /// Called when the user taps "Browse classes" — lets HomeShell switch tab.
  final VoidCallback? onGoToClasses;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final _memberService = MemberService(gymId: widget.gymId);
  late final _bookingService = BookingService(gymId: widget.gymId);
  late final _classService = ClassService(gymId: widget.gymId);
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);

  late final Stream<AppUser?> _userStream;
  late final Stream<List<dynamic>> _bookingsStream;
  late final Stream<Set<String>> _waitlistedClassIdsStream;
  late final Stream<UserSubscription?> _subscriptionStream;
  late final Stream<List<MembershipPlan>> _allOffersStream;

  // Memoised stream for booked class IDs — only recreated when IDs change.
  Set<String> _lastBookedIds = {};
  Stream<List<GymClass>>? _bookedClassesStream;

  Stream<List<GymClass>> _getBookedClassesStream(Set<String> bookedIds) {
    if (_bookedClassesStream == null || !setEquals(_lastBookedIds, bookedIds)) {
      _lastBookedIds = Set.unmodifiable(bookedIds);
      _bookedClassesStream =
          _classService.streamUpcomingClassesForIds(bookedIds);
    }
    return _bookedClassesStream!;
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userStream =
        user != null ? _memberService.streamUser(user.uid) : Stream.empty();
    _bookingsStream = user != null
        ? _bookingService.streamBookingsForUser(user.uid)
        : Stream.empty();
    _waitlistedClassIdsStream = user != null
        ? _bookingService.streamWaitlistedClassIds(user.uid)
        : Stream.empty();
    _subscriptionStream = user != null
        ? _subscriptionService.streamUserSubscription(user.uid)
        : Stream.empty();
    _allOffersStream = _subscriptionService.streamAllOffers();
  }

  @override
  Widget build(BuildContext context) {
    final fireUser = FirebaseAuth.instance.currentUser;
    if (fireUser == null) {
      return Scaffold(
        body: Center(child: Text(context.l10n.tr('Please sign in.'))),
      );
    }

    return Scaffold(
      body: StreamBuilder<AppUser?>(
        stream: _userStream,
        builder: (context, userSnap) {
          final appUser = userSnap.data;

          return StreamBuilder<List<dynamic>>(
            stream: _bookingsStream,
            builder: (context, bookingSnap) {
              final bookings = bookingSnap.data ?? [];
              final bookedIds =
                  bookings.map((b) => b.classId as String).toSet();

              return StreamBuilder<List<GymClass>>(
                stream: _getBookedClassesStream(bookedIds),
                builder: (context, classSnap) {
                  final upcomingBooked = classSnap.data ?? <GymClass>[];

                  return StreamBuilder<Set<String>>(
                    stream: _waitlistedClassIdsStream,
                    builder: (context, waitlistIdSnap) {
                      final waitlistedIds = waitlistIdSnap.data ?? <String>{};

                      return StreamBuilder<UserSubscription?>(
                        stream: _subscriptionStream,
                        builder: (context, subSnap) {
                          final subscription = subSnap.data;

                          return StreamBuilder<List<MembershipPlan>>(
                            stream: _allOffersStream,
                            builder: (context, planSnap) {
                              final planById = <String, MembershipPlan>{
                                for (final p
                                    in planSnap.data ?? <MembershipPlan>[])
                                  p.id: p,
                              };

                              return _DashboardBody(
                                appUser: appUser,
                                fireUser: fireUser,
                                upcomingBookedClasses: upcomingBooked,
                                totalBookings: bookings.length,
                                subscription: subscription,
                                gymId: widget.gymId,
                                planById: planById,
                                onGoToClasses: widget.onGoToClasses,
                                bookingService: _bookingService,
                                waitlistedClassIds: waitlistedIds,
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
        },
      ),
    );
  }
}

// ── Main body ────────────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.appUser,
    required this.fireUser,
    required this.upcomingBookedClasses,
    required this.totalBookings,
    required this.subscription,
    required this.gymId,
    required this.planById,
    required this.onGoToClasses,
    required this.bookingService,
    required this.waitlistedClassIds,
  });

  final AppUser? appUser;
  final User fireUser;
  final List<GymClass> upcomingBookedClasses;
  final int totalBookings;
  final UserSubscription? subscription;
  final String gymId;
  final Map<String, MembershipPlan> planById;
  final VoidCallback? onGoToClasses;
  final BookingService bookingService;
  final Set<String> waitlistedClassIds;

  String _firstName(AppLocalizations l10n) {
    final name = appUser?.displayName ?? fireUser.displayName ?? '';
    return name.trim().isEmpty ? l10n.tr('Athlete') : name.split(' ').first;
  }

  String _greeting(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour < 12) return l10n.tr('Good morning');
    if (hour < 17) return l10n.tr('Good afternoon');
    return l10n.tr('Good evening');
  }

  // Classes in the current calendar week (Mon–Sun)
  List<GymClass> _classesThisWeek() {
    // Bucketed in the gym's timezone (defaults to device offset).
    final clock = GymClock();
    return upcomingBookedClasses
        .where((c) => clock.isInGymWeek(c.startTime))
        .toList();
  }

  int _classesThisMonth() {
    final clock = GymClock();
    return upcomingBookedClasses
        .where((c) => clock.isInGymMonth(c.startTime))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 700;
    final isVeryWide = size.width >= 1100;
    final nextClass =
        upcomingBookedClasses.isEmpty ? null : upcomingBookedClasses.first;
    final weekClasses = _classesThisWeek();
    final monthCount = _classesThisMonth();

    final Widget topCards = isVeryWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MembershipCard(
                  subscription: subscription,
                  planById: planById,
                  appUser: appUser,
                  gymId: gymId,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _NextClassCard(
                  gymClass: nextClass,
                  userId: fireUser.uid,
                  bookingService: bookingService,
                  onGoToClasses: onGoToClasses,
                  gymId: gymId,
                ),
              ),
            ],
          )
        : Column(
            children: [
              _MembershipCard(
                subscription: subscription,
                planById: planById,
                appUser: appUser,
                gymId: gymId,
              ),
              SizedBox(height: 16),
              _NextClassCard(
                gymClass: nextClass,
                userId: fireUser.uid,
                bookingService: bookingService,
                onGoToClasses: onGoToClasses,
                gymId: gymId,
              ),
            ],
          );

    return CustomScrollView(
      slivers: [
        // ── Greeting App Bar ──────────────────────────────────────
        SliverAppBar(
          expandedHeight: 130,
          pinned: true,
          backgroundColor: cs.surfaceContainerLowest,
          flexibleSpace: FlexibleSpaceBar(
            background: _GreetingHeader(
              greeting: _greeting(context.l10n),
              firstName: _firstName(context.l10n),
              appUser: appUser,
              fireUser: fireUser,
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: isWide ? 760 : double.infinity),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, isWide ? 24 : 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Super-admin bootstrap banner ───────────────────────
                    _BootstrapBanner(appUser: appUser),

                    // ── Gym announcements (banners + popups) ───────────────
                    if (gymId.isNotEmpty)
                      AnnouncementSection(
                        gymId: gymId,
                        userId: fireUser.uid,
                      ),

                    // ── Membership + Next Class (side-by-side on very wide) ──
                    topCards,
                    SizedBox(height: 16),

                    // ── Waitlist card ──────────────────────────────────────
                    if (waitlistedClassIds.isNotEmpty) ...[
                      _WaitlistCard(
                        userId: fireUser.uid,
                        waitlistedClassIds: waitlistedClassIds,
                        bookingService: bookingService,
                        gymId: gymId,
                      ),
                      SizedBox(height: 16),
                    ],

                    // ── This week grid ─────────────────────────────────────
                    _WeekGrid(
                      upcomingBookedClasses: upcomingBookedClasses,
                      weekClasses: weekClasses,
                    ),
                    SizedBox(height: 16),

                    // ── Stats row ──────────────────────────────────────────
                    _StatsRow(
                      totalBookings: totalBookings,
                      monthCount: monthCount,
                      weekCount: weekClasses.length,
                      joinDate: appUser?.joinDate,
                    ),
                    SizedBox(height: 16),

                    // ── Progress card ──────────────────────────────────────
                    _ProgressCard(gymId: gymId),
                    SizedBox(height: 20),

                    // ── Upcoming list ──────────────────────────────────────
                    if (upcomingBookedClasses.length > 1) ...[
                      _SectionTitle(
                        title: context.l10n.tr('Upcoming Classes'),
                        actionLabel: context.l10n.tr('See all'),
                        onAction: onGoToClasses,
                      ),
                      SizedBox(height: 10),
                      ...upcomingBookedClasses
                          .skip(1)
                          .take(3)
                          .map((c) => _UpcomingClassTile(
                                gymClass: c,
                                userId: fireUser.uid,
                                bookingService: bookingService,
                                gymId: gymId,
                              )),
                    ],

                    // ── Browse CTA ─────────────────────────────────────────
                    SizedBox(height: 8),
                    _BrowseClassesButton(onGoToClasses: onGoToClasses),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Greeting header ──────────────────────────────────────────────────────────

// ── Progress card ────────────────────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProgressDashboardScreen(gymId: gymId),
        ),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Color(0xFF0F766E).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bar_chart_rounded,
                    color: Color(0xFF0F766E), size: 22),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tr('My Progress'),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: cs.onSurface),
                    ),
                    Text(
                      context.l10n.tr('Streaks, weekly attendance & PR trends'),
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Greeting header ──────────────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({
    required this.greeting,
    required this.firstName,
    required this.appUser,
    required this.fireUser,
  });

  final String greeting;
  final String firstName;
  final AppUser? appUser;
  final User fireUser;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = firstName[0].toUpperCase();
    final photoUrl = appUser?.photoUrl ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary,
            cs.primary.withValues(alpha: 0.75),
          ],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 12, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$greeting,',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  firstName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          // Avatar
          UserAvatar(
            photoUrl: photoUrl,
            initials: initials,
            color: Colors.white,
            radius: 28,
          ),
        ],
      ),
    );
  }
}

// ── Membership card ──────────────────────────────────────────────────────────

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({
    required this.subscription,
    required this.planById,
    required this.appUser,
    required this.gymId,
  });

  final UserSubscription? subscription;
  final Map<String, MembershipPlan> planById;
  final AppUser? appUser;
  final String gymId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = appUser?.subscriptionStatus ?? 'none';
    final planName = subscription != null
        ? (planById[subscription!.planId]?.name ??
            context.l10n.tr('Active Plan'))
        : context.l10n.tr('No active plan');

    final Color statusColor;
    switch (status) {
      case 'active':
        statusColor = Colors.green.shade600;
      case 'paused':
        statusColor = Colors.orange.shade600;
      case 'cancelled':
        statusColor = Colors.red.shade600;
      default:
        statusColor = Colors.grey.shade500;
    }

    // Days until expiry
    final daysLeft = subscription?.endDate?.difference(DateTime.now()).inDays;

    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_membership_outlined, size: 18, color: cs.primary),
              SizedBox(width: 8),
              Text(context.l10n.tr('Membership'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w700)),
              Spacer(),
              // Status chip
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status == 'none'
                      ? context.l10n.tr('No Plan')
                      : context.l10n.tr(status).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            planName,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (subscription != null) ...[
            SizedBox(height: 8),
            // Payment progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: subscription!.paymentPercentage,
                minHeight: 6,
                backgroundColor: cs.outline.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  subscription!.paymentPercentage >= 1.0
                      ? Colors.green.shade500
                      : cs.primary,
                ),
              ),
            ),
            SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${(subscription!.paymentPercentage * 100).toStringAsFixed(0)}% ${context.l10n.tr('paid')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Spacer(),
                if (daysLeft != null)
                  Text(
                    daysLeft > 0
                        ? '$daysLeft ${context.l10n.tr('days left')}'
                        : daysLeft == 0
                            ? context.l10n.tr('Expires today')
                            : context.l10n.tr('Expired'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: daysLeft <= 7
                              ? Colors.orange.shade600
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
              ],
            ),
          ],
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => MembershipScreen(gymId: gymId)),
              ),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 10),
                textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              child: Text(context.l10n.tr('Manage Membership')),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Next class card ──────────────────────────────────────────────────────────

class _NextClassCard extends StatelessWidget {
  const _NextClassCard({
    required this.gymClass,
    required this.userId,
    required this.bookingService,
    required this.onGoToClasses,
    required this.gymId,
  });

  final GymClass? gymClass;
  final String userId;
  final BookingService bookingService;
  final VoidCallback? onGoToClasses;
  final String gymId;

  String _relativeTime(DateTime dt, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final classDay = DateTime(dt.year, dt.month, dt.day);
    final diff = classDay.difference(today).inDays;
    final timeStr = DateFormat('HH:mm').format(dt);
    if (diff == 0) return '${l10n.tr('Today at')} $timeStr';
    if (diff == 1) return '${l10n.tr('Tomorrow at')} $timeStr';
    return '${DateFormat('EEE, d MMM').format(dt)} ${l10n.tr('at')} $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (gymClass == null) {
      return _DashCard(
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.event_outlined, size: 18, color: cs.primary),
                SizedBox(width: 8),
                Text(context.l10n.tr('Next Class'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.w700)),
              ],
            ),
            SizedBox(height: 20),
            Icon(Icons.fitness_center_outlined,
                size: 40, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
            SizedBox(height: 10),
            Text(context.l10n.tr('No upcoming classes booked'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    )),
            SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onGoToClasses,
              icon: Icon(Icons.search_rounded, size: 18),
              label: Text(context.l10n.tr('Browse Classes')),
            ),
          ],
        ),
      );
    }

    final c = gymClass!;
    final color =
        c.classColorValue != null ? Color(c.classColorValue!) : cs.primary;
    final spotsLeft = c.capacity - c.bookedCount;

    return _DashCard(
      borderColor: color.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_outlined, size: 18, color: color),
              SizedBox(width: 8),
              Text(context.l10n.tr('Next Class'),
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: color, fontWeight: FontWeight.w700)),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$spotsLeft ${context.l10n.tr('spots left')}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Text(
            c.title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.access_time_outlined,
                  size: 15, color: cs.onSurfaceVariant),
              SizedBox(width: 5),
              Text(
                _relativeTime(c.startTime, context.l10n),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              SizedBox(width: 12),
              Icon(Icons.timer_outlined, size: 15, color: cs.onSurfaceVariant),
              SizedBox(width: 4),
              Text(
                '${c.endTime.difference(c.startTime).inMinutes} ${context.l10n.tr('min')}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          if (c.coachName.isNotEmpty) ...[
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 15, color: cs.onSurfaceVariant),
                SizedBox(width: 5),
                Text(c.coachName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        )),
              ],
            ),
          ],
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ClassDetailsScreen(gymClass: c, gymId: gymId),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    textStyle:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  child: Text(context.l10n.tr('View Details')),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _CancelButton(
                  userId: userId,
                  classId: c.id,
                  bookingService: bookingService,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CancelButton extends StatefulWidget {
  const _CancelButton({
    required this.userId,
    required this.classId,
    required this.bookingService,
  });

  final String userId;
  final String classId;
  final BookingService bookingService;

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _cancelling = false;

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    return FilledButton.tonal(
      onPressed: _cancelling
          ? null
          : () async {
              setState(() => _cancelling = true);
              try {
                await widget.bookingService.cancelBooking(
                  userId: widget.userId,
                  classId: widget.classId,
                );
              } catch (e, s) {
                await CrashLogger.log(e, s, reason: 'cancelDashboardBooking');
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              } finally {
                if (mounted) setState(() => _cancelling = false);
              }
            },
      style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: 10),
        textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      child: _cancelling
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Text(context.l10n.tr('Cancel')),
    );
  }
}

// ── Week grid ────────────────────────────────────────────────────────────────

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.upcomingBookedClasses,
    required this.weekClasses,
  });

  final List<GymClass> upcomingBookedClasses;
  final List<GymClass> weekClasses;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));

    // Build set of weekday numbers (1=Mon … 7=Sun) that have a class
    final bookedWeekdays = weekClasses.map((c) => c.startTime.weekday).toSet();

    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_view_week_outlined,
                  size: 18, color: cs.primary),
              SizedBox(width: 8),
              Text(context.l10n.tr('This Week'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w700)),
              Spacer(),
              Text(
                '${weekClasses.length} ${context.l10n.tr(weekClasses.length == 1 ? 'class' : 'classes')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (i) {
              final weekday = i + 1; // 1=Mon
              final dayDate = monday.add(Duration(days: i));
              final dayNum = dayDate.day;
              final isToday = dayDate.year == now.year &&
                  dayDate.month == now.month &&
                  dayDate.day == now.day;
              final hasClass = bookedWeekdays.contains(weekday);
              final isPast = dayDate
                  .add(Duration(days: 1))
                  .isBefore(DateTime(now.year, now.month, now.day));

              return _DayDot(
                label: dayLabels[i],
                dayNum: dayNum,
                hasClass: hasClass,
                isToday: isToday,
                isPast: isPast,
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.dayNum,
    required this.hasClass,
    required this.isToday,
    required this.isPast,
  });

  final String label;
  final int dayNum;
  final bool hasClass;
  final bool isToday;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final dotColor = hasClass
        ? (isPast ? Colors.green.shade300 : cs.primary)
        : Colors.transparent;
    final textColor = isToday
        ? cs.primary
        : isPast
            ? cs.onSurfaceVariant.withValues(alpha: 0.4)
            : cs.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        SizedBox(height: 6),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isToday
                ? cs.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            border: isToday ? Border.all(color: cs.primary, width: 1.5) : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '$dayNum',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                  color: isToday ? cs.primary : textColor,
                ),
              ),
              // Green dot at bottom
              if (hasClass)
                Positioned(
                  bottom: 3,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Stats row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.totalBookings,
    required this.monthCount,
    required this.weekCount,
    required this.joinDate,
  });

  final int totalBookings;
  final int monthCount;
  final int weekCount;
  final DateTime? joinDate;

  @override
  Widget build(BuildContext context) {
    final memberSince =
        joinDate != null ? DateFormat('MMM yyyy').format(joinDate!) : null;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _StatCardWrap(
          value: '$totalBookings',
          label: context.l10n.tr('Total\nBookings'),
          icon: Icons.event_available_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        _StatCardWrap(
          value: '$monthCount',
          label: context.l10n.tr('This\nMonth'),
          icon: Icons.calendar_month_outlined,
          color: Colors.orange.shade600,
        ),
        _StatCardWrap(
          value: '$weekCount',
          label: context.l10n.tr('This\nWeek'),
          icon: Icons.calendar_view_week_outlined,
          color: Colors.teal.shade600,
        ),
        _StatCardWrap(
          value: memberSince ?? '—',
          label: context.l10n.tr('Member\nSince'),
          icon: Icons.star_outline_rounded,
          color: Colors.purple.shade500,
          smallValue: memberSince != null,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.smallValue = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final bool smallValue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: smallValue ? 14 : 22,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Stat card (wrap-friendly) ─────────────────────────────────────────────────

class _StatCardWrap extends StatelessWidget {
  const _StatCardWrap({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.smallValue = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final bool smallValue;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 700;
    final itemWidth = isWide
        ? (760 - 16 * 2 - 10 * 3) / 4.0
        : (screenWidth - 16 * 2 - 10) / 2.0;

    return SizedBox(
      width: itemWidth.clamp(80.0, 200.0),
      child: _StatCard(
        value: value,
        label: label,
        icon: icon,
        color: color,
        smallValue: smallValue,
      ),
    );
  }
}

// ── Upcoming class tile ───────────────────────────────────────────────────────

class _UpcomingClassTile extends StatelessWidget {
  const _UpcomingClassTile({
    required this.gymClass,
    required this.userId,
    required this.bookingService,
    required this.gymId,
  });

  final GymClass gymClass;
  final String userId;
  final BookingService bookingService;
  final String gymId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = gymClass.classColorValue != null
        ? Color(gymClass.classColorValue!)
        : cs.primary;
    final timeStr = DateFormat('EEE, d MMM • HH:mm').format(gymClass.startTime);

    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ClassDetailsScreen(gymClass: gymClass, gymId: gymId),
          ),
        ),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gymClass.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.access_time_outlined,
                            size: 13, color: cs.onSurfaceVariant),
                        SizedBox(width: 4),
                        Text(timeStr,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    )),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        Spacer(),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

// ── Browse classes CTA ────────────────────────────────────────────────────────

class _BrowseClassesButton extends StatelessWidget {
  const _BrowseClassesButton({required this.onGoToClasses});

  final VoidCallback? onGoToClasses;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onGoToClasses,
        icon: Icon(Icons.fitness_center_outlined, size: 18),
        label: Text(context.l10n.tr('Browse All Classes')),
        style: FilledButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

// ── Shared card wrapper ───────────────────────────────────────────────────────

class _DashCard extends StatelessWidget {
  const _DashCard({required this.child, this.borderColor});

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ?? cs.outline.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── Waitlist card ─────────────────────────────────────────────────────────────

class _WaitlistCard extends StatelessWidget {
  const _WaitlistCard({
    required this.userId,
    required this.waitlistedClassIds,
    required this.bookingService,
    required this.gymId,
  });

  final String userId;
  final Set<String> waitlistedClassIds;
  final BookingService bookingService;
  final String gymId;

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      borderColor: Colors.orange.shade300.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_top_outlined,
                        size: 14, color: Colors.orange.shade700),
                    SizedBox(width: 5),
                    Text(
                      context.l10n.tr('On Waitlist'),
                      style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade600,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${waitlistedClassIds.length}',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          ...waitlistedClassIds.take(3).map((id) => _WaitlistEntryRow(
                userId: userId,
                classId: id,
                bookingService: bookingService,
                gymId: gymId,
              )),
          if (waitlistedClassIds.length > 3)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '+${waitlistedClassIds.length - 3} ${context.l10n.tr('more in waitlist')}',
                style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaitlistEntryRow extends StatefulWidget {
  const _WaitlistEntryRow({
    required this.userId,
    required this.classId,
    required this.bookingService,
    required this.gymId,
  });

  final String userId;
  final String classId;
  final BookingService bookingService;
  final String gymId;

  @override
  State<_WaitlistEntryRow> createState() => _WaitlistEntryRowState();
}

class _WaitlistEntryRowState extends State<_WaitlistEntryRow> {
  late final _classService = ClassService(gymId: widget.gymId);
  late final _classFuture = _classService.getClassById(widget.classId);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: FutureBuilder<GymClass?>(
        future: _classFuture,
        builder: (context, snap) {
          final gymClass = snap.data;
          if (gymClass == null) {
            return SizedBox(
              height: 40,
              child: Center(child: LinearProgressIndicator()),
            );
          }

          final localeCode = Localizations.localeOf(context).languageCode;

          return StreamBuilder<int?>(
            stream: widget.bookingService
                .streamUserWaitlistPosition(widget.userId, widget.classId),
            builder: (context, posSnap) {
              final pos = posSnap.data;
              return Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.orange.shade200, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        pos != null ? '#$pos' : '–',
                        style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gymClass.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          DateFormat('EEE, d MMM • HH:mm', localeCode)
                              .format(gymClass.startTime),
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ── Bootstrap banner ─────────────────────────────────────────────────────────

/// Shows a prominent banner when no super admin has been set up yet.
/// Only visible to members; disappears once bootstrap is complete.
class _BootstrapBanner extends StatelessWidget {
  const _BootstrapBanner({required this.appUser});

  final AppUser? appUser;

  @override
  Widget build(BuildContext context) {
    // Only show when the user has no assigned role yet (pre-bootstrap state).
    // Members and any other assigned role should never see this banner.
    if (appUser != null && appUser!.role.isNotEmpty) {
      return SizedBox.shrink();
    }

    return FutureBuilder<bool>(
      future: needsBootstrap(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting ||
            snap.data != true) {
          return SizedBox.shrink();
        }
        return _BootstrapBannerContent();
      },
    );
  }
}

class _BootstrapBannerContent extends StatelessWidget {
  Future<void> _navigateToClaim(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BootstrapSuperAdminScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary,
            cs.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.admin_panel_settings_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.tr('No super admin exists yet'),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    context.l10n.tr('Claim the super admin role to get started!'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: FilledButton.tonal(
                      onPressed: () => _navigateToClaim(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: cs.primary,
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        textStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      child: Text(context.l10n.tr('Claim Super Admin')),
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
