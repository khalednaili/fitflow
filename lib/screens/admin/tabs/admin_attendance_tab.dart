import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import 'package:fit_flow/utils/crash_logger.dart';
import '../../../models/app_user.dart';
import '../../../models/booking.dart';
import '../../../models/gym_class.dart';
import '../../../models/waitlist_entry.dart';
import '../../../services/booking_service.dart';
import '../../../services/class_service.dart';
import '../../../services/member_service.dart';
import '../../../widgets/user_avatar.dart';

// ── Main tab ──────────────────────────────────────────────────────────────────

class AdminAttendanceTab extends StatefulWidget {
  const AdminAttendanceTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminAttendanceTab> createState() => _AdminAttendanceTabState();
}

class _AdminAttendanceTabState extends State<AdminAttendanceTab> {
  late final _classService = ClassService(gymId: widget.gymId);
  String _selectedClassId = '';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GymClass>>(
      stream: _classService.streamAllClasses(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final classes = snap.data ?? <GymClass>[];
        if (classes.isEmpty) {
          return _EmptyClasses();
        }

        if (_selectedClassId.isEmpty ||
            classes.every((c) => c.id != _selectedClassId)) {
          _selectedClassId = classes.first.id;
        }
        final selected = classes.firstWhere((c) => c.id == _selectedClassId);

        return Column(
          children: [
            // ── Class selector ──────────────────────────────────────────
            _ClassSelectorBar(
              classes: classes,
              selectedId: _selectedClassId,
              onChanged: (id) => setState(() => _selectedClassId = id),
            ),
            // ── Attendance pane ─────────────────────────────────────────
            Expanded(
              child: _AttendancePane(
                gymClass: selected,
                gymId: widget.gymId,
                search: _search,
                onSearchChanged: (v) => setState(() => _search = v),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Class selector bar ────────────────────────────────────────────────────────

class _ClassSelectorBar extends StatelessWidget {
  const _ClassSelectorBar({
    required this.classes,
    required this.selectedId,
    required this.onChanged,
  });

  final List<GymClass> classes;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: DropdownButtonHideUnderline(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: DropdownButton<String>(
            value: selectedId,
            isExpanded: true,
            icon: Icon(Icons.keyboard_arrow_down, color: cs.primary),
            items: classes.map((c) {
              final isToday = DateUtils.isSameDay(c.startTime, DateTime.now());
              return DropdownMenuItem<String>(
                value: c.id,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isToday
                            ? cs.primary.withValues(alpha: 0.12)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isToday
                            ? 'Today'
                            : DateFormat('EEE').format(c.startTime),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isToday ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${c.title}  ·  ${DateFormat('HH:mm').format(c.startTime)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${c.bookedCount}/${c.capacity}',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

// ── Attendance pane ───────────────────────────────────────────────────────────

class _AttendancePane extends StatefulWidget {
  const _AttendancePane({
    required this.gymClass,
    required this.gymId,
    required this.search,
    required this.onSearchChanged,
  });

  final GymClass gymClass;
  final String gymId;
  final String search;
  final ValueChanged<String> onSearchChanged;

  @override
  State<_AttendancePane> createState() => _AttendancePaneState();
}

class _AttendancePaneState extends State<_AttendancePane>
    with SingleTickerProviderStateMixin {
  late final TabController _tc = TabController(length: 2, vsync: this);
  late final _bookingService = BookingService(gymId: widget.gymId);

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<Booking>>(
      stream: _bookingService.streamBookingsForClass(widget.gymClass.id),
      builder: (context, bookSnap) {
        final bookings = bookSnap.data ?? <Booking>[];

        return StreamBuilder<Set<String>>(
          stream: _bookingService.streamCheckedInUserIds(widget.gymClass.id),
          builder: (context, attSnap) {
            final checkedInIds = attSnap.data ?? <String>{};
            final checkedInCount = checkedInIds.length;
            final totalBooked = bookings.length;
            final rate = totalBooked > 0 ? checkedInCount / totalBooked : 0.0;

            return Column(
              children: [
                // ── Stats banner ────────────────────────────────────────
                _StatsBanner(
                  checkedIn: checkedInCount,
                  booked: totalBooked,
                  waitlist: widget.gymClass.waitlistCount,
                  rate: rate,
                ),
                // ── Search ──────────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    onChanged: widget.onSearchChanged,
                    decoration: InputDecoration(
                      hintText: context.l10n.tr('Search member…'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                // ── Tabs ────────────────────────────────────────────────
                TabBar(
                  controller: _tc,
                  labelColor: cs.primary,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  indicatorColor: cs.primary,
                  dividerColor: cs.outlineVariant,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline, size: 16),
                          const SizedBox(width: 5),
                          Text('${context.l10n.tr('Booked')} ($totalBooked)'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_top_outlined,
                              size: 16, color: Colors.orange.shade600),
                          const SizedBox(width: 5),
                          Text(
                            '${context.l10n.tr('Waitlist')} (${widget.gymClass.waitlistCount})',
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tc,
                    children: [
                      _BookedList(
                        gymClass: widget.gymClass,
                        gymId: widget.gymId,
                        bookings: bookings,
                        checkedInIds: checkedInIds,
                        search: widget.search,
                      ),
                      _WaitlistList(gymClass: widget.gymClass),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Stats banner ──────────────────────────────────────────────────────────────

class _StatsBanner extends StatelessWidget {
  const _StatsBanner({
    required this.checkedIn,
    required this.booked,
    required this.waitlist,
    required this.rate,
  });

  final int checkedIn;
  final int booked;
  final int waitlist;
  final double rate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rateColor = rate >= 0.8
        ? Colors.green.shade700
        : rate >= 0.5
            ? Colors.orange.shade700
            : cs.error;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatChip(
                icon: Icons.check_circle_outline,
                label: context.l10n.tr('Checked in'),
                value: '$checkedIn',
                color: Colors.green.shade600,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.event_available_outlined,
                label: context.l10n.tr('Booked'),
                value: '$booked',
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.hourglass_top_outlined,
                label: context.l10n.tr('Waitlist'),
                value: '$waitlist',
                color: Colors.orange.shade700,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: rate,
                    minHeight: 7,
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(rate * 100).round()}% attendance',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: rateColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

// ── Booked list ───────────────────────────────────────────────────────────────

class _BookedList extends StatefulWidget {
  const _BookedList({
    required this.gymClass,
    required this.gymId,
    required this.bookings,
    required this.checkedInIds,
    required this.search,
  });

  final GymClass gymClass;
  final String gymId;
  final List<Booking> bookings;
  final Set<String> checkedInIds;
  final String search;

  @override
  State<_BookedList> createState() => _BookedListState();
}

class _BookedListState extends State<_BookedList> {
  late final _bookingService = BookingService(gymId: widget.gymId);
  late final _memberService = MemberService(gymId: widget.gymId);

  @override
  Widget build(BuildContext context) {
    final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (widget.bookings.isEmpty) {
      return _EmptyState(
        icon: Icons.people_outline,
        message: context.l10n.tr('No booked members yet.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: widget.bookings.length,
      itemBuilder: (context, i) {
        final booking = widget.bookings[i];
        return StreamBuilder<AppUser?>(
          stream: _memberService.streamUser(booking.userId),
          builder: (context, userSnap) {
            final user = userSnap.data;
            final name = (user?.displayName.isNotEmpty == true)
                ? user!.displayName
                : user?.email ?? booking.userId;

            if (widget.search.isNotEmpty &&
                !name.toLowerCase().contains(widget.search.toLowerCase())) {
              return const SizedBox.shrink();
            }

            final isCheckedIn = widget.checkedInIds.contains(booking.userId);
            return _MemberCheckInCard(
              user: user,
              name: name,
              isCheckedIn: isCheckedIn,
              onCheckIn: () => _bookingService.checkInMember(
                classId: widget.gymClass.id,
                userId: booking.userId,
                checkedInBy: adminId,
              ),
              onUndo: () => _bookingService.undoCheckIn(
                classId: widget.gymClass.id,
                userId: booking.userId,
              ),
            );
          },
        );
      },
    );
  }
}

// ── Member check-in card ──────────────────────────────────────────────────────

class _MemberCheckInCard extends StatefulWidget {
  const _MemberCheckInCard({
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
  State<_MemberCheckInCard> createState() => _MemberCheckInCardState();
}

class _MemberCheckInCardState extends State<_MemberCheckInCard> {
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
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isCheckedIn ? Colors.green.shade50 : cs.surfaceContainerLow,
        border: Border.all(
          color: isCheckedIn ? Colors.green.shade300 : cs.outlineVariant,
          width: isCheckedIn ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar
            UserAvatar(
              photoUrl: photoUrl,
              initials: initial,
              color: isCheckedIn ? Colors.green : cs.primary,
              radius: 20,
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  if (widget.user?.email.isNotEmpty == true)
                    Text(widget.user!.email,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            // Check-in / undo button
            if (_loading)
              const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (isCheckedIn)
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(context.l10n.tr('Present'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: context.l10n.tr('Undo check-in'),
                    icon:
                        Icon(Icons.undo, size: 18, color: cs.onSurfaceVariant),
                    onPressed: _toggle,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: _toggle,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.how_to_reg_outlined, size: 16),
                label: Text(context.l10n.tr('Check in'), style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Waitlist list ─────────────────────────────────────────────────────────────

class _WaitlistList extends StatefulWidget {
  const _WaitlistList({required this.gymClass});
  final GymClass gymClass;

  @override
  State<_WaitlistList> createState() => _WaitlistListState();
}

class _WaitlistListState extends State<_WaitlistList> {
  late final _bookingService = BookingService(gymId: widget.gymClass.gymId);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<WaitlistEntry>>(
      stream: _bookingService.streamWaitlistForClass(widget.gymClass.id),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final entries = snap.data ?? <WaitlistEntry>[];
        if (entries.isEmpty) {
          return _EmptyState(
              icon: Icons.hourglass_empty, message: context.l10n.tr('Waitlist is empty.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final entry = entries[i];
            final pos = i + 1;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: cs.surfaceContainerLow,
                border: Border.all(
                    color: Colors.orange.shade200.withValues(alpha: 0.7)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Position badge
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('#$pos',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: Colors.orange.shade800)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.memberName.isNotEmpty
                                ? entry.memberName
                                : entry.userId,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          Text(
                            '${context.l10n.tr('Joined')} ${DateFormat('d MMM • HH:mm').format(entry.createdAt)}',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.tr('Promote to booked'),
                      icon: Icon(Icons.arrow_upward_rounded,
                          color: Colors.green.shade600),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final fallbackMember = context.l10n.tr('Member');
                        final promotedLabel = context.l10n.tr('promoted.');
                        try {
                          await _bookingService
                              .promoteFirstWaitlisted(widget.gymClass.id);
                          messenger.showSnackBar(SnackBar(
                            content: Text(
                                '${entry.memberName.isNotEmpty ? entry.memberName : fallbackMember} $promotedLabel'),
                            backgroundColor: Colors.green.shade600,
                          ));
                        } catch (e, s) {
                          await CrashLogger.log(
                            e,
                            s,
                            reason: 'promoteWaitlistBooking',
                          );
                          messenger.showSnackBar(
                              SnackBar(content: Text(e.toString())));
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _EmptyClasses extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(context.l10n.tr('No upcoming classes. Create some first.')));
}
