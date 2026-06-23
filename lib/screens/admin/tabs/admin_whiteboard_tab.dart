import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/gym_class.dart';
import '../../../services/booking_service.dart';
import '../../../services/class_service.dart';
import '../class_whiteboard_screen.dart';

/// Admin Whiteboard hub — lists today's (or selected-date) classes.
/// Tapping a class opens the full ClassWhiteboardScreen.
class AdminWhiteboardTab extends StatefulWidget {
  const AdminWhiteboardTab({super.key, required this.gymId});
  final String gymId;

  @override
  State<AdminWhiteboardTab> createState() => _AdminWhiteboardTabState();
}

class _AdminWhiteboardTabState extends State<AdminWhiteboardTab> {
  late final ClassService _classService = ClassService(gymId: widget.gymId);

  DateTime _selectedDate = _today();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  List<GymClass> _filterForDate(List<GymClass> all, DateTime date) {
    return all.where((c) {
      final d = c.startTime;
      return d.year == date.year && d.month == date.month && d.day == date.day;
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  void _openWhiteboard(GymClass gymClass) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassWhiteboardScreen(
          gymClass: gymClass,
          gymId: widget.gymId,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('EEEE, d MMMM yyyy');
    final isToday = _selectedDate == _today();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Top bar ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
                bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4))),
          ),
          child: Row(
            children: [
              // Date chip
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 15, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        isToday
                            ? context.l10n.tr('Today')
                            : dateFmt.format(_selectedDate),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.expand_more,
                          size: 16, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Today shortcut
              if (!isToday)
                TextButton(
                  onPressed: () =>
                      setState(() => _selectedDate = _today()),
                  child: Text(context.l10n.tr('Today')),
                ),
              // Prev / Next day
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: context.l10n.tr('Previous day'),
                onPressed: () => setState(() => _selectedDate =
                    _selectedDate.subtract(const Duration(days: 1))),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: context.l10n.tr('Next day'),
                onPressed: () => setState(() =>
                    _selectedDate =
                        _selectedDate.add(const Duration(days: 1))),
              ),
            ],
          ),
        ),
        // ── Class list ───────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<GymClass>>(
            stream: _classService.streamAllClasses(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                    child: Text('${snap.error}',
                        style: TextStyle(color: cs.error)));
              }

              final classes =
                  _filterForDate(snap.data ?? [], _selectedDate);

              if (classes.isEmpty) {
                return _EmptyDay(
                  date: _selectedDate,
                  isToday: isToday,
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: classes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _ClassCard(
                  gymClass: classes[i],
                  gymId: widget.gymId,
                  onOpenWhiteboard: () => _openWhiteboard(classes[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ClassCard
// ─────────────────────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  const _ClassCard({
    required this.gymClass,
    required this.gymId,
    required this.onOpenWhiteboard,
  });

  final GymClass gymClass;
  final String gymId;
  final VoidCallback onOpenWhiteboard;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timeFmt = DateFormat('HH:mm');
    final timeLabel =
        '${timeFmt.format(gymClass.startTime)} – ${timeFmt.format(gymClass.endTime)}';
    final bookingService = BookingService(gymId: gymId);

    return StreamBuilder<int>(
      stream: bookingService
          .streamBookingsForClass(gymClass.id)
          .map((list) => list.length),
      builder: (context, snap) {
        final total = snap.data ?? 0;

        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Coloured top strip
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    // Time badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF0F766E)
                                .withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        timeLabel,
                        style: const TextStyle(
                            color: Color(0xFF0F766E),
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title + coaches
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gymClass.title,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800),
                          ),
                          if (gymClass.coachNames.isNotEmpty)
                            Text(
                              gymClass.coachNames.join(', '),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    // Booking count badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline,
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '$total',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Open Whiteboard button
                    FilledButton.icon(
                      onPressed: onOpenWhiteboard,
                      icon: const Icon(Icons.dashboard_outlined, size: 15),
                      label: Text(context.l10n.tr('Whiteboard')),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyDay
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.date, required this.isToday});
  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = isToday
        ? context.l10n.tr('No classes scheduled for today')
        : context.l10n.tr(
            'No classes on ${DateFormat('d MMM yyyy').format(date)}');
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: cs.surfaceContainerLow, shape: BoxShape.circle),
            child: Icon(Icons.fitness_center_outlined,
                size: 36, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(label,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            context.l10n.tr('Use the date picker to navigate to another day'),
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
