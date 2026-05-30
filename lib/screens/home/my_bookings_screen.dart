import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../../l10n/app_localizations.dart';
import '../../models/booking.dart';
import '../../models/gym_class.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import 'class_details_screen.dart';
import 'rate_class_sheet.dart';
import '../checkin/qr_scanner_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key, this.gymId = ''});

  final String gymId;

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final _bookingService = BookingService(gymId: widget.gymId);

  late final Stream<List<Booking>> _bookingsStream;
  late final Stream<Set<String>> _waitlistedClassIdsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final user = FirebaseAuth.instance.currentUser;
    _bookingsStream = user != null
        ? _bookingService.streamBookingsForUser(user.uid)
        : Stream.empty();
    _waitlistedClassIdsStream = user != null
        ? _bookingService.streamWaitlistedClassIds(user.uid)
        : Stream.empty();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(context.l10n.tr('Please sign in to see bookings.')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: StreamBuilder<List<Booking>>(
        stream: _bookingsStream,
        builder: (context, bookingSnap) {
          if (bookingSnap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (bookingSnap.hasError) {
            return _ErrorState(error: bookingSnap.error.toString());
          }

          final bookings = bookingSnap.data ?? <Booking>[];

          return StreamBuilder<Set<String>>(
            stream: _waitlistedClassIdsStream,
            builder: (context, waitlistSnap) {
              if (waitlistSnap.hasError) {
                return _ErrorState(error: waitlistSnap.error.toString());
              }

              final waitlistIds = waitlistSnap.data ?? <String>{};

              return NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  // ── App bar (title only – no expandedHeight) ──────────
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: cs.primary,
                    title: Text(
                      context.l10n.tr('My Bookings'),
                      style: TextStyle(color: Colors.white),
                    ),
                    iconTheme: IconThemeData(color: Colors.white),
                  ),
                  // ── Stats (self-sizing, no overflow risk) ─────────────
                  SliverToBoxAdapter(
                    child: _StatsHeader(
                      bookingsCount: bookings.length,
                      waitlistCount: waitlistIds.length,
                    ),
                  ),
                  // ── Tab bar ──────────────────────────────────────────
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(
                      TabBar(
                        controller: _tabController,
                        labelColor: cs.primary,
                        unselectedLabelColor: cs.onSurfaceVariant,
                        indicatorColor: cs.primary,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: cs.outlineVariant,
                        tabs: [
                          Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(context.l10n.tr('Bookings')),
                                if (bookings.isNotEmpty) ...[
                                  SizedBox(width: 6),
                                  _CountBadge(
                                      count: bookings.length,
                                      color: cs.primary),
                                ],
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(context.l10n.tr('Waitlist')),
                                if (waitlistIds.isNotEmpty) ...[
                                  SizedBox(width: 6),
                                  _CountBadge(
                                      count: waitlistIds.length,
                                      color: Colors.orange.shade700),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    // ── Bookings ──────────────────────────────────────
                    bookings.isEmpty
                        ? _EmptyState(
                            icon: Icons.event_available_outlined,
                            title: context.l10n.tr('No bookings yet'),
                            subtitle:
                                context.l10n.tr('Browse the schedule and book your next WOD.'),
                          )
                        : _CenteredList(
                            isWide: isWide,
                            itemCount: bookings.length,
                            itemBuilder: (context, i) => _BookingCard(
                              booking: bookings[i],
                              gymId: widget.gymId,
                            ),
                          ),

                    // ── Waitlist ──────────────────────────────────────
                    waitlistIds.isEmpty
                        ? _EmptyState(
                            icon: Icons.hourglass_empty_outlined,
                            title: context.l10n.tr('Not on any waitlist'),
                            subtitle:
                                context.l10n.tr('Join a full class to be auto-promoted when a spot opens.'),
                          )
                        : _CenteredList(
                            isWide: isWide,
                            itemCount: waitlistIds.length,
                            itemBuilder: (context, i) => _WaitlistCard(
                              classId: waitlistIds.elementAt(i),
                              gymId: widget.gymId,
                            ),
                          ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Stats header ──────────────────────────────────────────────────────────────

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.bookingsCount,
    required this.waitlistCount,
  });

  final int bookingsCount;
  final int waitlistCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, isWide ? 20 : 12, 16, isWide ? 20 : 16),
      child: Row(
        children: [
          _StatItem(
              value: '$bookingsCount',
              label: context.l10n.tr('Total Bookings'),
              icon: Icons.event_available_outlined,
              isWide: isWide),
          SizedBox(width: 12),
          _StatItem(
              value: '$waitlistCount',
              label: context.l10n.tr('Waitlisted'),
              icon: Icons.hourglass_top_outlined,
              isWide: isWide),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem(
      {required this.value,
      required this.label,
      required this.icon,
      this.isWide = false});
  final String value;
  final String label;
  final IconData icon;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: isWide ? 22 : 18),
            SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: isWide ? 28 : 20,
                    fontWeight: FontWeight.w800)),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: isWide ? 13 : 11)),
          ],
        ),
      ),
    );
  }
}

