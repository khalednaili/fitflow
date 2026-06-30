import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import 'package:fit_flow/utils/currency.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/booking.dart';
import '../../models/gym_class.dart';
import '../../models/membership_plan.dart';
import '../../models/user_subscription.dart';
import '../../models/waitlist_entry.dart';
import '../../models/wod_entry.dart';
import '../../services/auth_service.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import '../../services/friend_service.dart';
import '../../services/member_service.dart';
import '../../services/review_service.dart';
import '../../services/subscription_service.dart';
import '../../services/wod_service.dart';
import '../checkin/qr_scanner_screen.dart';
import '../../widgets/user_avatar.dart';
import 'log_score_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

class ClassDetailsScreen extends StatefulWidget {
  const ClassDetailsScreen({super.key, required this.gymClass, this.gymId = ''});

  final GymClass gymClass;
  final String gymId;

  @override
  State<ClassDetailsScreen> createState() => _ClassDetailsScreenState();
}

class _ClassDetailsScreenState extends State<ClassDetailsScreen> {
  late final _bookingService = BookingService(
      gymId: widget.gymId.isNotEmpty ? widget.gymId : widget.gymClass.gymId);
  late final _classService = ClassService(
      gymId: widget.gymId.isNotEmpty ? widget.gymId : widget.gymClass.gymId);
  late final _reviewService = ReviewService(
      gymId: widget.gymId.isNotEmpty ? widget.gymId : widget.gymClass.gymId);
  late final _friendService = FriendService(
      gymId: widget.gymId.isNotEmpty ? widget.gymId : widget.gymClass.gymId);
  bool _isWorking = false;
  int _minAdvanceMinutes = 0;

