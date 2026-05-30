import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/booking.dart';
import '../../models/gym_class.dart';
import '../../services/booking_service.dart';
import '../../services/member_service.dart';
import '../../widgets/user_avatar.dart';
import '../../l10n/app_localizations.dart';

/// Full-screen manual check-in panel for a specific class.
/// Accessible to both admins and coaches.
class ClassCheckInScreen extends StatefulWidget {
  const ClassCheckInScreen({super.key, required this.gymClass});

  final GymClass gymClass;

  @override
  State<ClassCheckInScreen> createState() => _ClassCheckInScreenState();
}

class _ClassCheckInScreenState extends State<ClassCheckInScreen> {
  late final _bookingService = BookingService(gymId: widget.gymClass.gymId);
  late final _memberService = MemberService(gymId: widget.gymClass.gymId);
  String _search = '';

  GymClass get _gc => widget.gymClass;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _gc.title,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              '${DateFormat('EEE, d MMM · HH:mm').format(_gc.startTime)}'
              ' – ${DateFormat('HH:mm').format(_gc.endTime)}',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
        ),
      ),
      body: StreamBuilder<List<Booking>>(
        stream: _bookingService.streamBookingsForClass(_gc.id),
        builder: (context, bookSnap) {
          if (bookSnap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final bookings = bookSnap.data ?? <Booking>[];

          return StreamBuilder<Set<String>>(
            stream: _bookingService.streamCheckedInUserIds(_gc.id),
            builder: (context, attSnap) {
              final checkedInIds = attSnap.data ?? <String>{};

              return Column(
                children: [
                  // ── Stats banner ──────────────────────────────────────
                  _CheckInStatsBanner(
                    checkedIn: checkedInIds.length,
                    booked: bookings.length,
                    capacity: _gc.capacity,
                  ),

                  // ── Search ────────────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        hintText: context.l10n.tr('Search member…'),
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _search = ''),
                              )
                            : null,
                      ),
                    ),
                  ),

                  // ── Not-checked-in / all toggle header ────────────────
                  if (bookings.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Row(
                        children: [
                          Text(
                            '${bookings.length} ${context.l10n.tr('booked')}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Spacer(),
                          Text(
                            '${checkedInIds.length} ${context.l10n.tr('checked in')}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(height: 6),

                  // ── Member list ───────────────────────────────────────
                  Expanded(
                    child: bookings.isEmpty
                        ? _EmptyState(
                            icon: Icons.people_outline,
                            message: context.l10n
                                .tr('No members have booked this class yet.'),
                          )
                        : _MemberCheckInList(
                            gymClass: _gc,
                            bookings: bookings,
                            checkedInIds: checkedInIds,
                            search: _search,
                            bookingService: _bookingService,
                            memberService: _memberService,
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

// ── Stats banner ───────────────────────────────────────────────────────────────

class _CheckInStatsBanner extends StatelessWidget {
  const _CheckInStatsBanner({
    required this.checkedIn,
    required this.booked,
    required this.capacity,
  });

  final int checkedIn;
  final int booked;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rate = booked > 0 ? checkedIn / booked : 0.0;
    final rateColor = rate >= 0.8
        ? Colors.green.shade700
        : rate >= 0.5
            ? Colors.orange.shade700
            : cs.error;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0F766E).withValues(alpha: 0.08),
            Color(0xFF0F766E).withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF0F766E).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _BannerStat(
                icon: Icons.how_to_reg_rounded,
                label: context.l10n.tr('Checked in'),
                value: '$checkedIn',
                color: Colors.green.shade600,
              ),
              SizedBox(width: 8),
              _BannerStat(
                icon: Icons.event_available_outlined,
                label: context.l10n.tr('Booked'),
                value: '$booked',
                color: cs.primary,
              ),
              SizedBox(width: 8),
              _BannerStat(
                icon: Icons.pending_outlined,
                label: context.l10n.tr('Remaining'),
                value: '${booked - checkedIn}',
                color: booked - checkedIn > 0
                    ? Colors.orange.shade700
                    : Colors.green.shade700,
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: rate.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Text(
                '${(rate * 100).round()}% ${context.l10n.tr('attendance')}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: rateColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BannerStat extends StatelessWidget {
  const _BannerStat({
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
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

// ── Member list ────────────────────────────────────────────────────────────────

class _MemberCheckInList extends StatelessWidget {
  const _MemberCheckInList({
    required this.gymClass,
    required this.bookings,
    required this.checkedInIds,
    required this.search,
    required this.bookingService,
    required this.memberService,
  });

  final GymClass gymClass;
  final List<Booking> bookings;
  final Set<String> checkedInIds;
  final String search;
  final BookingService bookingService;
  final MemberService memberService;

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Sort: not-checked-in first, then alphabetically by name
    final sorted = List<Booking>.from(bookings)
      ..sort((a, b) {
        final aIn = checkedInIds.contains(a.userId) ? 1 : 0;
        final bIn = checkedInIds.contains(b.userId) ? 1 : 0;
        if (aIn != bIn) return aIn.compareTo(bIn);
        return (a.memberName).compareTo(b.memberName);
      });

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final booking = sorted[i];
        return StreamBuilder<AppUser?>(
          stream: memberService.streamUser(booking.userId),
          builder: (context, userSnap) {
            final user = userSnap.data;
            final name = (user?.displayName.isNotEmpty == true)
                ? user!.displayName
                : user?.email ?? booking.memberName;

            if (search.isNotEmpty &&
                !name.toLowerCase().contains(search.toLowerCase())) {
              return SizedBox.shrink();
            }

            final isCheckedIn = checkedInIds.contains(booking.userId);

            return _MemberCheckInTile(
              user: user,
              name: name,
              isCheckedIn: isCheckedIn,
              onCheckIn: () => bookingService.checkInMember(
                classId: gymClass.id,
                userId: booking.userId,
                checkedInBy: currentUserId,
              ),
              onUndo: () => bookingService.undoCheckIn(
                classId: gymClass.id,
                userId: booking.userId,
              ),
            );
          },
        );
      },
    );
  }
}

// ── Member check-in tile ───────────────────────────────────────────────────────

class _MemberCheckInTile extends StatefulWidget {
  const _MemberCheckInTile({
    required this.user,
    required this.name,
    required this.isCheckedIn,
    required this.onCheckIn,
    required this.onUndo,
  });

  final AppUser? user;
  final String name;
  final bool isCheckedIn;
  final Future<void> Function() onCheckIn;
  final Future<void> Function() onUndo;

  @override
  State<_MemberCheckInTile> createState() => _MemberCheckInTileState();
}

class _MemberCheckInTileState extends State<_MemberCheckInTile> {
  bool _loading = false;

  Future<void> _toggle() async {
    setState(() => _loading = true);
    try {
      if (widget.isCheckedIn) {
        await widget.onUndo();
      } else {
        await widget.onCheckIn();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCheckedIn = widget.isCheckedIn;
    final name = widget.name;
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final photoUrl = widget.user?.photoUrl ?? '';

    return AnimatedContainer(
      duration: Duration(milliseconds: 220),
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isCheckedIn ? Colors.green.shade50 : cs.surfaceContainerLow,
        border: Border.all(
          color: isCheckedIn ? Colors.green.shade300 : cs.outlineVariant,
          width: isCheckedIn ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // ── Avatar ────────────────────────────────────────────
            Stack(
              children: [
                UserAvatar(
                  photoUrl: photoUrl,
                  initials: initial,
                  color: isCheckedIn ? Colors.green : cs.primary,
                  radius: 22,
                ),
                if (isCheckedIn)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Icon(Icons.check, size: 8, color: Colors.white),
                    ),
                  ),
              ],
            ),
            SizedBox(width: 12),

            // ── Info ──────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isCheckedIn ? Colors.green.shade900 : cs.onSurface,
                    ),
                  ),
                  if (widget.user?.email.isNotEmpty == true)
                    Text(
                      widget.user!.email,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),

            // ── Action ───────────────────────────────────────────
            if (_loading)
              SizedBox(
                width: 36,
                height: 36,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else if (isCheckedIn)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            size: 13, color: Colors.green.shade700),
                        SizedBox(width: 4),
                        Text(
                          context.l10n.tr('Present'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 4),
                  IconButton(
                    tooltip: context.l10n.tr('Undo check-in'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.undo_rounded,
                        size: 18, color: cs.onSurfaceVariant),
                    onPressed: _toggle,
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: _toggle,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(Icons.how_to_reg_outlined, size: 16),
                label: Text(context.l10n.tr('Check in'),
                    style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.4)),
            SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