// ── Booking card ──────────────────────────────────────────────────────────────

class _BookingCard extends StatefulWidget {
  const _BookingCard({required this.booking, this.gymId = ''});
  final Booking booking;
  final String gymId;

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  late final _classService = ClassService(gymId: widget.gymId);
  late final _bookingService = BookingService(gymId: widget.gymId);
  bool _cancelling = false;

  Future<void> _confirmCancel(GymClass gymClass) async {
    // Block cancellation if the class has already started
    if (gymClass.startTime.isBefore(DateTime.now())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n
              .tr('You cannot cancel a booking after the class has started.')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if a late-cancellation penalty applies
    final lateMins = await _bookingService.getLateCancellationMinutes();
    final minutesUntilClass =
        gymClass.startTime.difference(DateTime.now()).inMinutes;
    final isLatePenalty =
        lateMins > 0 && minutesUntilClass >= 0 && minutesUntilClass < lateMins;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Cancel booking?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${context.l10n.tr('Cancel your spot in')} "${gymClass.title}"?\n${context.l10n.tr('Any waitlisted members will be promoted automatically.')}'),
            if (isLatePenalty) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.timer_off_outlined,
                        color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ ${context.l10n.tr('Late cancellation: the class starts in')} '
                        '$minutesUntilClass ${context.l10n.tr('min')}. ${context.l10n.tr('This cancellation will count as a used session against your offer.')}',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.tr('Keep')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.tr('Cancel booking')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _bookingService.cancelBooking(
        userId: widget.booking.userId,
        classId: widget.booking.classId,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(isLatePenalty
              ? context.l10n.tr('Booking cancelled — late cancellation penalty applied.')
              : '${context.l10n.tr('Booking for')} "${gymClass.title}" ${context.l10n.tr('cancelled.')}'),
          backgroundColor:
              isLatePenalty ? Colors.orange.shade700 : Colors.orange.shade700,
        ),
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'cancelBooking');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<GymClass?>(
      future: _classService.getClassById(widget.booking.classId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _CardSkeleton();
        }
        final gymClass = snap.data;
        if (gymClass == null) {
          return Card(
            margin: EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(Icons.broken_image_outlined),
              title: Text(context.l10n.tr('Class no longer available')),
              subtitle:
                  Text(widget.booking.classId, style: TextStyle(fontSize: 11)),
            ),
          );
        }

        final now = DateTime.now();
        final hasStarted = gymClass.startTime.isBefore(now);
        final isPast = gymClass.endTime.isBefore(now);
        final isToday = gymClass.startTime.day == now.day &&
            gymClass.startTime.month == now.month &&
            gymClass.startTime.year == now.year;
        final isTomorrow =
            !isToday && gymClass.startTime.isBefore(now.add(Duration(days: 2)));
        final minutesUntil = gymClass.startTime.difference(now).inMinutes;
        final accentColor =
            isPast ? cs.onSurfaceVariant.withValues(alpha: 0.5) : cs.primary;

        String timeLabel;
        if (isPast) {
          timeLabel = DateFormat('EEE, d MMM').format(gymClass.startTime);
        } else if (isToday) {
          if (minutesUntil <= 60 && minutesUntil > 0) {
            timeLabel = '${context.l10n.tr('In')} ${minutesUntil}m';
          } else {
            timeLabel =
                '${context.l10n.tr('Today at')} ${DateFormat('HH:mm').format(gymClass.startTime)}';
          }
        } else if (isTomorrow) {
          timeLabel =
              '${context.l10n.tr('Tomorrow at')} ${DateFormat('HH:mm').format(gymClass.startTime)}';
        } else {
          timeLabel =
              DateFormat('EEE, d MMM • HH:mm').format(gymClass.startTime);
        }

        final durationMins =
            gymClass.endTime.difference(gymClass.startTime).inMinutes;

        return Card(
          margin: EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: isPast
                    ? cs.outlineVariant
                    : accentColor.withValues(alpha: 0.3),
                width: isPast ? 1 : 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => ClassDetailsScreen(
                      gymClass: gymClass, gymId: widget.gymId)),
            ),
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top row ──────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Accent icon box
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: accentColor.withValues(alpha: 0.25)),
                        ),
                        child: Icon(
                          isPast
                              ? Icons.check_circle_outline
                              : Icons.fitness_center,
                          color: accentColor,
                          size: 22,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(gymClass.title,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isPast
                                        ? cs.onSurfaceVariant
                                        : cs.onSurface)),
                            SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(Icons.person_outline,
                                    size: 13, color: cs.onSurfaceVariant),
                                SizedBox(width: 4),
                                Text(gymClass.coachName,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Status badge
                      _StatusBadge(isPast: isPast, isToday: isToday),
                    ],
                  ),

                  SizedBox(height: 12),
                  Divider(height: 1, color: cs.outlineVariant),
                  SizedBox(height: 10),

                  // ── Info chips ────────────────────────────────────
                  Row(
                    children: [
                      _InfoChip(
                          icon: Icons.access_time_outlined,
                          label: timeLabel,
                          color: isPast ? cs.onSurfaceVariant : accentColor),
                      SizedBox(width: 8),
                      _InfoChip(
                          icon: Icons.timer_outlined,
                          label: '$durationMins ${context.l10n.tr('min')}',
                          color: cs.onSurfaceVariant),
                      Spacer(),
                      _InfoChip(
                          icon: Icons.people_outline,
                          label: '${gymClass.bookedCount}/${gymClass.capacity}',
                          color: cs.onSurfaceVariant),
                    ],
                  ),

                  // ── Action buttons ────────────────────────────────
                  if (!isPast) ...[
                    SizedBox(height: 12),
                    // ── Check-in window: show scan button ──────────
                    Builder(builder: (ctx) {
                      final windowOpen =
                          gymClass.startTime.subtract(Duration(hours: 1));
                      final canCheckIn = now.isAfter(windowOpen) &&
                          now.isBefore(gymClass.endTime);
                      if (canCheckIn) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => QrScannerScreen()),
                              ),
                              icon:
                                  Icon(Icons.qr_code_scanner_rounded, size: 18),
                              label:
                                  Text(context.l10n.tr('Scan QR · Check In')),
                              style: FilledButton.styleFrom(
                                backgroundColor: Color(0xFF0F766E),
                                padding: EdgeInsets.symmetric(vertical: 12),
                                textStyle: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        );
                      }
                      return SizedBox.shrink();
                    }),
                    Row(
                      children: [
                        // View details
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => ClassDetailsScreen(
                                      gymClass: gymClass, gymId: widget.gymId)),
                            ),
                            icon: Icon(Icons.open_in_new, size: 15),
                            label: Text(context.l10n.tr('View Details')),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              textStyle: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        // Cancel — hidden after class has started
                        if (!hasStarted)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _cancelling
                                  ? null
                                  : () => _confirmCancel(gymClass),
                              icon: _cancelling
                                  ? SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Icon(Icons.cancel_outlined, size: 15),
                              label:
                                  Text(_cancelling ? context.l10n.tr('Cancelling…') : context.l10n.tr('Cancel')),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                textStyle: TextStyle(fontSize: 13),
                                foregroundColor: Colors.red.shade600,
                                side: BorderSide(color: Colors.red.shade200),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ] else ...[
                    // Past: view details + rate (if checked in)
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => ClassDetailsScreen(
                                      gymClass: gymClass, gymId: widget.gymId)),
                            ),
                            icon: Icon(Icons.open_in_new, size: 15),
                            label: Text(context.l10n.tr('View Class')),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              textStyle: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        if (widget.booking.checkedIn) ...[
                          SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => RateClassSheet.show(
                                context,
                                classId: gymClass.id,
                                className: gymClass.title,
                                gymId: widget.gymId,
                              ),
                              icon: Icon(Icons.star_outline_rounded, size: 15),
                              label: Text(context.l10n.tr('Rate')),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                textStyle: TextStyle(fontSize: 13),
                                foregroundColor: Colors.amber.shade700,
                                side: BorderSide(
                                    color: Colors.amber.shade300),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Waitlist card ─────────────────────────────────────────────────────────────

class _WaitlistCard extends StatefulWidget {
  const _WaitlistCard({required this.classId, this.gymId = ''});
  final String classId;
  final String gymId;

  @override
  State<_WaitlistCard> createState() => _WaitlistCardState();
}

class _WaitlistCardState extends State<_WaitlistCard> {
  late final _classService = ClassService(gymId: widget.gymId);
  late final _bookingService = BookingService(gymId: widget.gymId);
  bool _leaving = false;

  Future<void> _leave() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _leaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _bookingService.leaveWaitlist(
          userId: user.uid, classId: widget.classId);
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.tr('Left waitlist.'))));
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'leaveWaitlist');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<GymClass?>(
      future: _classService.getClassById(widget.classId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _CardSkeleton();
        }
        final gymClass = snap.data;
        if (gymClass == null) {
          return Card(
            margin: EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(Icons.broken_image_outlined),
              title: Text(context.l10n.tr('Class no longer available')),
            ),
          );
        }

        final durationMins =
            gymClass.endTime.difference(gymClass.startTime).inMinutes;

        return StreamBuilder<int?>(
          stream: user != null
              ? _bookingService.streamUserWaitlistPosition(
                  user.uid, widget.classId)
              : Stream<int?>.empty(),
          builder: (context, posSnap) {
            final position = posSnap.data;

            return Card(
              margin: EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: Colors.orange.shade300.withValues(alpha: 0.7),
                    width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => ClassDetailsScreen(
                          gymClass: gymClass, gymId: widget.gymId)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Queue position badge
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.orange.shade300, width: 1.5),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.hourglass_top_outlined,
                                    size: 15, color: Colors.orange.shade700),
                                if (position != null)
                                  Text('#$position',
                                      style: TextStyle(
                                          color: Colors.orange.shade800,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(gymClass.title,
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                                SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.person_outline,
                                        size: 13, color: cs.onSurfaceVariant),
                                    SizedBox(width: 4),
                                    Text(gymClass.coachName,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              position != null
                                  ? '#$position ${context.l10n.tr('in queue')}'
                                  : context.l10n.tr('Waitlisted'),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade800),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Divider(height: 1, color: cs.outlineVariant),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          _InfoChip(
                              icon: Icons.access_time_outlined,
                              label: DateFormat('EEE, d MMM • HH:mm')
                                  .format(gymClass.startTime),
                              color: Colors.orange.shade700),
                          SizedBox(width: 8),
                          _InfoChip(
                              icon: Icons.timer_outlined,
                              label: '$durationMins ${context.l10n.tr('min')}',
                              color: cs.onSurfaceVariant),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => ClassDetailsScreen(
                                        gymClass: gymClass,
                                        gymId: widget.gymId)),
                              ),
                              icon: Icon(Icons.open_in_new, size: 15),
                              label: Text(context.l10n.tr('View Details')),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                textStyle: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _leaving ? null : _leave,
                              icon: _leaving
                                  ? SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Icon(Icons.exit_to_app_outlined, size: 15),
                              label:
                                  Text(_leaving ? context.l10n.tr('Leaving…') : context.l10n.tr('Leave Queue')),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                textStyle: TextStyle(fontSize: 13),
                                foregroundColor: Colors.orange.shade700,
                                side: BorderSide(color: Colors.orange.shade300),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isPast, required this.isToday});
  final bool isPast;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    final IconData icon;

    if (isPast) {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
      label = context.l10n.tr('Completed');
      icon = Icons.check_circle_outline;
    } else if (isToday) {
      bg = Colors.blue.shade50;
      fg = Colors.blue.shade700;
      label = context.l10n.tr('Today');
      icon = Icons.today_outlined;
    } else {
      bg = Theme.of(context).colorScheme.primaryContainer;
      fg = Theme.of(context).colorScheme.onPrimaryContainer;
      label = context.l10n.tr('Booked');
      icon = Icons.bookmark_added_outlined;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$count',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: cs.primary),
            ),
            SizedBox(height: 18),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            SizedBox(height: 12),
            Text(context.l10n.tr('Failed to load bookings'),
                style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 6),
            Text(error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 140,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: 6),
                  Container(
                    height: 11,
                    width: 90,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
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

// ── Tab bar persistent header ─────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) => old.tabBar != tabBar;
}

// ── Centered constrained list ─────────────────────────────────────────────────

class _CenteredList extends StatelessWidget {
  const _CenteredList({
    required this.isWide,
    required this.itemCount,
    required this.itemBuilder,
  });

  final bool isWide;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 760 : double.infinity),
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 12, 16, isWide ? 24 : 100),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}