  // Cached streams — created once so StreamBuilder never sees a new stream
  // object on rebuild, which would cancel and recreate Firestore listeners and
  // trigger a race condition in the Firestore Web SDK.
  late final Stream<GymClass?> _classStream;
  late final Stream<Set<String>> _bookedClassIdsStream;
  late final Stream<Set<String>> _waitlistedClassIdsStream;
  late final Stream<Set<String>> _checkedInUserIdsStream;
  late final Stream<double> _avgRatingStream;
  late final Stream<Set<String>> _friendIdsStream;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _classStream = _classService.streamClass(widget.gymClass.id);
    _bookedClassIdsStream = _bookingService.streamBookedClassIds(userId);
    _waitlistedClassIdsStream =
        _bookingService.streamWaitlistedClassIds(userId);
    _checkedInUserIdsStream =
        _bookingService.streamCheckedInUserIds(widget.gymClass.id);
    _avgRatingStream = _reviewService.streamAverageRating(widget.gymClass.id);
    _friendIdsStream = userId.isNotEmpty
        ? _friendService.streamFriendIds(userId)
        : Stream.value({});
    _bookingService.getMinAdvanceBookingMinutes().then((v) {
      if (mounted) setState(() => _minAdvanceMinutes = v);
    });
  }

  // ── Action helpers ──────────────────────────────────────────────────────────

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.replaceFirst('Exception: ', '');
    }
    return raw;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 18,
          ),
          SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor:
            error ? Colors.red.shade700 : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _book(String classId) async {
    setState(() => _isWorking = true);
    try {
      final result = await _bookingService.bookClass(
        userId: FirebaseAuth.instance.currentUser!.uid,
        classId: classId,
      );
      if (!mounted) return;
      _snack(
        result == BookingResult.booked
            ? context.l10n.tr('Class booked successfully!')
            : context.l10n.tr('Class is full. You were added to the waitlist.'),
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'bookClass');
      _snack(_friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _bookDropIn(String classId, double price) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Drop-in Booking')),
        content: Text(
          '${context.l10n.tr("You'll be booked as a drop-in for")} ${widget.gymClass.title}. '
          '${context.l10n.tr('The drop-in fee is')} ${Currency.format(price, null)}. '
          '${context.l10n.tr('Payment is collected at the front desk.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isWorking = true);
    try {
      await _bookingService.bookClass(
        userId: FirebaseAuth.instance.currentUser!.uid,
        classId: classId,
        isDropIn: true,
      );
      if (!mounted) return;
      _snack(
        '${context.l10n.tr('Booked as drop-in! Please pay')} ${Currency.format(price, null)} ${context.l10n.tr('at the front desk.')}',
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'bookDropIn');
      _snack(_friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _cancel(String classId) async {
    // Confirm before cancelling
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Cancel Booking')),
        content: Text(
            context.l10n.tr('Are you sure you want to cancel this booking?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.tr('No'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              child: Text(context.l10n.tr('Yes, Cancel'))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isWorking = true);
    final messenger = ScaffoldMessenger.of(context);
    final cancelledMsg = context.l10n.tr('Booking cancelled.');
    try {
      await _bookingService.cancelBooking(
        userId: FirebaseAuth.instance.currentUser!.uid,
        classId: classId,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(cancelledMsg)));
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'cancelClassBooking');
      _snack(_friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _leaveWaitlist(String classId) async {
    setState(() => _isWorking = true);
    final removedMsg = context.l10n.tr('Removed from waitlist.');
    try {
      await _bookingService.leaveWaitlist(
        userId: FirebaseAuth.instance.currentUser!.uid,
        classId: classId,
      );
      if (!mounted) return;
      _snack(removedMsg);
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'leaveWaitlist');
      _snack(_friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<GymClass?>(
      stream: _classStream,
      builder: (context, classSnap) {
        final gymClass = classSnap.data ?? widget.gymClass;

        return StreamBuilder<Set<String>>(
          stream: _bookedClassIdsStream,
          builder: (context, bookedSnap) {
            final isBooked = bookedSnap.data?.contains(gymClass.id) ?? false;

            return StreamBuilder<Set<String>>(
              stream: _waitlistedClassIdsStream,
              builder: (context, wlSnap) {
                final isWaitlisted =
                    wlSnap.data?.contains(gymClass.id) ?? false;

                return StreamBuilder<Set<String>>(
                  stream: _checkedInUserIdsStream,
                  builder: (context, ciSnap) {
                    final isCheckedIn = ciSnap.data?.contains(userId) ?? false;

                    return StreamBuilder<double>(
                      stream: _avgRatingStream,
                      builder: (context, ratingSnap) {
                        final avgRating = ratingSnap.data ?? 0.0;

                        return StreamBuilder<Set<String>>(
                          stream: _friendIdsStream,
                          builder: (context, friendSnap) {
                            final friendIds = friendSnap.data ?? {};

                            return _DetailScaffold(
                              gymClass: gymClass,
                              gymId: widget.gymId,
                              isBooked: isBooked,
                              isWaitlisted: isWaitlisted,
                              isCheckedIn: isCheckedIn,
                              isWorking: _isWorking,
                              minAdvanceMinutes: _minAdvanceMinutes,
                              avgRating: avgRating,
                              friendIds: friendIds,
                              onBook: () => _book(gymClass.id),
                              onCancel: () => _cancel(gymClass.id),
                              onLeaveWaitlist: () => _leaveWaitlist(gymClass.id),
                              onBookDropIn: () =>
                                  _bookDropIn(gymClass.id, gymClass.dropInPrice),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scaffold
// ─────────────────────────────────────────────────────────────────────────────

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.gymClass,
    required this.gymId,
    required this.isBooked,
    required this.isWaitlisted,
    required this.isCheckedIn,
    required this.isWorking,
    required this.onBook,
    required this.onCancel,
    required this.onLeaveWaitlist,
    required this.onBookDropIn,
    this.minAdvanceMinutes = 0,
    this.avgRating = 0.0,
    this.friendIds = const {},
  });

  final GymClass gymClass;
  final String gymId;
  final bool isBooked;
  final bool isWaitlisted;
  final bool isCheckedIn;
  final bool isWorking;
  final VoidCallback onBook;
  final VoidCallback onCancel;
  final VoidCallback onLeaveWaitlist;
  final VoidCallback onBookDropIn;
  final int minAdvanceMinutes;
  final double avgRating;
  final Set<String> friendIds;

  Color get _accentColor {
    if (gymClass.classColorValue != null) {
      return Color(gymClass.classColorValue!);
    }
    return Color(0xFF0F766E); // brand teal
  }

  bool get _useDarkText => _accentColor.computeLuminance() > 0.45;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final localeCode = Localizations.localeOf(context).languageCode;
    final durationMin =
        gymClass.endTime.difference(gymClass.startTime).inMinutes;
    final spotsLeft = gymClass.capacity - gymClass.bookedCount;
    final occupancy = gymClass.capacity <= 0
        ? 0.0
        : (gymClass.bookedCount / gymClass.capacity).clamp(0.0, 1.0);
    final onAccent = _useDarkText ? Colors.black87 : Colors.white;
    final mutedAccent = _useDarkText
        ? Colors.black.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.75);

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── Hero app bar ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: _accentColor,
            iconTheme: IconThemeData(color: onAccent),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _HeroHeader(
                gymClass: gymClass,
                accentColor: _accentColor,
                onAccent: onAccent,
                mutedAccent: mutedAccent,
                localeCode: localeCode,
                durationMin: durationMin,
                isBooked: isBooked,
                isWaitlisted: isWaitlisted,
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Builder(builder: (context) {
              final screenW = MediaQuery.sizeOf(context).width;
              final isTwoCol = screenW >= 1050;

              // ── shared widgets ──────────────────────────────────────────
              Widget actionArea = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Average rating row ──────────────────────────────────
                  if (avgRating > 0)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _AverageRatingRow(avgRating: avgRating),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: _ActionButton(
                      gymClass: gymClass,
                      isBooked: isBooked,
                      isWaitlisted: isWaitlisted,
                      isWorking: isWorking,
                      minAdvanceMinutes: minAdvanceMinutes,
                      onBook: onBook,
                      onCancel: onCancel,
                      onLeaveWaitlist: onLeaveWaitlist,
                    ),
                  ),
                  if (isBooked) ...[
                    SizedBox(height: 10),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: isCheckedIn
                          ? _CheckedInBanner()
                          : _CheckInButtonOrTimer(gymClass: gymClass),
                    ),
                  ],
                  if (gymClass.dropInEnabled &&
                      !isBooked &&
                      !gymClass.isFull) ...[
                    SizedBox(height: 10),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _DropInBookButton(
                        gymClass: gymClass,
                        isWorking: isWorking,
                        onBookDropIn: onBookDropIn,
                      ),
                    ),
                  ],
                  // ── Friends attending ───────────────────────────────────
                  if (friendIds.isNotEmpty) ...[
                    SizedBox(height: 12),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _FriendsAttendingRow(
                        classId: gymClass.id,
                        gymId: gymId.isNotEmpty ? gymId : gymClass.gymId,
                        friendIds: friendIds,
                      ),
                    ),
                  ],
                  SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _QuickInfoRow(
                      gymClass: gymClass,
                      localeCode: localeCode,
                      durationMin: durationMin,
                      spotsLeft: spotsLeft,
                    ),
                  ),
                  SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _OfferEligibilityCard(
                      gymClass: gymClass,
                      localeCode: localeCode,
                    ),
                  ),
                  if (gymClass.description.isNotEmpty) ...[
                    SizedBox(height: 20),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _SectionLabel(label: context.l10n.tr('About this class')),
                    ),
                    SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child:
                          _DescriptionCard(description: gymClass.description),
                    ),
                  ],
                ],
              );

              Widget rightCol = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // WOD — always shown
                  _WodSection(
                    classDate: gymClass.startTime,
                    gymId: gymId.isNotEmpty ? gymId : gymClass.gymId,
                  ),
                  SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _CapacityCard(
                      gymClass: gymClass,
                      spotsLeft: spotsLeft,
                      occupancy: occupancy,
                    ),
                  ),
                  SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _SectionLabel(
                      label:
                          '${context.l10n.tr('Booked')} (${gymClass.bookedCount}/${gymClass.capacity})',
                    ),
                  ),
                  SizedBox(height: 8),
                  _BookedMembersList(
                    classId: gymClass.id,
                    gymId: gymId.isNotEmpty ? gymId : gymClass.gymId,
                  ),
                  if (gymClass.waitlistCount > 0) ...[
                    SizedBox(height: 20),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _WaitlistSection(
                        gymClass: gymClass,
                        gymId: gymId.isNotEmpty ? gymId : gymClass.gymId,
                      ),
                    ),
                  ],
                  SizedBox(height: 32),
                ],
              );

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isTwoCol ? 1100 : 760),
                  child: isTwoCol
                      ? Padding(
                          padding: EdgeInsets.only(top: 20, bottom: 32),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: actionArea),
                              SizedBox(width: 16),
                              Expanded(flex: 5, child: rightCol),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            actionArea,
                            rightCol,
                          ],
                        ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero header (expanded app bar background)
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.gymClass,
    required this.accentColor,
    required this.onAccent,
    required this.mutedAccent,
    required this.localeCode,
    required this.durationMin,
    required this.isBooked,
    required this.isWaitlisted,
  });

  final GymClass gymClass;
  final Color accentColor;
  final Color onAccent;
  final Color mutedAccent;
  final String localeCode;
  final int durationMin;
  final bool isBooked;
  final bool isWaitlisted;

  @override
  Widget build(BuildContext context) {
    final startText =
        DateFormat('EEE, d MMM • HH:mm', localeCode).format(gymClass.startTime);
    final endText = DateFormat('HH:mm', localeCode).format(gymClass.endTime);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor,
            accentColor.withValues(alpha: 0.82),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -40,
            top: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onAccent.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: 20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onAccent.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 56, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Status badges row
                  Row(
                    children: [
                      if (isBooked)
                        _HeroBadge(
                          icon: Icons.check_circle_outline,
                          label: context.l10n.tr('Booked'),
                          bg: Colors.green.shade600,
                        )
                      else if (isWaitlisted)
                        _HeroBadge(
                          icon: Icons.hourglass_top_outlined,
                          label: context.l10n.tr('Waitlisted'),
                          bg: Colors.orange.shade600,
                        )
                      else if (gymClass.isFull)
                        _HeroBadge(
                          icon: Icons.block_outlined,
                          label: context.l10n.tr('Full'),
                          bg: Colors.red.shade600,
                        )
                      else
                        _HeroBadge(
                          icon: Icons.fitness_center_outlined,
                          label: context.l10n.tr('Open'),
                          bg: Colors.green.shade600.withValues(alpha: 0.85),
                        ),
                      if (gymClass.requiredOfferPlanId.isNotEmpty) ...[
                        SizedBox(width: 8),
                        _HeroBadge(
                          icon: Icons.workspace_premium_outlined,
                          label: context.l10n.tr('Offer required'),
                          bg: onAccent.withValues(alpha: 0.18),
                          textColor: onAccent,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 10),
                  // Title
                  Text(
                    gymClass.title,
                    style: TextStyle(
                      color: onAccent,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6),
                  // Coach row
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 15, color: mutedAccent),
                      SizedBox(width: 5),
                      Text(
                        gymClass.coachName,
                        style: TextStyle(
                            color: mutedAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  // Time chips
                  Wrap(
                    spacing: 8,
                    children: [
                      _HeroChip(
                        icon: Icons.access_time,
                        label: '$startText → $endText',
                        onAccent: onAccent,
                      ),
                      _HeroChip(
                        icon: Icons.timer_outlined,
                        label: '$durationMin ${context.l10n.tr('min')}',
                        onAccent: onAccent,
                      ),
                    ],
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

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({
    required this.icon,
    required this.label,
    required this.bg,
    this.textColor = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                color: textColor, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label, required this.onAccent});

  final IconData icon;
  final String label;
  final Color onAccent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: onAccent),
          SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: onAccent, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action button
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.gymClass,
    required this.isBooked,
    required this.isWaitlisted,
    required this.isWorking,
    required this.onBook,
    required this.onCancel,
    required this.onLeaveWaitlist,
    this.minAdvanceMinutes = 0,
  });

  final GymClass gymClass;
  final bool isBooked;
  final bool isWaitlisted;
  final bool isWorking;
  final VoidCallback onBook;
  final VoidCallback onCancel;
  final VoidCallback onLeaveWaitlist;
  final int minAdvanceMinutes;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final now = DateTime.now();

    String label;
    IconData icon;
    Color bg;
    Color fg;
    VoidCallback? action;

    if (isBooked) {
      label = l10n.tr('Cancel Booking');
      icon = Icons.cancel_outlined;
      bg = Colors.red.shade600;
      fg = Colors.white;
      action = onCancel;
    } else if (isWaitlisted) {
      label = l10n.tr('Leave Waitlist');
      icon = Icons.remove_circle_outline;
      bg = Colors.orange.shade600;
      fg = Colors.white;
      action = onLeaveWaitlist;
    } else if (gymClass.isFull) {
      label = l10n.tr('Join Waitlist');
      icon = Icons.queue_outlined;
      bg = Colors.orange.shade600;
      fg = Colors.white;
      action = onBook;
    } else {
      label = l10n.tr('Book This Class');
      icon = Icons.add_circle_outline;
      bg = Color(0xFF0F766E);
      fg = Colors.white;
      action = onBook;
    }

    // Booking window check: block if too far in advance
    if (!isBooked && !isWaitlisted) {
      final minAdv = minAdvanceMinutes;
      if (minAdv > 0) {
        final minutesUntilClass = gymClass.startTime.difference(now).inMinutes;
        if (minutesUntilClass > minAdv) {
          final opensAt =
              gymClass.startTime.subtract(Duration(minutes: minAdv));
          final hm =
              '${opensAt.hour.toString().padLeft(2, '0')}:${opensAt.minute.toString().padLeft(2, '0')}';
          label = '${context.l10n.tr('Opens at')} $hm';
          icon = Icons.schedule;
          bg = Colors.grey.shade300;
          fg = Colors.grey.shade700;
          action = null;
        }
      }
    }

    return SizedBox(
      width: double.infinity,
      height: isWide ? 60 : 52,
      child: FilledButton.icon(
        onPressed: isWorking ? null : action,
        icon: isWorking
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, size: 20),
        label: Text(label,
            style: TextStyle(
                fontSize: isWide ? 17 : 15, fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick info row
// ─────────────────────────────────────────────────────────────────────────────

class _QuickInfoRow extends StatelessWidget {
  const _QuickInfoRow({
    required this.gymClass,
    required this.localeCode,
    required this.durationMin,
    required this.spotsLeft,
  });

  final GymClass gymClass;
  final String localeCode;
  final int durationMin;
  final int spotsLeft;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateLabel =
        DateFormat('EEE, d MMM yyyy', localeCode).format(gymClass.startTime);

    return Row(
      children: [
        Expanded(
          child: _InfoChip(
            icon: Icons.calendar_today_outlined,
            title: context.l10n.tr('Date'),
            value: dateLabel,
            cs: cs,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _InfoChip(
            icon: Icons.timer_outlined,
            title: context.l10n.tr('Duration'),
            value: '$durationMin ${context.l10n.tr('min')}',
            cs: cs,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _InfoChip(
            icon: gymClass.isFull
                ? Icons.block_outlined
                : Icons.event_seat_outlined,
            title: context.l10n.tr('Spots'),
            value: gymClass.isFull
                ? context.l10n.tr('Full')
                : '$spotsLeft ${context.l10n.tr('left')}',
            iconColor: gymClass.isFull
                ? Colors.red.shade600
                : spotsLeft <= 3
                    ? Colors.orange.shade600
                    : cs.primary,
            cs: cs,
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.title,
    required this.value,
    required this.cs,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final ColorScheme cs;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor ?? cs.primary),
          SizedBox(height: 6),
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: 2),
          Text(value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Description card
// ─────────────────────────────────────────────────────────────────────────────

class _DescriptionCard extends StatefulWidget {
  const _DescriptionCard({required this.description});

  final String description;

  @override
  State<_DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<_DescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const maxLines = 3;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCrossFade(
            duration: Duration(milliseconds: 220),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Text(
              widget.description,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14, height: 1.55, color: cs.onSurfaceVariant),
            ),
            secondChild: Text(
              widget.description,
              style: TextStyle(
                  fontSize: 14, height: 1.55, color: cs.onSurfaceVariant),
            ),
          ),
          if (widget.description.length > 120) ...[
            SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? context.l10n.tr('Show less') : context.l10n.tr('Read more'),
                style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Capacity card
// ─────────────────────────────────────────────────────────────────────────────

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({
    required this.gymClass,
    required this.spotsLeft,
    required this.occupancy,
  });

  final GymClass gymClass;
  final int spotsLeft;
  final double occupancy;

  Color _barColor() {
    if (occupancy >= 1.0) return Colors.red.shade500;
    if (occupancy >= 0.75) return Colors.orange.shade500;
    return Color(0xFF0F766E);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_outline, size: 18, color: cs.primary),
              SizedBox(width: 8),
              Text(context.l10n.tr('Capacity'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Spacer(),
              Text(
                '${gymClass.bookedCount}/${gymClass.capacity}',
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ],
          ),
          SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: occupancy,
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(_barColor()),
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              _CapacityStat(
                icon: Icons.check_circle_outline,
                label: context.l10n.tr('Booked'),
                value: '${gymClass.bookedCount}',
                color: Color(0xFF0F766E),
              ),
              SizedBox(width: 20),
              _CapacityStat(
                icon: Icons.event_seat_outlined,
                label: context.l10n.tr('Available'),
                value: spotsLeft <= 0 ? '0' : '$spotsLeft',
                color: spotsLeft <= 0
                    ? Colors.red.shade500
                    : spotsLeft <= 3
                        ? Colors.orange.shade600
                        : cs.onSurface,
              ),
              if (gymClass.waitlistCount > 0) ...[
                SizedBox(width: 20),
                _CapacityStat(
                  icon: Icons.hourglass_top_outlined,
                  label: context.l10n.tr('Waitlist'),
                  value: '${gymClass.waitlistCount}',
                  color: Colors.orange.shade600,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        SizedBox(width: 5),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14, color: color)),
        SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offer eligibility
// ─────────────────────────────────────────────────────────────────────────────

class _OfferEligibilityCard extends StatelessWidget {
  const _OfferEligibilityCard({
    required this.gymClass,
    required this.localeCode,
  });

  final GymClass gymClass;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final currentUserId = authService.currentUser?.uid;
    if (currentUserId == null) return SizedBox.shrink();

    if (gymClass.requiredOfferPlanId.isEmpty) {
      return _EligibilityBanner(
        icon: Icons.check_circle_outline,
        title: context.l10n.tr('Open to all members'),
        subtitle: context.l10n.tr('No offer required for this class.'),
        iconColor: Colors.green.shade600,
        bgColor: Colors.green.shade50,
        borderColor: Colors.green.shade200,
      );
    }

    return _OfferEligibilityContent(
      gymClass: gymClass,
      currentUserId: currentUserId,
      localeCode: localeCode,
      gymId: gymClass.gymId,
    );
  }
}

class _EligibilityBanner extends StatelessWidget {
  const _EligibilityBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: iconColor)),
                SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: iconColor.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferEligibilityContent extends StatefulWidget {
  const _OfferEligibilityContent({
    required this.gymClass,
    required this.currentUserId,
    required this.localeCode,
    this.gymId = '',
  });

  final GymClass gymClass;
  final String currentUserId;
  final String localeCode;
  final String gymId;

  @override
  State<_OfferEligibilityContent> createState() =>
      _OfferEligibilityContentState();
}

class _OfferEligibilityContentState extends State<_OfferEligibilityContent> {
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM yyyy', widget.localeCode);
    final l10n = context.l10n;

    return FutureBuilder<MembershipPlan?>(
      future:
          _subscriptionService.getPlanById(widget.gymClass.requiredOfferPlanId),
      builder: (context, planSnapshot) {
        final planName = planSnapshot.data?.name ?? l10n.tr('Unknown Offer');

        return StreamBuilder<List<UserSubscription>>(
          stream: _subscriptionService
              .streamUserSubscriptions(widget.currentUserId),
          builder: (context, subscriptionsSnapshot) {
            final subscriptions = subscriptionsSnapshot.data ?? [];
            final matchingSub = subscriptions.firstWhere(
              (sub) => sub.planId == widget.gymClass.requiredOfferPlanId,
              orElse: () => UserSubscription.empty(),
            );

            if (matchingSub.planId.isEmpty) {
              return _EligibilityBanner(
                icon: Icons.cancel_outlined,
                title: l10n.tr('Offer required'),
                subtitle: '${l10n.tr('This class requires')} $planName',
                iconColor: Colors.red.shade600,
                bgColor: Colors.red.shade50,
                borderColor: Colors.red.shade200,
              );
            }

            final expired = matchingSub.endDate != null &&
                matchingSub.endDate!.isBefore(widget.gymClass.startTime);

            if (expired) {
              return _EligibilityBanner(
                icon: Icons.warning_amber_outlined,
                title: l10n.tr('Offer expired'),
                subtitle:
                    '${l10n.tr('Expired on')} ${dateFormat.format(matchingSub.endDate!)}',
                iconColor: Colors.orange.shade700,
                bgColor: Colors.orange.shade50,
                borderColor: Colors.orange.shade200,
              );
            }

            final expiry = dateFormat
                .format(matchingSub.endDate ?? widget.gymClass.startTime);
            return _EligibilityBanner(
              icon: Icons.workspace_premium_outlined,
              title: l10n.tr('Eligible with $planName'),
              subtitle: '${l10n.tr('Valid until')} $expiry',
              iconColor: Colors.green.shade600,
              bgColor: Colors.green.shade50,
              borderColor: Colors.green.shade200,
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Booked members list
// ─────────────────────────────────────────────────────────────────────────────

class _BookedMembersList extends StatefulWidget {
  const _BookedMembersList({required this.classId, this.gymId = ''});

  final String classId;
  final String gymId;

  @override
  State<_BookedMembersList> createState() => _BookedMembersListState();
}

class _BookedMembersListState extends State<_BookedMembersList> {
  late final _bookingService = BookingService(gymId: widget.gymId);
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<Booking>>(
      stream: _bookingService.streamBookingsForClass(widget.classId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final bookings = snap.data ?? <Booking>[];
        if (bookings.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.people_outline, size: 20, color: cs.outlineVariant),
                SizedBox(width: 8),
                Text(
                  context.l10n.tr('No bookings yet. Be the first!'),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        const avatarPreview = 6;
        final displayList =
            _showAll ? bookings : bookings.take(avatarPreview).toList();

        return Column(
          children: [
            // Avatar chips preview
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: displayList
                          .map((b) => _MemberAvatar(booking: b))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            if (bookings.length > avatarPreview) ...[
              SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => setState(() => _showAll = !_showAll),
                  child: Row(
                    children: [
                      Icon(
                        _showAll ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: cs.primary,
                      ),
                      SizedBox(width: 4),
                      Text(
                        _showAll
                            ? context.l10n.tr('Show less')
                            : '${context.l10n.tr('Show all')} ${bookings.length} ${context.l10n.tr('members')}',
                        style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MemberAvatar extends StatefulWidget {
  const _MemberAvatar({required this.booking});

  final Booking booking;

  @override
  State<_MemberAvatar> createState() => _MemberAvatarState();
}

class _MemberAvatarState extends State<_MemberAvatar> {
  late final _memberService = MemberService(gymId: widget.booking.gymId);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = widget.booking.memberName.trim().isNotEmpty
        ? widget.booking.memberName
        : '?';
    final initial = name[0].toUpperCase();

    if (widget.booking.memberName.isNotEmpty) {
      return Tooltip(
        message: widget.booking.memberName,
        child: CircleAvatar(
          radius: 20,
          backgroundColor: cs.primaryContainer,
          child: Text(initial,
              style: TextStyle(
                  color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
        ),
      );
    }

    // Need to load user
    return StreamBuilder<AppUser?>(
      stream: _memberService.streamUser(widget.booking.userId),
      builder: (context, snap) {
        final displayName = snap.data?.displayName ?? '';
        final initLetter =
            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
        return Tooltip(
          message: displayName.isNotEmpty ? displayName : widget.booking.userId,
          child: UserAvatar(
            radius: 20,
            photoUrl: snap.data?.photoUrl ?? '',
            initials: initLetter,
            color: cs.primary,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waitlist section
// ─────────────────────────────────────────────────────────────────────────────

class _WaitlistSection extends StatefulWidget {
  const _WaitlistSection({required this.gymClass, this.gymId = ''});

  final GymClass gymClass;
  final String gymId;

  @override
  State<_WaitlistSection> createState() => _WaitlistSectionState();
}

class _WaitlistSectionState extends State<_WaitlistSection> {
  late final _bookingService = BookingService(gymId: widget.gymId);

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<WaitlistEntry>>(
      stream: _bookingService.streamWaitlistForClass(widget.gymClass.id),
      builder: (context, snap) {
        final entries = snap.data ?? <WaitlistEntry>[];
        if (entries.isEmpty) return SizedBox.shrink();

        final myIndex = entries.indexWhere((e) => e.userId == currentUserId);
        final myPosition = myIndex == -1 ? null : myIndex + 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.hourglass_top_outlined,
                    size: 18, color: Colors.orange.shade600),
                SizedBox(width: 8),
                Text(context.l10n.tr('Waitlist'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade600,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${entries.length}',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
              ],
            ),

            // My position banner
            if (myPosition != null) ...[
              SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300, width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Center(
                        child: Text('#$myPosition',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "${context.l10n.tr('You\'re')} #$myPosition ${context.l10n.tr('in the queue.')}\n${context.l10n.tr('You\'ll be auto-promoted if a spot opens.')}",
                        style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 12),

            // Ranked list
            ...entries.asMap().entries.map((entry) {
              final pos = entry.key + 1;
              final we = entry.value;
              final isMe = we.userId == currentUserId;
              final localeCode = Localizations.localeOf(context).languageCode;
              final name = we.memberName.isNotEmpty ? we.memberName : we.userId;

              return Container(
                margin: EdgeInsets.only(bottom: 8),
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? Colors.orange.shade50 : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isMe
                          ? Colors.orange.shade300
                          : cs.outline.withValues(alpha: 0.18),
                      width: isMe ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          isMe ? Colors.orange.shade600 : cs.primaryContainer,
                      child: Text(
                        '$pos',
                        style: TextStyle(
                            color: isMe ? Colors.white : cs.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: TextStyle(
                                  fontWeight:
                                      isMe ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 14)),
                          Text(
                            '${context.l10n.tr('Joined')}: ${DateFormat('d MMM yyyy • HH:mm', localeCode).format(we.createdAt)}',
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (isMe)
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade600,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(context.l10n.tr('You'),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scan to Check In button
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Check-in button or countdown timer
// ─────────────────────────────────────────────────────────────────────────────

class _CheckInButtonOrTimer extends StatefulWidget {
  const _CheckInButtonOrTimer({required this.gymClass});
  final GymClass gymClass;

  @override
  State<_CheckInButtonOrTimer> createState() => _CheckInButtonOrTimerState();
}

class _CheckInButtonOrTimerState extends State<_CheckInButtonOrTimer> {
  late final _ticker = Stream.periodic(Duration(seconds: 30)).listen((_) {
    if (mounted) setState(() {});
  });

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final windowOpen = widget.gymClass.startTime.subtract(Duration(hours: 1));
    final windowClose = widget.gymClass.endTime;
    final isOpen = now.isAfter(windowOpen) && now.isBefore(windowClose);
    final isEnded = now.isAfter(windowClose);

    if (isEnded) return SizedBox.shrink();

    if (isOpen) {
      return _ScanCheckinButton(gymClass: widget.gymClass);
    }

    // Not open yet — show countdown
    final minsUntil = windowOpen.difference(now).inMinutes + 1;
    final opensAt = DateFormat('HH:mm').format(windowOpen);
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.schedule_rounded, color: cs.primary, size: 20),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${context.l10n.tr('Check-in opens at')} $opensAt',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  '${context.l10n.tr('In')} ${minsUntil >= 60 ? '${minsUntil ~/ 60}h ${minsUntil % 60}min' : '${minsUntil}min'}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanCheckinButton extends StatelessWidget {
  const _ScanCheckinButton({required this.gymClass});
  final GymClass gymClass;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0891B2)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0F766E).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => QrScannerScreen(gymClass: gymClass)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.tr('Scan to Check In'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      context.l10n.tr('Scan the QR code at the front desk'),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Spacer(),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white60,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Already checked-in banner
// ─────────────────────────────────────────────────────────────────────────────

class _CheckedInBanner extends StatelessWidget {
  const _CheckedInBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade500],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade700.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr("You're Checked In!"),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  context.l10n.tr('Attendance recorded — enjoy your workout! 💪'),
                  style: TextStyle(color: Colors.white70, fontSize: 12),
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
// Drop-in booking button
// ─────────────────────────────────────────────────────────────────────────────

class _DropInBookButton extends StatelessWidget {
  const _DropInBookButton({
    required this.gymClass,
    required this.isWorking,
    required this.onBookDropIn,
  });

  final GymClass gymClass;
  final bool isWorking;
  final VoidCallback onBookDropIn;

  @override
  Widget build(BuildContext context) {
    final price = gymClass.dropInPrice;
    final priceLabel = Currency.format(price, null);

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isWorking ? null : onBookDropIn,
        icon: Icon(Icons.directions_walk_outlined, size: 18),
        label: Text('${context.l10n.tr('Book as Drop-In')} • $priceLabel'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Color(0xFFEA580C),
          side: BorderSide(color: Color(0xFFEA580C), width: 1.5),
          padding: EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WOD section — shown when the class type is "WOD"
// ─────────────────────────────────────────────────────────────────────────────

class _WodSection extends StatefulWidget {
  const _WodSection({required this.classDate, this.gymId = ''});
  final DateTime classDate;
  final String gymId;

  @override
  State<_WodSection> createState() => _WodSectionState();
}

class _WodSectionState extends State<_WodSection> {
  late final _svc = WodService(gymId: widget.gymId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WodEntry>>(
      stream: _svc.streamForDate(widget.classDate),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final wods = snap.data ?? [];
        if (wods.isEmpty) return _WodEmptyCard(date: widget.classDate);
        return _WodDetailCard(wod: wods.first, service: _svc);
      },
    );
  }
}

// ── WOD not yet added placeholder ─────────────────────────────────────────────

class _WodEmptyCard extends StatelessWidget {
  const _WodEmptyCard({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.fitness_center_outlined,
                      color: cs.onSurfaceVariant, size: 22),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isToday
                            ? context.l10n.tr("Today's WOD")
                            : context.l10n.tr('Workout of the Day'),
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '${context.l10n.tr('No WOD for')} ${DateFormat('EEE, d MMM').format(date)} ${context.l10n.tr('yet.')}',
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            height: 1.4),
                      ),
                    ],
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

// ── WOD detail card ───────────────────────────────────────────────────────────

class _WodDetailCard extends StatelessWidget {
  const _WodDetailCard({required this.wod, required this.service});
  final WodEntry wod;
  final WodService service;

  static const _kOrange = Color(0xFFF97316);
  static const _kTeal = Color(0xFF0F766E);

  Color _formatColor(String fmt) {
    switch (fmt.toLowerCase()) {
      case 'amrap':
        return Colors.purple.shade600;
      case 'for time':
        return Colors.red.shade600;
      case 'emom':
        return Colors.blue.shade600;
      case 'tabata':
        return Colors.pink.shade600;
      case 'rounds':
        return _kTeal;
      case 'max reps':
        return _kOrange;
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isToday = DateUtils.isSameDay(wod.date, DateTime.now());
    final fmtColor = wod.format.isNotEmpty ? _formatColor(wod.format) : _kTeal;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section title ─────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: 8),
              Text(
                isToday
                    ? context.l10n.tr("Today's WOD")
                    : '${context.l10n.tr('Workout')} — ${DateFormat('d MMM').format(wod.date)}',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2),
              ),
              Spacer(),
              if (wod.format.isNotEmpty)
                _WodPill(
                  label: wod.format.toUpperCase(),
                  color: fmtColor,
                ),
              if (wod.timeCap.isNotEmpty) ...[
                SizedBox(width: 6),
                _WodPill(
                  label: '⏱ ${wod.timeCap}',
                  color: Colors.grey.shade600,
                  subtle: true,
                ),
              ],
            ],
          ),
          SizedBox(height: 10),

          // ── Main WOD card ─────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  fmtColor.withValues(alpha: 0.09),
                  fmtColor.withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: fmtColor.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: fmtColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child:
                            Icon(Icons.bolt_rounded, color: fmtColor, size: 20),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              wod.title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                height: 1.2,
                              ),
                            ),
                            if (wod.description.isNotEmpty) ...[
                              SizedBox(height: 6),
                              Text(
                                wod.description,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Exercises
                if (wod.exercises.isNotEmpty) ...[
                  Divider(
                      height: 1,
                      color: fmtColor.withValues(alpha: 0.15),
                      indent: 16,
                      endIndent: 16),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Icon(Icons.format_list_numbered_rounded,
                            size: 14, color: fmtColor),
                        SizedBox(width: 6),
                        Text(
                          '${context.l10n.tr('EXERCISES')} (${wod.exercises.length})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: fmtColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      children: wod.exercises
                          .asMap()
                          .entries
                          .map((e) => _WodExerciseTile(
                              index: e.key + 1,
                              exercise: e.value,
                              accentColor: fmtColor))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Score card ────────────────────────────────────────────
          SizedBox(height: 12),
          StreamBuilder<WodScore?>(
            stream: service.streamMyScore(wod.id, uid),
            builder: (ctx, snap) => _WodScoreLauncher(
              wod: wod,
              myScore: snap.data,
              gymId: service.gymId,
              accentColor: fmtColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _WodPill extends StatelessWidget {
  const _WodPill({required this.label, required this.color, this.subtle = false});
  final String label;
  final Color color;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: subtle
            ? Colors.grey.withValues(alpha: 0.1)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: subtle
            ? Border.all(color: Colors.grey.withValues(alpha: 0.3))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: subtle ? Colors.grey.shade600 : color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Exercise tile ─────────────────────────────────────────────────────────────

class _WodExerciseTile extends StatelessWidget {
  const _WodExerciseTile({
    required this.index,
    required this.exercise,
    required this.accentColor,
  });
  final int index;
  final WodExercise exercise;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                if (exercise.sets.isNotEmpty ||
                    exercise.reps.isNotEmpty ||
                    exercise.weight.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (exercise.sets.isNotEmpty && exercise.reps.isNotEmpty)
                        _ExerciseChip(
                          label: '${exercise.sets}×${exercise.reps}',
                          icon: Icons.repeat_rounded,
                          color: accentColor,
                        ),
                      if (exercise.weight.isNotEmpty)
                        _ExerciseChip(
                          label: exercise.weight,
                          icon: Icons.fitness_center_outlined,
                          color: Colors.grey.shade600,
                        ),
                    ],
                  ),
                ],
                if (exercise.notes.isNotEmpty) ...[
                  SizedBox(height: 3),
                  Text(
                    exercise.notes,
                    style: TextStyle(
                      fontSize: 11,
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

class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip({required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// ── Score launcher card (opens LogScoreScreen) ────────────────────────────────

class _WodScoreLauncher extends StatelessWidget {
  const _WodScoreLauncher({
    required this.wod,
    required this.myScore,
    required this.gymId,
    required this.accentColor,
  });
  final WodEntry wod;
  final WodScore? myScore;
  final String gymId;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasScore = myScore != null;

    if (hasScore) {
      return Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accentColor.withValues(alpha: 0.1),
              accentColor.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.emoji_events_rounded,
                  color: accentColor, size: 22),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.tr('Your Score'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: 2),
                  Text(
                    myScore!.score,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                        letterSpacing: -0.3),
                  ),
                  if (myScore!.scale.isNotEmpty)
                    Text(myScore!.scale.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: accentColor.withValues(alpha: 0.7))),
                  if (myScore!.notes.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(myScore!.notes,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LogScoreScreen(
                    wod: wod,
                    gymId: gymId,
                    existingScore: myScore,
                  ),
                ),
              ),
              icon: Icon(Icons.edit_outlined, size: 16),
              label: Text(context.l10n.tr('Edit')),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ],
        ),
      );
    }

    return FilledButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LogScoreScreen(
            wod: wod,
            gymId: gymId,
          ),
        ),
      ),
      icon: Icon(Icons.add_chart_outlined, size: 18),
      label: Text(context.l10n.tr('Log Your Score')),
      style: FilledButton.styleFrom(
        backgroundColor: accentColor,
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        minimumSize: Size(double.infinity, 50),
      ),
    );
  }
}

// ── Average rating row ────────────────────────────────────────────────────────

class _AverageRatingRow extends StatelessWidget {
  const _AverageRatingRow({required this.avgRating});

  final double avgRating;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rounded = (avgRating * 10).round() / 10;
    return Row(
      children: [
        ...List.generate(5, (i) {
          final filled = i < avgRating.floor();
          final half = !filled && i < avgRating;
          return Icon(
            filled
                ? Icons.star_rounded
                : half
                    ? Icons.star_half_rounded
                    : Icons.star_border_rounded,
            color: Colors.amber.shade600,
            size: 20,
          );
        }),
        SizedBox(width: 6),
        Text(
          '$rounded',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

// ── Friends attending ─────────────────────────────────────────────────────────

class _FriendsAttendingRow extends StatelessWidget {
  const _FriendsAttendingRow({
    required this.classId,
    required this.gymId,
    required this.friendIds,
  });

  final String classId;
  final String gymId;
  final Set<String> friendIds;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookingService = BookingService(gymId: gymId);

    return StreamBuilder<List<Booking>>(
      stream: bookingService.streamBookingsForClass(classId),
      builder: (context, snap) {
        final bookings = snap.data ?? [];
        final attendingFriendIds = bookings
            .map((b) => b.userId)
            .where((uid) => friendIds.contains(uid))
            .toSet();

        if (attendingFriendIds.isEmpty) return SizedBox.shrink();

        final memberService = MemberService(gymId: gymId);

        return Row(
          children: [
            Icon(Icons.group_outlined, size: 16, color: Color(0xFF0F766E)),
            SizedBox(width: 6),
            Text(
              '${context.l10n.tr('Friends joining')}:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F766E),
              ),
            ),
            SizedBox(width: 8),
            ...attendingFriendIds.take(4).map((uid) => Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: StreamBuilder<AppUser?>(
                    stream: memberService.streamUser(uid),
                    builder: (context, userSnap) {
                      final user = userSnap.data;
                      final initials = (user?.displayName.isNotEmpty == true
                              ? user!.displayName[0]
                              : '?')
                          .toUpperCase();
                      return Tooltip(
                        message: user?.displayName ?? '',
                        child: UserAvatar(
                          photoUrl: user?.photoUrl ?? '',
                          initials: initials,
                          color: Color(0xFF0F766E),
                          radius: 14,
                        ),
                      );
                    },
                  ),
                )),
            if (attendingFriendIds.length > 4)
              Text(
                '+${attendingFriendIds.length - 4}',
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600),
              ),
          ],
        );
      },
    );
  }
}
