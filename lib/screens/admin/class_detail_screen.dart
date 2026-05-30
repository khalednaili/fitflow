import 'package:fit_flow/utils/crash_logger.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/booking.dart';
import '../../models/gym_class.dart';
import '../../models/user_subscription.dart';
import '../../models/waitlist_entry.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import '../checkin/class_checkin_screen.dart';
import '../../widgets/qr_code_dialog.dart';
import 'select_coaches_screen.dart';
import 'tabs/admin_classes_tab.dart';
import '../../models/app_user.dart';
import 'member_detail_screen.dart';
import '../../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public widget
// ─────────────────────────────────────────────────────────────────────────────

class ClassDetailScreen extends StatefulWidget {
  const ClassDetailScreen({
    super.key,
    required this.gymClass,
    required this.gymId,
    this.readOnly = false,
  });

  final GymClass gymClass;
  final String gymId;
  final bool readOnly;

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  late final _classService = ClassService(gymId: widget.gymId);
  late final _bookingService = BookingService(gymId: widget.gymId);
  late final Stream<List<Booking>> _bookingsStream;
  late final Stream<List<WaitlistEntry>> _waitlistStream;

  bool _hideDetails = false;

  static const _palette = <Color>[
    Color(0xFF147AD6),
    Color(0xFF008272),
    Color(0xFFB146C2),
    Color(0xFFD83B01),
    Color(0xFF5C2D91),
    Color(0xFF8764B8),
    Color(0xFF4F6BED),
    Color(0xFF498205),
  ];

  @override
  void initState() {
    super.initState();
    _bookingsStream =
        _bookingService.streamBookingsForClass(widget.gymClass.id);
    _waitlistStream =
        _bookingService.streamWaitlistForClass(widget.gymClass.id);
  }

  Color _classColor(GymClass gymClass) {
    if (gymClass.classColorValue != null) {
      return Color(gymClass.classColorValue!);
    }
    final key = gymClass.title.trim().toLowerCase();
    return _palette[key.isEmpty ? 0 : key.codeUnitAt(0) % _palette.length];
  }

