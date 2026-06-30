import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import 'package:fit_flow/utils/crash_logger.dart';
import 'package:fit_flow/utils/currency.dart';
import '../../../models/app_user.dart';
import '../../../models/booking.dart';
import '../../../models/gym_class.dart';
import '../../../services/booking_service.dart';
import '../../../services/class_service.dart';
import '../../../services/member_service.dart';

class AdminDropInsTab extends StatefulWidget {
  const AdminDropInsTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminDropInsTab> createState() => _AdminDropInsTabState();
}

class _AdminDropInsTabState extends State<AdminDropInsTab> {
  late final _bookingService = BookingService(gymId: widget.gymId);
  late final _classService = ClassService(gymId: widget.gymId);

  final Map<String, GymClass> _classCache = {};
  // 0=All, 1=Today, 2=Pending Payment
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _classService.streamClasses().listen((classes) {
      if (!mounted) return;
      setState(() {
        for (final c in classes) {
          _classCache[c.id] = c;
        }
      });
    });
  }

  List<Booking> _applyFilter(List<Booking> all) {
    switch (_filter) {
      case 1:
        final today = DateTime.now();
        return all.where((b) {
          final d = b.createdAt;
          return d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
        }).toList();
      case 2:
        return all.where((b) => b.dropInPaymentStatus == 'pending').toList();
      default:
        return all;
    }
  }

  Map<String, List<Booking>> _groupByDate(List<Booking> bookings) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final grouped = <String, List<Booking>>{};
    for (final b in bookings) {
      final d = b.createdAt;
      final dayKey = DateTime(d.year, d.month, d.day);
      String label;
      if (!dayKey.isBefore(todayStart)) {
        label = 'Today';
      } else if (!dayKey.isBefore(yesterdayStart)) {
        label = 'Yesterday';
      } else {
        label = DateFormat('EEEE, d MMMM yyyy').format(d);
      }
      grouped.putIfAbsent(label, () => []).add(b);
    }
    return grouped;
  }

  Future<void> _showAddDropInDialog(BuildContext ctx) async {
    await showDialog<void>(
      context: ctx,
      builder: (_) => _AddDropInDialog(
        classCache: _classCache,
        bookingService: _bookingService,
        gymId: widget.gymId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDropInDialog(context),
        backgroundColor: const Color(0xFFEA580C),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: Text(context.l10n.tr('Add Drop-in'),
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<List<Booking>>(
        stream: _bookingService.streamAllDropIns(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data ?? <Booking>[];
          final filtered = _applyFilter(all);

          final now = DateTime.now();
          final todayDropIns = all.where((b) {
            final d = b.createdAt;
            return d.year == now.year &&
                d.month == now.month &&
                d.day == now.day;
          }).length;
          final pendingCount =
              all.where((b) => b.dropInPaymentStatus == 'pending').length;
          double totalRevenue = 0;
          for (final b in all) {
            if (b.dropInPaymentStatus == 'paid') {
              // Prefer the price snapshotted on the booking; fall back to the
              // class's current price for legacy bookings created before the
              // snapshot field existed.
              totalRevenue += b.dropInPrice > 0
                  ? b.dropInPrice
                  : (_classCache[b.classId]?.dropInPrice ?? 0);
            }
          }

          return Column(
            children: [
              _StatsStrip(
                todayCount: todayDropIns,
                pendingCount: pendingCount,
                totalRevenue: totalRevenue,
              ),
              _FilterBar(
                filter: _filter,
                onFilter: (i) => setState(() => _filter = i),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyState(filter: _filter)
                    : _DropInList(
                        bookings: filtered,
                        classCache: _classCache,
                        groupedBookings: _groupByDate(filtered),
                        bookingService: _bookingService,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats strip
// ─────────────────────────────────────────────────────────────────────────────

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.todayCount,
    required this.pendingCount,
    required this.totalRevenue,
  });
  final int todayCount;
  final int pendingCount;
  final double totalRevenue;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _StatItem(
            label: context.l10n.tr("Today's drop-ins"),
            value: '$todayCount',
            icon: Icons.directions_walk,
          ),
          const SizedBox(width: 20),
          _StatItem(
            label: context.l10n.tr('Pending payment'),
            value: '$pendingCount',
            icon: Icons.hourglass_top_outlined,
          ),
          const SizedBox(width: 20),
          _StatItem(
            label: context.l10n.tr('Confirmed revenue'),
            value: Currency.format(totalRevenue, null),
            icon: Icons.payments_outlined,
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
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
// Filter bar
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onFilter});
  final int filter;
  final ValueChanged<int> onFilter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labels = [context.l10n.tr('All'), context.l10n.tr('Today'), context.l10n.tr('Pending Payment')];

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(labels.length, (i) {
            final selected = filter == i;
            const accent = Color(0xFFEA580C);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(labels[i]),
                selected: selected,
                onSelected: (_) => onFilter(i),
                selectedColor: accent.withValues(alpha: 0.15),
                checkmarkColor: accent,
                labelStyle: TextStyle(
                  color: selected ? accent : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(
                  color: selected ? accent : cs.outlineVariant,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drop-in list grouped by date
// ─────────────────────────────────────────────────────────────────────────────

class _DropInList extends StatelessWidget {
  const _DropInList({
    required this.bookings,
    required this.classCache,
    required this.groupedBookings,
    required this.bookingService,
  });
  final List<Booking> bookings;
  final Map<String, GymClass> classCache;
  final Map<String, List<Booking>> groupedBookings;
  final BookingService bookingService;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        for (final entry in groupedBookings.entries) ...[
          _DateHeader(label: entry.key),
          ...entry.value.map((b) => _DropInCard(
                booking: b,
                gymClass: classCache[b.classId],
                bookingService: bookingService,
              )),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date header
// ─────────────────────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final isToday = label == 'Today';
    final isYesterday = label == 'Yesterday';
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          if (isToday || isYesterday)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isToday
                    ? const Color(0xFFEA580C)
                    : const Color(0xFFEA580C).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isToday ? Colors.white : const Color(0xFFEA580C),
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
// Drop-in booking card
// ─────────────────────────────────────────────────────────────────────────────

class _DropInCard extends StatelessWidget {
  const _DropInCard({
    required this.booking,
    required this.gymClass,
    required this.bookingService,
  });
  final Booking booking;
  final GymClass? gymClass;
  final BookingService bookingService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPaid = booking.dropInPaymentStatus == 'paid';
    // Snapshotted price (fall back to the class's current price for legacy
    // bookings without it).
    final price =
        booking.dropInPrice > 0 ? booking.dropInPrice : (gymClass?.dropInPrice ?? 0.0);
    final priceLabel = Currency.format(price, null);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            booking.memberName.isNotEmpty
                                ? booking.memberName
                                : context.l10n.tr('Unknown'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEA580C),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              context.l10n.tr('Drop-in'),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (booking.isGuest) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                context.l10n.tr('Guest'),
                                style: TextStyle(
                                  color: Colors.purple.shade700,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (booking.isGuest && booking.guestEmail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.email_outlined,
                                size: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              booking.guestEmail,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      if (gymClass != null) ...[
                        Text(
                          gymClass!.title,
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                        Text(
                          DateFormat('EEE d MMM • HH:mm')
                              .format(gymClass!.startTime),
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  cs.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                      ] else
                        Text(
                          '${context.l10n.tr('Class ID')}: ${booking.classId}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      priceLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPaid
                            ? const Color(0xFF059669).withValues(alpha: 0.12)
                            : const Color(0xFFEA580C).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPaid ? context.l10n.tr('✓ Paid') : context.l10n.tr('💰 Pending'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isPaid
                              ? const Color(0xFF059669)
                              : const Color(0xFFEA580C),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (!isPaid) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _markPaid(context),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(context.l10n.tr('Mark as Paid')), 
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF059669),
                    side: const BorderSide(color: Color(0xFF059669)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _markPaid(BuildContext context) async {
    try {
      await bookingService.markDropInPaid(booking.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('Payment confirmed!')), 
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'markDropInPaid');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10n.tr('Error')}: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final int filter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final msg = filter == 1
        ? context.l10n.tr('No drop-ins today')
        : filter == 2
            ? context.l10n.tr('No pending payments')
            : context.l10n.tr('No drop-in bookings yet');
    final sub = filter == 2
        ? context.l10n.tr('All drop-ins have been paid.')
        : context.l10n.tr('Drop-in bookings will appear here.');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_walk_outlined,
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(msg,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Drop-in Dialog (admin manual booking)
// ─────────────────────────────────────────────────────────────────────────────

class _AddDropInDialog extends StatefulWidget {
  const _AddDropInDialog({
    required this.classCache,
    required this.bookingService,
    required this.gymId,
  });
  final Map<String, GymClass> classCache;
  final BookingService bookingService;
  final String gymId;

  @override
  State<_AddDropInDialog> createState() => _AddDropInDialogState();
}

class _AddDropInDialogState extends State<_AddDropInDialog> {
  late final _memberService = MemberService(gymId: widget.gymId);
  GymClass? _selectedClass;
  String? _selectedMemberId;
  String _selectedMemberName = '';
  bool _saving = false;
  String? _error;

  // Guest mode
  bool _isGuest = false;
  final _guestNameCtrl = TextEditingController();
  final _guestEmailCtrl = TextEditingController();

  @override
  void dispose() {
    _guestNameCtrl.dispose();
    _guestEmailCtrl.dispose();
    super.dispose();
  }

  List<GymClass> get _dropInClasses =>
      widget.classCache.values.where((c) => c.dropInEnabled).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  Future<void> _save() async {
    if (_selectedClass == null) {
      setState(() => _error = context.l10n.tr('Please select a class.'));
      return;
    }
    if (_isGuest) {
      final name = _guestNameCtrl.text.trim();
      final email = _guestEmailCtrl.text.trim();
      if (name.isEmpty) {
        setState(() => _error = context.l10n.tr('Please enter the guest name.'));
        return;
      }
      if (email.isEmpty || !email.contains('@')) {
        setState(() => _error = context.l10n.tr('Please enter a valid email address.'));
        return;
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        await widget.bookingService.bookGuestDropIn(
          classId: _selectedClass!.id,
          guestName: name,
          guestEmail: email,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('$name ${context.l10n.tr('added as guest drop-in for')} ${_selectedClass!.title}'),
          backgroundColor: const Color(0xFFEA580C),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      } catch (e, s) {
        await CrashLogger.log(e, s, reason: 'bookGuestDropIn');
        setState(() {
          _saving = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }

    if (_selectedMemberId == null || _selectedMemberId!.isEmpty) {
      setState(() => _error = context.l10n.tr('Please select a member.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.bookingService.bookClass(
        classId: _selectedClass!.id,
        userId: _selectedMemberId!,
        isDropIn: true,
        dropInPaymentStatus: 'pending',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_selectedMemberName booked as drop-in for ${_selectedClass!.title}',
          ),
          backgroundColor: const Color(0xFFEA580C),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'bookAdminDropIn');
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const accent = Color(0xFFEA580C);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_add_rounded,
                      color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add Drop-in',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        _isGuest
                            ? 'Register a non-member guest'
                            : 'Book a member as a drop-in guest',
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Member / Guest toggle
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isGuest = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_isGuest ? cs.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: !_isGuest
                              ? [
                                  BoxShadow(
                                      color: Colors.black.withAlpha(18),
                                      blurRadius: 4)
                                ]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_outline_rounded,
                                size: 16,
                                color:
                                    !_isGuest ? accent : cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(context.l10n.tr('Member'),
                                style: TextStyle(
                                    fontWeight: !_isGuest
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                    fontSize: 13,
                                    color: !_isGuest
                                        ? accent
                                        : cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isGuest = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _isGuest ? cs.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: _isGuest
                              ? [
                                  BoxShadow(
                                      color: Colors.black.withAlpha(18),
                                      blurRadius: 4)
                                ]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_alt_1_outlined,
                                size: 16,
                                color: _isGuest ? accent : cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(context.l10n.tr('Non-member'),
                                style: TextStyle(
                                    fontWeight: _isGuest
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                    fontSize: 13,
                                    color: _isGuest
                                        ? accent
                                        : cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Class picker
            Text(context.l10n.tr('Class'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            _dropInClasses.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.tr('No classes have drop-ins enabled. Enable drop-ins in the Classes tab first.'),
                            style: TextStyle(
                                color: Colors.orange.shade800, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                : DropdownButtonFormField<GymClass>(
                    value: _selectedClass,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.fitness_center_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    hint: Text(context.l10n.tr('Select a class')), 
                    items: _dropInClasses
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              '${c.title}  •  ${DateFormat('EEE d MMM HH:mm').format(c.startTime)}  •  ${Currency.format(c.dropInPrice, null)}',
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedClass = v),
                  ),
            const SizedBox(height: 16),

            // Member picker or Guest fields
            if (_isGuest) ...[
              Text(context.l10n.tr('Guest Name'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: _guestNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.badge_outlined),
                  hintText: context.l10n.tr('Full name'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),
              Text(context.l10n.tr('Email Address'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: _guestEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.email_outlined),
                  hintText: context.l10n.tr('guest@example.com'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ] else ...[
              Text(context.l10n.tr('Member'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              StreamBuilder<List<AppUser>>(
                stream: _memberService.streamMembers(),
                builder: (context, snap) {
                  final members = snap.data ?? <AppUser>[];
                  members
                      .sort((a, b) => a.displayName.compareTo(b.displayName));
                  return DropdownButtonFormField<String>(
                    value: _selectedMemberId,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    hint: Text(context.l10n.tr('Select a member')), 
                    items: members
                        .map(
                          (m) => DropdownMenuItem<String>(
                            value: m.id,
                            child: Text(
                              m.displayName.isNotEmpty
                                  ? m.displayName
                                  : m.email,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      final picked =
                          members.where((m) => m.id == id).firstOrNull;
                      setState(() {
                        _selectedMemberId = id;
                        _selectedMemberName =
                            picked?.displayName.isNotEmpty == true
                                ? picked!.displayName
                                : (picked?.email ?? '');
                      });
                    },
                  );
                },
              ),
            ],

            // Price preview
            if (_selectedClass != null) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.euro_outlined, size: 16, color: accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${context.l10n.tr('Drop-in fee')}: ${Currency.format(_selectedClass!.dropInPrice, null)}  •  ${context.l10n.tr('Payment collected at desk')}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: accent,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ],

            const SizedBox(height: 24),
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
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(context.l10n.tr('Book Drop-in'),
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