  String _durationLabel(GymClass gymClass) {
    final mins = gymClass.endTime.difference(gymClass.startTime).inMinutes;
    if (mins <= 0) return '';
    if (mins < 60) return '${mins}min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  // ── Action handlers ────────────────────────────────────────────────────────

  Future<void> _handleEdit(GymClass liveClass) async {
    await showClassEditorDialog(
      context,
      gymId: widget.gymId,
      existing: liveClass,
    );
  }

  Future<void> _handleDelete(GymClass liveClass) async {
    if (liveClass.recurrenceGroupId != null) {
      final deleteScope = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFDC2626), size: 32),
          title: Text(context.l10n.tr('Delete recurring class?')),
          content:
              Text(context.l10n.tr('Which occurrences do you want to delete?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.l10n.tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('this'),
              child: Text(context.l10n.tr('This only')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('following'),
              child: Text(context.l10n.tr('This & following')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.of(ctx).pop('all'),
              child: Text(context.l10n.tr('Entire series')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (deleteScope == null) return;
      if (deleteScope == 'this') {
        await _classService.deleteClass(liveClass.id);
      } else if (deleteScope == 'following') {
        await _classService.deleteSeriesFromDate(
            liveClass.recurrenceGroupId!, liveClass.startTime);
      } else if (deleteScope == 'all') {
        await _classService.deleteEntireSeries(liveClass.recurrenceGroupId!);
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFDC2626), size: 32),
          title: Text(context.l10n.tr('Delete class?')),
          content: Text(
            'This will permanently delete "${liveClass.title}" on '
            '${DateFormat('EEE, d MMM').format(liveClass.startTime)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.l10n.tr('Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.l10n.tr('Delete')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _classService.deleteClass(liveClass.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _handleCopyToDay(GymClass liveClass) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDate: liveClass.startTime.add(const Duration(days: 1)),
      helpText: 'Copy class to…',
    );
    if (picked == null || !mounted) return;
    await _classService.copyClassToDate(
      sourceClassId: liveClass.id,
      targetDate: picked,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${context.l10n.tr('Class copied to')} ${DateFormat('EEE, d MMM').format(picked)}'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _handleDuplicateSeries(GymClass liveClass) async {
    if (liveClass.recurrenceGroupId == null) return;

    final result = await showModalBottomSheet<_DuplicateSeriesResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DuplicateSeriesSheet(sourceClass: liveClass),
    );

    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await _classService.duplicateSeries(
        sourceRecurrenceGroupId: liveClass.recurrenceGroupId!,
        newStartDate: result.dateRange.start,
        newEndDate: result.dateRange.end,
        overrideStartTime: result.startTime,
        overrideEndTime: result.endTime,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.tr('Series duplicated successfully!')),
        backgroundColor: Colors.green,
      ));
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'duplicateSeries');
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('${context.l10n.tr('Failed to duplicate')}: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _handleBulkCheckIn(
    GymClass liveClass,
    List<Booking> pending,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.done_all_rounded,
            color: Color(0xFF16A34A), size: 32),
        title: Text(l10n.tr('Check In Everyone?')),
        content: Text(
          l10n.tr(
              'This will mark all ${pending.length} member(s) as checked in for "${liveClass.title}".'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('Cancel')),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('Check In All')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final count = await _bookingService.bulkCheckInAll(
        classId: liveClass.id,
        bookings: pending,
        checkedInBy: FirebaseAuth.instance.currentUser?.uid ?? 'admin',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count member(s) checked in successfully.'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'bulkCheckIn');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleAssignCoaches(GymClass liveClass) async {
    final initial = [
      for (var i = 0; i < liveClass.coachIds.length; i++)
        CoachSelectionResult(
          id: liveClass.coachIds[i],
          name: i < liveClass.coachNames.length
              ? liveClass.coachNames[i]
              : liveClass.coachName,
        ),
    ];

    if (!mounted) return;
    final result = await pickCoaches(
      context: context,
      gymId: widget.gymId,
      initialSelection: initial,
    );
    if (result == null || !mounted) return;

    final ids = result.map((c) => c.id).toList();
    final names = result.map((c) => c.name).toList();
    final primaryName =
        names.isNotEmpty ? names.join(', ') : liveClass.coachName;

    await FirebaseFirestore.instance
        .collection('classes')
        .doc(liveClass.id)
        .update({
      'coachIds': ids,
      'coachNames': names,
      'coachName': primaryName,
      'updatedAt': Timestamp.now(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isEmpty
              ? 'Coaches removed from class.'
              : 'Coaches updated: $primaryName'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showMessageDialog(BuildContext context, List<Booking> bookings) {
    final members = bookings
        .where((b) => !b.isGuest && b.memberName.isNotEmpty)
        .map((b) => b.memberName)
        .toSet()
        .toList()
      ..sort();
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.email_outlined),
                    const SizedBox(width: 10),
                    Text(
                      'Booked Members (${bookings.length})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Messaging is not yet integrated. The following members are booked for this class:',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 14),
                          const SizedBox(width: 8),
                          Text(members[i],
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  List<PopupMenuEntry<String>> _buildMenuItems(GymClass liveClass) => [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.edit_outlined),
            title: Text(context.l10n.tr('Edit Class')),
          ),
        ),
        if (liveClass.recurrenceGroupId != null)
          PopupMenuItem(
            value: 'duplicate',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.content_copy_outlined),
              title: Text(context.l10n.tr('Duplicate Series')),
            ),
          ),
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.content_copy),
            title: Text(context.l10n.tr('Copy to Day…')),
          ),
        ),
        if (!widget.readOnly)
          PopupMenuItem(
            value: 'assign_coaches',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.sports_outlined),
              title: Text(context.l10n.tr('Assign Coaches')),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
            title: Text(context.l10n.tr('Delete Class'),
                style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ),
      ];

  void _onMenuAction(String action, GymClass liveClass) {
    switch (action) {
      case 'edit':
        _handleEdit(liveClass);
      case 'delete':
        _handleDelete(liveClass);
      case 'copy':
        _handleCopyToDay(liveClass);
      case 'duplicate':
        _handleDuplicateSeries(liveClass);
      case 'assign_coaches':
        _handleAssignCoaches(liveClass);
    }
  }

  List<Widget> _buildActionButtons(
    BuildContext context,
    GymClass liveClass,
    Color color,
    List<Booking> bookings,
  ) {
    final cs = Theme.of(context).colorScheme;
    final pendingCheckIn =
        bookings.where((b) => !b.checkedIn && b.userId.isNotEmpty).toList();
    return [
      _HeaderAction(
        icon: Icons.how_to_reg_outlined,
        label: 'Check-In Screen',
        color: const Color(0xFF0F766E),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ClassCheckInScreen(gymClass: liveClass),
          ),
        ),
      ),
      _HeaderAction(
        icon: Icons.qr_code_2_rounded,
        label: 'Class QR',
        color: cs.primary,
        onPressed: () => ClassQrCodeDialog.show(context, liveClass),
      ),
      if (!widget.readOnly) ...[
        _HeaderAction(
          icon: Icons.add,
          label: 'Add Booking',
          color: color,
          onPressed: () => showForceReservationDialog(
            context,
            gymClass: liveClass,
            gymId: widget.gymId,
          ),
        ),
        _HeaderAction(
          icon: Icons.done_all_rounded,
          label: pendingCheckIn.isEmpty
              ? 'All Checked In'
              : 'Check In All (${pendingCheckIn.length})',
          color: pendingCheckIn.isEmpty
              ? cs.onSurfaceVariant
              : const Color(0xFF16A34A),
          onPressed: pendingCheckIn.isEmpty
              ? null
              : () => _handleBulkCheckIn(liveClass, pendingCheckIn),
        ),
      ],
      _HeaderAction(
        icon: Icons.email_outlined,
        label: 'Message Booked',
        color: cs.onSurfaceVariant,
        onPressed: bookings.isEmpty
            ? null
            : () => _showMessageDialog(context, bookings),
      ),
      _HeaderAction(
        icon: _hideDetails
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        label: _hideDetails ? 'Show Details' : 'Hide Details',
        color: cs.onSurfaceVariant,
        onPressed: () => setState(() => _hideDetails = !_hideDetails),
      ),
    ];
  }

  Widget _buildAttendeeTable(
    BuildContext context,
    GymClass liveClass,
    Color color,
    List<Booking> bookings,
    bool loading,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 800;

    // On narrow screens wrap in horizontal scroll so every column stays
    // fully visible instead of being squeezed to near-zero width.
    Widget table = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!loading && bookings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(children: [
              const SizedBox(width: 30),
              const SizedBox(width: 160, child: _ColHeader('Attendee')),
              Tooltip(
                message: context.l10n.tr('Health Notes'),
                child: SizedBox(
                  width: 28,
                  child: Icon(Icons.health_and_safety_outlined,
                      size: 14, color: const Color(0xFFD97706)),
                ),
              ),
              _ColHeaderFixed('Bookings', 58),
              if (!_hideDetails) ...[
                const SizedBox(width: 160, child: _ColHeader('Packages')),
                _ColHeaderFixed('Outstanding', 90),
              ],
              const SizedBox(width: 40),
              const SizedBox(width: 40),
            ]),
          ),
        if (!loading && bookings.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
            ),
            child: Row(children: [
              Icon(Icons.inbox_outlined, color: cs.onSurfaceVariant, size: 18),
              const SizedBox(width: 10),
              Text(context.l10n.tr('No bookings yet'),
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ]),
          ),
        if (!loading)
          ...bookings.map((b) => _AttendeeRow(
                key: ValueKey(b.id),
                booking: b,
                gymClass: liveClass,
                accentColor: color,
                hideDetails: _hideDetails,
              )),
      ],
    );

    // On wide screens the panel is wide enough for flex layout; on mobile
    // give the table a minimum width and let it scroll horizontally.
    if (!isWide) {
      final minWidth = _hideDetails ? 358.0 : 608.0;
      table = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: minWidth, child: table),
      );
    }

    return table;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GymClass?>(
      stream: _classService.streamClass(widget.gymClass.id),
      builder: (context, classSnap) {
        final liveClass = classSnap.data ?? widget.gymClass;
        return StreamBuilder<List<Booking>>(
          stream: _bookingsStream,
          builder: (context, bookingSnap) {
            return StreamBuilder<List<WaitlistEntry>>(
              stream: _waitlistStream,
              builder: (context, waitlistSnap) {
                final loading =
                    bookingSnap.connectionState == ConnectionState.waiting;
                final bookings = bookingSnap.data ?? [];
                final waitlistEntries = waitlistSnap.data ?? [];
                final checkedInCount =
                    bookings.where((b) => b.checkedIn).length;
                final noShowsCount =
                    bookings.where((b) => !b.checkedIn).length;

                final isWide = MediaQuery.sizeOf(context).width >= 800;
                return isWide
                    ? _buildWide(context, liveClass, bookings, waitlistEntries,
                        loading, checkedInCount, noShowsCount)
                    : _buildMobile(context, liveClass, bookings,
                        waitlistEntries, loading, checkedInCount, noShowsCount);
              },
            );
          },
        );
      },
    );
  }

  // ── Mobile layout (< 800px) ────────────────────────────────────────────────

  Widget _buildMobile(
    BuildContext context,
    GymClass liveClass,
    List<Booking> bookings,
    List<WaitlistEntry> waitlistEntries,
    bool loading,
    int checkedInCount,
    int noShowsCount,
  ) {
    final color = _classColor(liveClass);
    final duration = _durationLabel(liveClass);
    final coaches = liveClass.coachNames.isNotEmpty
        ? liveClass.coachNames.join(', ')
        : liveClass.coachName;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
            actionsIconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              liveClass.title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            actions: [
              if (!widget.readOnly)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  tooltip: context.l10n.tr('Actions'),
                  onSelected: (v) => _onMenuAction(v, liveClass),
                  itemBuilder: (_) => _buildMenuItems(liveClass),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _GradientHeaderContent(
                gymClass: liveClass,
                color: color,
                duration: duration,
                coaches: coaches,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _buildActionButtons(
                        context, liveClass, color, bookings),
                  ),
                  const SizedBox(height: 14),
                  loading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _StatsBar(
                          booked: bookings.length,
                          capacity: liveClass.capacity,
                          checkedIn: checkedInCount,
                          noShows: noShowsCount,
                          waitlist: liveClass.waitlistCount,
                          color: color,
                        ),
                  const SizedBox(height: 14),
                  Divider(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.15),
                      height: 1),
                  const SizedBox(height: 6),
                  _buildAttendeeTable(
                      context, liveClass, color, bookings, loading),
                  if (!widget.readOnly && waitlistEntries.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _WaitlistSection(
                      entries: waitlistEntries,
                      classId: liveClass.id,
                      gymClass: liveClass,
                      bookingService: _bookingService,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Wide layout (>= 800px) ─────────────────────────────────────────────────

  Widget _buildWide(
    BuildContext context,
    GymClass liveClass,
    List<Booking> bookings,
    List<WaitlistEntry> waitlistEntries,
    bool loading,
    int checkedInCount,
    int noShowsCount,
  ) {
    final color = _classColor(liveClass);
    final duration = _durationLabel(liveClass);
    final coaches = liveClass.coachNames.isNotEmpty
        ? liveClass.coachNames.join(', ')
        : liveClass.coachName;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          liveClass.title,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.72)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          if (!widget.readOnly)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              tooltip: context.l10n.tr('Actions'),
              onSelected: (v) => _onMenuAction(v, liveClass),
              itemBuilder: (_) => _buildMenuItems(liveClass),
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left panel: class info + stats + actions ──────────────
          SizedBox(
            width: 380,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: cs.outline.withValues(alpha: 0.15)),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gradient info card
                    _ClassInfoCard(
                      gymClass: liveClass,
                      color: color,
                      duration: duration,
                      coaches: coaches,
                    ),
                    const SizedBox(height: 16),
                    // Stats
                    if (loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      _StatsBar(
                        booked: bookings.length,
                        capacity: liveClass.capacity,
                        checkedIn: checkedInCount,
                        noShows: noShowsCount,
                        waitlist: liveClass.waitlistCount,
                        color: color,
                      ),
                    const SizedBox(height: 16),
                    // Action buttons
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _buildActionButtons(
                          context, liveClass, color, bookings),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Right panel: attendee list ─────────────────────────────
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAttendeeTable(
                            context, liveClass, color, bookings, false),
                        if (!widget.readOnly && waitlistEntries.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _WaitlistSection(
                            entries: waitlistEntries,
                            classId: liveClass.id,
                            gymClass: liveClass,
                            bookingService: _bookingService,
                          ),
                        ],
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
// Gradient header content for SliverAppBar flexibleSpace (mobile)
// ─────────────────────────────────────────────────────────────────────────────

class _GradientHeaderContent extends StatelessWidget {
  const _GradientHeaderContent({
    required this.gymClass,
    required this.color,
    required this.duration,
    required this.coaches,
  });

  final GymClass gymClass;
  final Color color;
  final String duration;
  final String coaches;

  @override
  Widget build(BuildContext context) {
    final isFull = gymClass.isFull;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(22, 52, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            DateFormat('EEEE, d MMMM').format(gymClass.startTime),
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          Text(
            gymClass.title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.2),
          ),
          const SizedBox(height: 5),
          Row(children: [
            const Icon(Icons.access_time_rounded,
                color: Colors.white70, size: 13),
            const SizedBox(width: 4),
            Text(
              '${DateFormat('HH:mm').format(gymClass.startTime)} – ${DateFormat('HH:mm').format(gymClass.endTime)}'
              '${duration.isNotEmpty ? '  ·  $duration' : ''}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ]),
          if (coaches.isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.sports_outlined,
                  color: Colors.white70, size: 13),
              const SizedBox(width: 4),
              Text(coaches,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: [
              if (isFull)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(context.l10n.tr('FULL'),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFDC2626),
                          letterSpacing: 0.7)),
                ),
              if (gymClass.recurrenceGroupId != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.repeat, color: Colors.white, size: 10),
                      SizedBox(width: 3),
                      Text(context.l10n.tr('RECURRING'),
                          style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5)),
                    ],
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
// Class info card for wide layout left panel
// ─────────────────────────────────────────────────────────────────────────────

class _ClassInfoCard extends StatelessWidget {
  const _ClassInfoCard({
    required this.gymClass,
    required this.color,
    required this.duration,
    required this.coaches,
  });

  final GymClass gymClass;
  final Color color;
  final String duration;
  final String coaches;

  @override
  Widget build(BuildContext context) {
    final isFull = gymClass.isFull;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, d MMMM').format(gymClass.startTime),
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            gymClass.title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.2),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.access_time_rounded,
                color: Colors.white70, size: 13),
            const SizedBox(width: 4),
            Text(
              '${DateFormat('HH:mm').format(gymClass.startTime)} – ${DateFormat('HH:mm').format(gymClass.endTime)}'
              '${duration.isNotEmpty ? '  ·  $duration' : ''}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ]),
          if (coaches.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.sports_outlined,
                  color: Colors.white70, size: 13),
              const SizedBox(width: 4),
              Expanded(
                child: Text(coaches,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              if (isFull)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(context.l10n.tr('FULL'),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFDC2626),
                          letterSpacing: 0.7)),
                ),
              if (gymClass.recurrenceGroupId != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.repeat, color: Colors.white, size: 10),
                      SizedBox(width: 3),
                      Text(context.l10n.tr('RECURRING'),
                          style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5)),
                    ],
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
// Action bar button
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: onPressed == null
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)
            : color,
        side: BorderSide(
          color: onPressed == null
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)
              : color.withValues(alpha: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats bar
// ─────────────────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.booked,
    required this.capacity,
    required this.checkedIn,
    required this.noShows,
    required this.waitlist,
    required this.color,
  });

  final int booked;
  final int capacity;
  final int checkedIn;
  final int noShows;
  final int waitlist;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFull = capacity > 0 && booked >= capacity;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          _StatCell(
            label: 'Booked',
            value: capacity > 0 ? '$booked/$capacity' : '$booked',
            color: isFull ? const Color(0xFFDC2626) : color,
          ),
          _StatSep(),
          _StatCell(
            label: 'Checked-In',
            value: '$checkedIn',
            color: const Color(0xFF16A34A),
          ),
          _StatSep(),
          _StatCell(
            label: 'No Shows',
            value: '$noShows',
            color: noShows > 0 ? const Color(0xFFD97706) : cs.onSurfaceVariant,
          ),
          if (waitlist > 0) ...[
            _StatSep(),
            _StatCell(
              label: 'Waitlist',
              value: '$waitlist',
              color: const Color(0xFFF97316),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _StatSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Table column headers
// ─────────────────────────────────────────────────────────────────────────────

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(context.l10n.tr(label),
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}

class _ColHeaderFixed extends StatelessWidget {
  const _ColHeaderFixed(this.label, this.width);
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(context.l10n.tr(label),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attendee table row
// ─────────────────────────────────────────────────────────────────────────────

class _MemberRowData {
  const _MemberRowData({
    required this.totalBookings,
    required this.subscriptions,
    required this.planNames,
    required this.weeklyAttendance,
    this.healthNotes = '',
    this.user,
  });

  final int totalBookings;
  final List<UserSubscription> subscriptions;

  /// Maps planId → human-readable plan name fetched from membership_plans.
  final Map<String, String> planNames;
  final int weeklyAttendance;
  final String healthNotes;

  /// Full user profile — null for guests or when the doc doesn't exist.
  final AppUser? user;
}

class _AttendeeRow extends StatefulWidget {
  const _AttendeeRow({
    super.key,
    required this.booking,
    required this.gymClass,
    required this.accentColor,
    required this.hideDetails,
  });

  final Booking booking;
  final GymClass gymClass;
  final Color accentColor;
  final bool hideDetails;

  @override
  State<_AttendeeRow> createState() => _AttendeeRowState();
}

class _AttendeeRowState extends State<_AttendeeRow> {
  static const _green = Color(0xFF16A34A);

  bool _checkInLoading = false;
  // Cache the future so setState (e.g. check-in toggle) never re-fetches.
  late final Future<_MemberRowData?> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = widget.booking.userId.isNotEmpty
        ? _loadData()
        : Future<_MemberRowData?>.value(null);
  }

  String get _name {
    if (widget.booking.isGuest) return widget.booking.guestEmail;
    if (widget.booking.memberName.isNotEmpty) return widget.booking.memberName;
    final uid = widget.booking.userId;
    return 'Member ${uid.length > 6 ? uid.substring(0, 6) : uid}';
  }

  String get _initials {
    final n = _name.trim();
    if (n.isEmpty) return '?';
    return n
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
  }

  Future<_MemberRowData?> _loadData() async {
    final userId = widget.booking.userId;
    if (userId.isEmpty) return null;

    final now = DateTime.now();
    final weekStart =
        DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));

    final results = await Future.wait<dynamic>([
      FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: userId)
          .get(),
      FirebaseFirestore.instance
          .collection('user_subscriptions')
          .where('userId', isEqualTo: userId)
          .get(),
      FirebaseFirestore.instance
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('checkedInAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .where('checkedInAt', isLessThan: Timestamp.fromDate(weekEnd))
          .get(),
      FirebaseFirestore.instance.collection('users').doc(userId).get(),
    ]);

    List<UserSubscription> subs =
        (results[1] as QuerySnapshot<Map<String, dynamic>>)
            .docs
            .map((d) => UserSubscription.fromSnapshot(d))
            .toList();

    // Legacy: some records use docId == userId
    if (subs.isEmpty) {
      final legacyDoc = await FirebaseFirestore.instance
          .collection('user_subscriptions')
          .doc(userId)
          .get();
      if (legacyDoc.exists) {
        subs = [UserSubscription.fromSnapshot(legacyDoc)];
      }
    }

    subs.sort((a, b) {
      final aEnd = a.endDate ?? DateTime(2100);
      final bEnd = b.endDate ?? DateTime(2100);
      return bEnd.compareTo(aEnd);
    });

    final planIds =
        subs.map((s) => s.planId).where((id) => id.isNotEmpty).toSet();
    final planDocs = await Future.wait(planIds.map((id) => FirebaseFirestore
        .instance
        .collection('membership_plans')
        .doc(id)
        .get()));
    final planNames = <String, String>{};
    for (final doc in planDocs) {
      if (doc.exists) {
        planNames[doc.id] = doc.data()?['name'] as String? ?? doc.id;
      }
    }

    final userDoc = results[3] as DocumentSnapshot<Map<String, dynamic>>;
    final healthNotes =
        (userDoc.data()?['healthNotes'] as String? ?? '').trim();

    return _MemberRowData(
      totalBookings:
          (results[0] as QuerySnapshot<Map<String, dynamic>>).docs.length,
      subscriptions: subs,
      planNames: planNames,
      weeklyAttendance:
          (results[2] as QuerySnapshot<Map<String, dynamic>>).docs.length,
      healthNotes: healthNotes,
      user: (results[3] as DocumentSnapshot<Map<String, dynamic>>).exists
          ? AppUser.fromSnapshot(
              results[3] as DocumentSnapshot<Map<String, dynamic>>)
          : null,
    );
  }

  Future<void> _toggleCheckIn() async {
    setState(() => _checkInLoading = true);
    try {
      final svc = BookingService(gymId: widget.gymClass.gymId);
      if (widget.booking.checkedIn) {
        await svc.undoCheckIn(
          classId: widget.booking.classId,
          userId: widget.booking.userId,
        );
      } else {
        await svc.checkInMember(
          classId: widget.booking.classId,
          userId: widget.booking.userId,
          checkedInBy: FirebaseAuth.instance.currentUser?.uid ?? 'admin',
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'toggleClassCheckIn');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.l10n.tr('Error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _checkInLoading = false);
    }
  }

  Future<void> _cancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Color(0xFFDC2626), size: 28),
        title: Text(context.l10n.tr('Cancel booking?')),
        content: Text(
            '${context.l10n.tr('Remove')} $_name ${context.l10n.tr('from this class?')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.tr('Keep'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Cancel Booking')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await BookingService(gymId: widget.gymClass.gymId).cancelBooking(
      userId: widget.booking.userId,
      classId: widget.booking.classId,
    );
  }

  void _openProfile(BuildContext context, _MemberRowData? data) {
    final user = data?.user;
    if (user != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MemberDetailScreen(member: user),
        ),
      );
      return;
    }
    // Fallback for guests or missing user docs
    showDialog<void>(
      context: context,
      builder: (_) => _MemberProfileDialog(
        booking: widget.booking,
        gymClass: widget.gymClass,
        accentColor: widget.accentColor,
        name: _name,
        initials: _initials,
        onToggleCheckIn: _toggleCheckIn,
        onCancelBooking: _cancelBooking,
      ),
    );
  }

  void _openOffer(BuildContext context, _MemberRowData? data) {
    if (data == null || data.subscriptions.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => _SubscriptionDetailDialog(
        name: _name,
        initials: _initials,
        accentColor: widget.accentColor,
        subscriptions: data.subscriptions,
        planNames: data.planNames,
        weeklyAttendance: data.weeklyAttendance,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final checkedIn = widget.booking.checkedIn;
    final color = widget.accentColor;

    return FutureBuilder<_MemberRowData?>(
      future: _dataFuture,
      builder: (context, snap) {
        final data = snap.data;

        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: checkedIn ? _green.withValues(alpha: 0.04) : cs.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: checkedIn
                            ? _green.withValues(alpha: 0.5)
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(8)),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Info button
                            SizedBox(
                              width: 30,
                              child: Tooltip(
                                message: context.l10n.tr('View Profile'),
                                child: InkWell(
                                  onTap: () => _openProfile(context, data),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Icon(Icons.info_outline,
                                      size: 16,
                                      color: color.withValues(alpha: 0.8)),
                                ),
                              ),
                            ),
                            // Name
                            SizedBox(
                              width: 160,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () => _openProfile(context, data),
                                    child: Text(
                                      _name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (widget.booking.isDropIn ||
                                      widget.booking.isGuest ||
                                      checkedIn)
                                    Wrap(
                                      spacing: 3,
                                      children: [
                                        if (widget.booking.isDropIn)
                                          _TinyBadge('Drop-in',
                                              const Color(0xFF7C3AED)),
                                        if (widget.booking.isGuest)
                                          _TinyBadge(
                                              'Guest', const Color(0xFFD97706)),
                                        if (checkedIn &&
                                            widget.booking.checkedInAt != null)
                                          _TinyBadge(
                                            DateFormat('HH:mm').format(
                                                widget.booking.checkedInAt!),
                                            _green,
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            // Health notes column
                            SizedBox(
                              width: 28,
                              child: Center(
                                child: (data != null &&
                                        data.healthNotes.isNotEmpty)
                                    ? Tooltip(
                                        message: data.healthNotes,
                                        preferBelow: false,
                                        triggerMode: TooltipTriggerMode.tap,
                                        showDuration:
                                            const Duration(seconds: 6),
                                        child: const Icon(
                                          Icons.health_and_safety,
                                          size: 15,
                                          color: Color(0xFFD97706),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                            // Total bookings
                            SizedBox(
                              width: 58,
                              child: Center(
                                child: snap.connectionState ==
                                            ConnectionState.waiting &&
                                        data == null
                                    ? SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: cs.onSurfaceVariant),
                                      )
                                    : Text(
                                        data != null
                                            ? '${data.totalBookings}'
                                            : '—',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSurface,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            ),
                            // Packages (hideable)
                            if (!widget.hideDetails)
                              SizedBox(
                                width: 160,
                                child: data == null
                                    ? const SizedBox.shrink()
                                    : _PackagesCell(
                                        subscriptions: data.subscriptions,
                                        planNames: data.planNames,
                                        weeklyCount: data.weeklyAttendance,
                                      ),
                              ),
                            // Outstanding (hideable)
                            if (!widget.hideDetails)
                              SizedBox(
                                width: 90,
                                child: data == null
                                    ? const SizedBox.shrink()
                                    : _OutstandingCell(
                                        subscriptions: data.subscriptions,
                                      ),
                              ),
                            // Check-in toggle
                            SizedBox(
                              width: 40,
                              child: Center(
                                child: _checkInLoading
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: color),
                                      )
                                    : Tooltip(
                                        message: checkedIn
                                            ? 'Undo check-in'
                                            : 'Mark checked in',
                                        child: InkWell(
                                          onTap: _toggleCheckIn,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: Icon(
                                            checkedIn
                                                ? Icons.check_circle_rounded
                                                : Icons.check_circle_outline,
                                            size: 22,
                                            color: checkedIn
                                                ? _green
                                                : cs.onSurfaceVariant
                                                    .withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            // Actions menu
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert,
                                  size: 17,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.6)),
                              onSelected: (v) {
                                if (v == 'profile') _openProfile(context, data);
                                if (v == 'offer') _openOffer(context, data);
                                if (v == 'checkin') _toggleCheckIn();
                                if (v == 'cancel') _cancelBooking();
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'profile',
                                  child: ListTile(
                                    leading: Icon(Icons.person_outline),
                                    title:
                                        Text(context.l10n.tr('View Profile')),
                                    dense: true,
                                  ),
                                ),
                                if (data != null &&
                                    data.subscriptions.isNotEmpty)
                                  PopupMenuItem(
                                    value: 'offer',
                                    child: ListTile(
                                      leading:
                                          Icon(Icons.card_membership_rounded),
                                      title: Text(
                                          context.l10n.tr('View Subscription')),
                                      dense: true,
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: 'checkin',
                                  child: ListTile(
                                    leading: Icon(
                                      checkedIn
                                          ? Icons.undo_rounded
                                          : Icons.how_to_reg_rounded,
                                      color: checkedIn
                                          ? const Color(0xFFD97706)
                                          : _green,
                                    ),
                                    title: Text(checkedIn
                                        ? 'Undo Check-in'
                                        : 'Mark Checked In'),
                                    dense: true,
                                  ),
                                ),
                                if (!widget.booking.isGuest)
                                  PopupMenuItem(
                                    value: 'cancel',
                                    child: ListTile(
                                      leading: Icon(
                                          Icons.person_remove_outlined,
                                          color: Color(0xFFDC2626)),
                                      title: Text(
                                          context.l10n.tr('Cancel Booking'),
                                          style: TextStyle(
                                              color: Color(0xFFDC2626))),
                                      dense: true,
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
              Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.outline.withValues(alpha: 0.08)),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Packages cell
// ─────────────────────────────────────────────────────────────────────────────

class _PackagesCell extends StatelessWidget {
  const _PackagesCell({
    required this.subscriptions,
    required this.planNames,
    required this.weeklyCount,
  });

  final List<UserSubscription> subscriptions;
  final Map<String, String> planNames;
  final int weeklyCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (subscriptions.isEmpty) {
      return Text('—',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: subscriptions.take(2).map((sub) {
        final displayName = planNames[sub.planId] ?? sub.planId;
        final endText = sub.endDate != null
            ? 'End: ${DateFormat('d MMM yyyy').format(sub.endDate!)}'
            : '';
        final weeklyText = weeklyCount > 0 ? '($weeklyCount this week)' : '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(fontSize: 11, color: cs.onSurface),
              children: [
                TextSpan(
                  text: displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (weeklyText.isNotEmpty)
                  TextSpan(
                    text: ' $weeklyText',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                if (endText.isNotEmpty)
                  TextSpan(
                    text: ' · $endText',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outstanding cell
// ─────────────────────────────────────────────────────────────────────────────

class _OutstandingCell extends StatelessWidget {
  const _OutstandingCell({required this.subscriptions});
  final List<UserSubscription> subscriptions;

  @override
  Widget build(BuildContext context) {
    final outstanding = subscriptions.fold<int>(
      0,
      (acc, s) => acc + s.remainingAmount,
    );
    if (outstanding <= 0) return const SizedBox.shrink();
    final currency =
        subscriptions.isNotEmpty ? subscriptions.first.currency : '';
    return Text(
      '$currency ${outstanding.toStringAsFixed(0)}',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFFDC2626),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscription detail dialog
// ─────────────────────────────────────────────────────────────────────────────

class _SubscriptionDetailDialog extends StatelessWidget {
  const _SubscriptionDetailDialog({
    required this.name,
    required this.initials,
    required this.accentColor,
    required this.subscriptions,
    required this.planNames,
    required this.weeklyAttendance,
  });

  final String name;
  final String initials;
  final Color accentColor;
  final List<UserSubscription> subscriptions;
  final Map<String, String> planNames;
  final int weeklyAttendance;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const red = Color(0xFFDC2626);
    const green = Color(0xFF16A34A);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor,
                    accentColor.withValues(alpha: 0.75),
                  ],
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    child: Text(initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        Text(
                          '${subscriptions.length} active subscription${subscriptions.length == 1 ? '' : 's'}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (weeklyAttendance > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                size: 13, color: green),
                            const SizedBox(width: 6),
                            Text(
                              '$weeklyAttendance session${weeklyAttendance == 1 ? '' : 's'} this week',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: green,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ...subscriptions.map((sub) {
                      final planName = planNames[sub.planId] ?? sub.planId;
                      final outstanding = sub.remainingAmount;
                      final isActive = sub.status == 'active';
                      final isExpired = sub.endDate != null &&
                          sub.endDate!.isBefore(DateTime.now());
                      final statusColor = isExpired
                          ? red
                          : isActive
                              ? green
                              : const Color(0xFFD97706);
                      final statusLabel = isExpired
                          ? 'Expired'
                          : isActive
                              ? 'Active'
                              : sub.status.isNotEmpty
                                  ? sub.status
                                  : 'Unknown';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: cs.outline.withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.card_membership_rounded,
                                      size: 16, color: Color(0xFF7C3AED)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(planName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(statusLabel,
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: statusColor)),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, thickness: 0.5),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  _SubDetailRow(
                                    icon: Icons.calendar_month_outlined,
                                    label: 'Start Date',
                                    value: sub.startDate != null
                                        ? DateFormat('d MMM yyyy')
                                            .format(sub.startDate!)
                                        : '—',
                                  ),
                                  _SubDetailRow(
                                    icon: Icons.event_available_outlined,
                                    label: 'End Date',
                                    value: sub.endDate != null
                                        ? DateFormat('d MMM yyyy')
                                            .format(sub.endDate!)
                                        : '—',
                                    valueColor: isExpired ? red : null,
                                  ),
                                  _SubDetailRow(
                                    icon: Icons.payments_outlined,
                                    label: 'Total Amount',
                                    value: '${sub.currency} ${sub.totalAmount}',
                                  ),
                                  _SubDetailRow(
                                    icon: Icons.check_circle_outline,
                                    label: 'Amount Paid',
                                    value: '${sub.currency} ${sub.amountPaid}',
                                    valueColor: green,
                                  ),
                                  if (outstanding > 0)
                                    _SubDetailRow(
                                      icon: Icons.warning_amber_outlined,
                                      label: 'Outstanding',
                                      value: '${sub.currency} $outstanding',
                                      valueColor: red,
                                      valueBold: true,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubDetailRow extends StatelessWidget {
  const _SubDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(context.l10n.tr(label),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiny inline badge
// ─────────────────────────────────────────────────────────────────────────────

class _TinyBadge extends StatelessWidget {
  const _TinyBadge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Booking member tile (kept for potential future use)
// ─────────────────────────────────────────────────────────────────────────────

class _BookingMemberTile extends StatefulWidget {
  const _BookingMemberTile({
    required this.booking,
    required this.gymClass,
    required this.accentColor,
  });

  final Booking booking;
  final GymClass gymClass;
  final Color accentColor;

  @override
  State<_BookingMemberTile> createState() => _BookingMemberTileState();
}

class _BookingMemberTileState extends State<_BookingMemberTile> {
  bool _loading = false;

  String get _name {
    if (widget.booking.isGuest) return widget.booking.guestEmail;
    if (widget.booking.memberName.isNotEmpty) return widget.booking.memberName;
    final uid = widget.booking.userId;
    return 'Member ${uid.length > 6 ? uid.substring(0, 6) : uid}';
  }

  String get _initials {
    final n = _name.trim();
    if (n.isEmpty) return '?';
    return n
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
  }

  Future<void> _toggleCheckIn() async {
    setState(() => _loading = true);
    try {
      final svc = BookingService(gymId: widget.gymClass.gymId);
      if (widget.booking.checkedIn) {
        await svc.undoCheckIn(
          classId: widget.booking.classId,
          userId: widget.booking.userId,
        );
      } else {
        await svc.checkInMember(
          classId: widget.booking.classId,
          userId: widget.booking.userId,
          checkedInBy: FirebaseAuth.instance.currentUser?.uid ?? 'admin',
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'cancelClassBooking');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.l10n.tr('Error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Cancel Booking')),
        content: Text('${context.l10n.tr('Cancel booking for')} $_name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('No')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(context.l10n.tr('Yes, Cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      await BookingService(gymId: widget.gymClass.gymId).cancelBooking(
        userId: widget.booking.userId,
        classId: widget.booking.classId,
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'markClassDropInPaid');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.l10n.tr('Error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showProfile() {
    final userId = widget.booking.userId;
    if (userId.isNotEmpty && !widget.booking.isGuest) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get()
          .then((doc) {
        if (!mounted) return;
        if (doc.exists) {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  MemberDetailScreen(member: AppUser.fromSnapshot(doc)),
            ),
          );
          return;
        }
        _showFallbackDialog();
      });
      return;
    }
    _showFallbackDialog();
  }

  void _showFallbackDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _MemberProfileDialog(
        booking: widget.booking,
        gymClass: widget.gymClass,
        accentColor: widget.accentColor,
        name: _name,
        initials: _initials,
        onToggleCheckIn: _toggleCheckIn,
        onCancelBooking: _cancelBooking,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final checkedIn = widget.booking.checkedIn;
    const green = Color(0xFF16A34A);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: checkedIn
              ? green.withValues(alpha: 0.4)
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: checkedIn
          ? green.withValues(alpha: 0.05)
          : cs.surfaceContainerHighest.withValues(alpha: 0.3),
      elevation: 0,
      child: InkWell(
        onTap: _showProfile,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.accentColor.withValues(alpha: 0.15),
                  border: Border.all(
                      color: widget.accentColor.withValues(alpha: 0.6),
                      width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: widget.accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (checkedIn)
                          const _MiniTag(label: 'Checked In', color: green)
                        else
                          _MiniTag(
                              label: 'Pending', color: cs.onSurfaceVariant),
                        if (widget.booking.isDropIn)
                          const _MiniTag(
                              label: 'Drop-in', color: Color(0xFF7C3AED)),
                        if (widget.booking.isGuest)
                          const _MiniTag(
                              label: 'Guest', color: Color(0xFFD97706)),
                        if (checkedIn && widget.booking.checkedInAt != null)
                          _MiniTag(
                            label: DateFormat('HH:mm')
                                .format(widget.booking.checkedInAt!),
                            color: green,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_loading)
                const SizedBox(
                  width: 34,
                  height: 34,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                Tooltip(
                  message: checkedIn ? 'Undo check-in' : 'Mark as checked in',
                  child: InkWell(
                    onTap: _toggleCheckIn,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: checkedIn
                            ? green.withValues(alpha: 0.15)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        checkedIn
                            ? Icons.how_to_reg_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 18,
                        color: checkedIn ? green : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                icon:
                    Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
                onSelected: (v) {
                  if (v == 'profile') _showProfile();
                  if (v == 'checkin') _toggleCheckIn();
                  if (v == 'cancel') _cancelBooking();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: ListTile(
                      leading: Icon(Icons.person_outline),
                      title: Text(context.l10n.tr('View Profile')),
                      dense: true,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'checkin',
                    child: ListTile(
                      leading: Icon(
                        checkedIn
                            ? Icons.undo_rounded
                            : Icons.how_to_reg_rounded,
                        color: checkedIn ? const Color(0xFFD97706) : green,
                      ),
                      title:
                          Text(checkedIn ? 'Undo Check-in' : 'Mark Checked In'),
                      dense: true,
                    ),
                  ),
                  if (!widget.booking.isGuest)
                    PopupMenuItem(
                      value: 'cancel',
                      child: ListTile(
                        leading: Icon(Icons.person_remove_outlined,
                            color: Color(0xFFDC2626)),
                        title: Text(context.l10n.tr('Cancel Booking'),
                            style: TextStyle(color: Color(0xFFDC2626))),
                        dense: true,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Member profile dialog
// ─────────────────────────────────────────────────────────────────────────────

class _MemberProfileDialog extends StatefulWidget {
  const _MemberProfileDialog({
    required this.booking,
    required this.gymClass,
    required this.accentColor,
    required this.name,
    required this.initials,
    required this.onToggleCheckIn,
    required this.onCancelBooking,
  });

  final Booking booking;
  final GymClass gymClass;
  final Color accentColor;
  final String name;
  final String initials;
  final VoidCallback onToggleCheckIn;
  final VoidCallback onCancelBooking;

  @override
  State<_MemberProfileDialog> createState() => _MemberProfileDialogState();
}

class _MemberProfileDialogState extends State<_MemberProfileDialog> {
  bool _actionLoading = false;
  bool _paidLoading = false;
  bool? _paidOverride;

  static const _green = Color(0xFF16A34A);
  static const _amber = Color(0xFFD97706);
  static const _red = Color(0xFFDC2626);
  static const _purple = Color(0xFF7C3AED);

  bool get _isPaid =>
      _paidOverride ?? widget.booking.dropInPaymentStatus == 'paid';

  Future<void> _toggleCheckIn() async {
    setState(() => _actionLoading = true);
    try {
      widget.onToggleCheckIn();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _cancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: _red, size: 30),
        title: Text(context.l10n.tr('Cancel booking?')),
        content: Text(
            '${context.l10n.tr('Remove')} ${widget.name} ${context.l10n.tr('from this class?')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.tr('Keep'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Cancel Booking')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onCancelBooking();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _markPaid() async {
    setState(() => _paidLoading = true);
    try {
      await BookingService(gymId: widget.gymClass.gymId)
          .markDropInPaid(widget.booking.id);
      if (mounted) setState(() => _paidOverride = true);
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'markClassDropInPaid');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.l10n.tr('Error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _paidLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final checkedIn = widget.booking.checkedIn;
    final color = widget.accentColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header banner
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.18),
                    color.withValues(alpha: 0.06),
                  ],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.2),
                      border: Border.all(
                          color: color.withValues(alpha: 0.5), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.initials,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            _MiniTag(
                              label: checkedIn ? 'Checked In' : 'Pending',
                              color: checkedIn ? _green : cs.onSurfaceVariant,
                            ),
                            if (widget.booking.isDropIn)
                              const _MiniTag(label: 'Drop-in', color: _purple),
                            if (widget.booking.isGuest)
                              const _MiniTag(label: 'Guest', color: _amber),
                            if (widget.booking.isDropIn)
                              _MiniTag(
                                label: _isPaid ? 'Paid' : 'Payment Pending',
                                color:
                                    _isPaid ? _green : const Color(0xFFF97316),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            // Scrollable body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (checkedIn) ...[
                      _CheckInStatusCard(
                        checkedInAt: widget.booking.checkedInAt,
                        bookedAt: widget.booking.createdAt,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (widget.booking.isDropIn) ...[
                      _DropInPaymentCard(
                        isPaid: _isPaid,
                        loading: _paidLoading,
                        onMarkPaid: _isPaid ? null : _markPaid,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (!widget.booking.isGuest &&
                        widget.booking.userId.isNotEmpty)
                      _MemberFirestoreSection(
                        userId: widget.booking.userId,
                        accentColor: color,
                      ),
                    _SectionLabel(label: 'Booking', color: color),
                    const SizedBox(height: 8),
                    _InfoCard(
                      children: [
                        _ProfileRow(
                          icon: Icons.fitness_center_outlined,
                          label: widget.gymClass.title,
                        ),
                        _ProfileRow(
                          icon: Icons.access_time_outlined,
                          label:
                              '${DateFormat('EEE d MMM, HH:mm').format(widget.gymClass.startTime)} – ${DateFormat('HH:mm').format(widget.gymClass.endTime)}',
                        ),
                        _ProfileRow(
                          icon: Icons.confirmation_number_outlined,
                          label:
                              'Booked on ${DateFormat('d MMM yyyy, HH:mm').format(widget.booking.createdAt)}',
                        ),
                      ],
                    ),
                    if (!widget.booking.isGuest &&
                        widget.booking.userId.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _AttendanceHistorySection(
                        userId: widget.booking.userId,
                        accentColor: color,
                        currentClassId: widget.gymClass.id,
                        gymId: widget.gymClass.gymId,
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // Sticky action footer
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                border: Border(
                    top: BorderSide(color: cs.outline.withValues(alpha: 0.15))),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: _actionLoading
                  ? const Center(
                      child: SizedBox(
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _ActionFooter(
                      checkedIn: checkedIn,
                      isGuest: widget.booking.isGuest,
                      onToggleCheckIn: _toggleCheckIn,
                      onCancelBooking: _cancelBooking,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Check-in status card
// ─────────────────────────────────────────────────────────────────────────────

class _CheckInStatusCard extends StatelessWidget {
  const _CheckInStatusCard({
    required this.checkedInAt,
    required this.bookedAt,
  });

  final DateTime? checkedInAt;
  final DateTime bookedAt;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.how_to_reg_rounded, color: green, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Checked In',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: green,
                  ),
                ),
                if (checkedInAt != null)
                  Text(
                    DateFormat('EEEE d MMM, HH:mm').format(checkedInAt!),
                    style: const TextStyle(
                        fontSize: 12, color: green, height: 1.4),
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
// Drop-in payment card
// ─────────────────────────────────────────────────────────────────────────────

class _DropInPaymentCard extends StatelessWidget {
  const _DropInPaymentCard({
    required this.isPaid,
    required this.loading,
    required this.onMarkPaid,
  });

  final bool isPaid;
  final bool loading;
  final VoidCallback? onMarkPaid;

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);
    const orange = Color(0xFFF97316);
    const green = Color(0xFF16A34A);
    final color = isPaid ? green : orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.door_sliding_outlined,
                color: purple, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.tr('Drop-in'),
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                Text(
                  isPaid
                      ? context.l10n.tr('Payment received')
                      : context.l10n.tr('Payment pending'),
                  style: TextStyle(fontSize: 12, color: color, height: 1.4),
                ),
              ],
            ),
          ),
          if (!isPaid)
            loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onMarkPaid,
                    icon: const Icon(Icons.check, size: 14),
                    label: Text(context.l10n.tr('Mark Paid'),
                        style: const TextStyle(fontSize: 12)),
                  ),
          if (isPaid)
            const Icon(Icons.verified_rounded, color: green, size: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Member Firestore section
// ─────────────────────────────────────────────────────────────────────────────

class _MemberFirestoreSection extends StatelessWidget {
  const _MemberFirestoreSection({
    required this.userId,
    required this.accentColor,
  });

  final String userId;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data?.data();
        if (data == null) return const SizedBox.shrink();

        final email = data['email'] as String?;
        final phone = data['phone'] as String?;
        final planId = data['planId'] as String?;
        final planStatus = data['planStatus'] as String?;
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(label: 'Member Profile', color: accentColor),
            const SizedBox(height: 8),
            _InfoCard(
              children: [
                if (email != null && email.isNotEmpty)
                  _ProfileRow(icon: Icons.email_outlined, label: email),
                if (phone != null && phone.isNotEmpty)
                  _ProfileRow(icon: Icons.phone_outlined, label: phone),
                if (planId != null && planId.isNotEmpty)
                  _ProfileRow(
                    icon: Icons.card_membership_outlined,
                    label: planId,
                    trailing: planStatus != null
                        ? _MiniTag(
                            label: planStatus,
                            color: planStatus == 'active'
                                ? green
                                : cs.onSurfaceVariant,
                          )
                        : null,
                  ),
                if (createdAt != null)
                  _ProfileRow(
                    icon: Icons.calendar_today_outlined,
                    label:
                        'Joined ${DateFormat('d MMM yyyy').format(createdAt)}',
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attendance history section
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceHistorySection extends StatelessWidget {
  const _AttendanceHistorySection({
    required this.userId,
    required this.accentColor,
    required this.currentClassId,
    this.gymId = '',
  });

  final String userId;
  final Color accentColor;
  final String currentClassId;
  final String gymId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Attendance History', color: accentColor),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: BookingService(gymId: gymId).streamAttendanceForUser(userId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final records = snap.data ?? [];
            final total = records.length;
            final recent = records.take(3).toList();

            return _InfoCard(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.bar_chart_rounded,
                          size: 15, color: accentColor),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$total class${total == 1 ? '' : 'es'} attended total',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (recent.isNotEmpty) ...[
                  Divider(
                      height: 16, color: cs.outline.withValues(alpha: 0.15)),
                  ...recent.map((r) {
                    final classTitle = (r['classTitle'] as String?) ?? 'Class';
                    final ts = (r['checkedInAt'] as Timestamp?)?.toDate();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(Icons.history_rounded,
                              size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              classTitle,
                              style:
                                  TextStyle(fontSize: 12, color: cs.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (ts != null)
                            Text(
                              DateFormat('d MMM').format(ts),
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info card
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action footer
// ─────────────────────────────────────────────────────────────────────────────

class _ActionFooter extends StatelessWidget {
  const _ActionFooter({
    required this.checkedIn,
    required this.isGuest,
    required this.onToggleCheckIn,
    required this.onCancelBooking,
  });

  final bool checkedIn;
  final bool isGuest;
  final VoidCallback onToggleCheckIn;
  final VoidCallback onCancelBooking;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    const amber = Color(0xFFD97706);
    const red = Color(0xFFDC2626);

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: checkedIn ? amber : green,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onToggleCheckIn,
            icon: Icon(
              checkedIn ? Icons.undo_rounded : Icons.how_to_reg_rounded,
              size: 16,
            ),
            label: Text(checkedIn ? 'Undo Check-In' : 'Check In'),
          ),
        ),
        if (!isGuest) ...[
          const SizedBox(width: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: red,
              side: BorderSide(color: red.withValues(alpha: 0.7), width: 1.3),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onCancelBooking,
            icon: const Icon(Icons.person_remove_outlined, size: 16),
            label: Text(context.l10n.tr('Cancel')),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duplicate Series bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DuplicateSeriesResult {
  const _DuplicateSeriesResult({
    required this.dateRange,
    required this.startTime,
    required this.endTime,
  });
  final DateTimeRange dateRange;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
}

class _DuplicateSeriesSheet extends StatefulWidget {
  const _DuplicateSeriesSheet({required this.sourceClass});
  final GymClass sourceClass;

  @override
  State<_DuplicateSeriesSheet> createState() => _DuplicateSeriesSheetState();
}

class _DuplicateSeriesSheetState extends State<_DuplicateSeriesSheet> {
  DateTimeRange? _dateRange;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  final bool _loading = false;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay(
      hour: widget.sourceClass.startTime.hour,
      minute: widget.sourceClass.startTime.minute,
    );
    _endTime = TimeOfDay(
      hour: widget.sourceClass.endTime.hour,
      minute: widget.sourceClass.endTime.minute,
    );
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

  String _weekdaysLabel(List<int> days) {
    if (days.isEmpty) return '—';
    final sorted = [...days]..sort();
    return sorted.map((d) => _dayNames[(d - 1).clamp(0, 6)]).join(' · ');
  }

  int _weeksCount() {
    if (_dateRange == null) return 0;
    return (_dateRange!.end.difference(_dateRange!.start).inDays / 7).ceil() +
        1;
  }

  bool get _startBeforeEnd {
    final startMins = _startTime.hour * 60 + _startTime.minute;
    final endMins = _endTime.hour * 60 + _endTime.minute;
    return startMins < endMins;
  }

  bool get _canSubmit => _dateRange != null && _startBeforeEnd && !_loading;

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      initialDateRange: _dateRange,
      helpText: 'Select new series date range',
      saveText: 'Confirm',
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      helpText: isStart ? 'Start time' : 'End time',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(_DuplicateSeriesResult(
      dateRange: _dateRange!,
      startTime: _startTime,
      endTime: _endTime,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final src = widget.sourceClass;
    final weeks = _weeksCount();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.content_copy_outlined,
                      color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.tr('Duplicate Series'),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                      Text(context.l10n.tr('Create a copy with a new schedule'),
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Source info card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          Color(src.classColorValue ?? cs.primary.toARGB32()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(src.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          _weekdaysLabel(src.repeatWeekdays),
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${DateFormat('HH:mm').format(src.startTime)} – ${DateFormat('HH:mm').format(src.endTime)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Date range section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.tr('Date Range'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickDateRange,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _dateRange != null
                          ? cs.primary.withValues(alpha: 0.06)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _dateRange != null
                            ? cs.primary.withValues(alpha: 0.4)
                            : cs.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.date_range_outlined,
                            size: 20,
                            color: _dateRange != null
                                ? cs.primary
                                : cs.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dateRange == null
                              ? Text(
                                  context.l10n.tr('Tap to select date range'),
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant, fontSize: 14))
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_formatDate(_dateRange!.start)}  →  ${_formatDate(_dateRange!.end)}',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface),
                                    ),
                                    if (weeks > 0)
                                      Text(
                                          '$weeks ${context.l10n.tr(weeks == 1 ? 'week' : 'weeks')}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: cs.onSurfaceVariant)),
                                  ],
                                ),
                        ),
                        Icon(Icons.chevron_right,
                            color: cs.onSurfaceVariant, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Time slot section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.tr('Time Slot'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _TimePickerTile(
                        label: context.l10n.tr('Start'),
                        time: _startTime,
                        onTap: () => _pickTime(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimePickerTile(
                        label: context.l10n.tr('End'),
                        time: _endTime,
                        onTap: () => _pickTime(isStart: false),
                        hasError: !_startBeforeEnd,
                      ),
                    ),
                  ],
                ),
                if (!_startBeforeEnd)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      context.l10n.tr('End time must be after start time'),
                      style: TextStyle(fontSize: 12, color: cs.error),
                    ),
                  ),
              ],
            ),
          ),

          // Preview banner
          if (_dateRange != null && _startBeforeEnd) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${context.l10n.tr('Will create')} $weeks ${context.l10n.tr(weeks == 1 ? 'week' : 'weeks')} ${context.l10n.tr('of')} "${src.title}" · ${_formatTime(_startTime)} – ${_formatTime(_endTime)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Submit button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _canSubmit ? _submit : null,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.content_copy_outlined, size: 18),
                label: Text(context.l10n.tr('Duplicate Series'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  const _TimePickerTile({
    required this.label,
    required this.time,
    required this.onTap,
    this.hasError = false,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;
  final bool hasError;

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: hasError
              ? cs.error.withValues(alpha: 0.06)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasError
                ? cs.error.withValues(alpha: 0.5)
                : cs.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: hasError ? cs.error : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time_outlined,
                    size: 16, color: hasError ? cs.error : cs.primary),
                const SizedBox(width: 6),
                Text(_fmt(time),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: hasError ? cs.error : cs.onSurface)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waitlist section (admin view)
// ─────────────────────────────────────────────────────────────────────────────

class _WaitlistSection extends StatefulWidget {
  const _WaitlistSection({
    required this.entries,
    required this.classId,
    required this.gymClass,
    required this.bookingService,
  });

  final List<WaitlistEntry> entries;
  final String classId;
  final GymClass gymClass;
  final BookingService bookingService;

  @override
  State<_WaitlistSection> createState() => _WaitlistSectionState();
}

class _WaitlistSectionState extends State<_WaitlistSection> {
  bool _promoting = false;

  Future<void> _promote() async {
    setState(() => _promoting = true);
    try {
      await widget.bookingService.promoteFirstWaitlisted(widget.classId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.entries.first.memberName.isNotEmpty ? widget.entries.first.memberName : 'Member'} has been moved from the waitlist to the class.'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _promoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFull = widget.gymClass.capacity > 0 &&
        widget.gymClass.bookedCount >= widget.gymClass.capacity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded,
                  size: 14, color: Color(0xFFF97316)),
              const SizedBox(width: 6),
              Text(
                'WAITLIST (${widget.entries.length})',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Color(0xFFF97316),
                ),
              ),
              const Spacer(),
              // "Promote #1" button — disabled while full or while loading
              FilledButton.icon(
                onPressed: _promoting || isFull ? null : _promote,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: _promoting
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.arrow_upward_rounded, size: 14),
                label: Text(
                  isFull ? 'Class full' : 'Promote #1',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        // ── Entries list ────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < widget.entries.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      color: cs.outline.withValues(alpha: 0.1),
                      indent: 48),
                _WaitlistRow(
                  entry: widget.entries[i],
                  position: i + 1,
                  isFirst: i == 0,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WaitlistRow extends StatelessWidget {
  const _WaitlistRow({
    required this.entry,
    required this.position,
    required this.isFirst,
  });

  final WaitlistEntry entry;
  final int position;
  final bool isFirst;

  String get _name => entry.memberName.isNotEmpty
      ? entry.memberName
      : 'Member ${entry.userId.substring(0, 6)}';

  String get _initials {
    final n = _name.trim();
    if (n.isEmpty) return '?';
    return n
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final joined = DateFormat('d MMM, HH:mm').format(entry.createdAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Position badge
          SizedBox(
            width: 24,
            child: Text(
              '#$position',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isFirst
                    ? const Color(0xFFF97316)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          CircleAvatar(
            radius: 15,
            backgroundColor: isFirst
                ? const Color(0xFFF97316).withValues(alpha: 0.18)
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
            child: Text(
              _initials,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isFirst
                    ? const Color(0xFFF97316)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Joined $joined',
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (isFirst)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'Next',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF97316),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
