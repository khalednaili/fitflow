import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/personal_training.dart';
import '../../../services/member_service.dart';
import '../../../services/personal_training_service.dart';
import '../../../widgets/user_avatar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin / Coach — Private PT tab
// ─────────────────────────────────────────────────────────────────────────────

class AdminPersonalTrainingTab extends StatefulWidget {
  /// When [filterCoachId] is provided, only shows sessions assigned to that coach.
  /// Leave null to show all sessions (admin view).
  const AdminPersonalTrainingTab({
    super.key,
    required this.gymId,
    this.filterCoachId,
  });

  final String gymId;
  final String? filterCoachId;

  @override
  State<AdminPersonalTrainingTab> createState() =>
      _AdminPersonalTrainingTabState();
}

class _AdminPersonalTrainingTabState extends State<AdminPersonalTrainingTab> {
  late final _svc = PersonalTrainingService(gymId: widget.gymId);

  static const _purple = Color(0xFF7C3AED);

  bool get _isFiltered => widget.filterCoachId != null;

  Stream<List<PersonalTraining>> get _stream => _isFiltered
      ? _svc.streamForCoach(widget.filterCoachId!)
      : _svc.streamAll();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.tr('New Session'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => _openEditor(context),
      ),
      body: StreamBuilder<List<PersonalTraining>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snap.data ?? [];

          return CustomScrollView(
            slivers: [
              // ── Header banner ────────────────────────────────────────
              SliverToBoxAdapter(
                child: _PtBanner(
                  count: sessions.length,
                  isFiltered: _isFiltered,
                ),
              ),

              if (sessions.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(onAdd: () => _openEditor(context)),
                )
              else ...[
                // ── Group by upcoming / past ─────────────────────────
                ..._buildSections(context, sessions),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildSections(
      BuildContext context, List<PersonalTraining> sessions) {
    final now = DateTime.now();
    final upcoming = sessions.where((s) => s.startTime.isAfter(now)).toList();
    final past = sessions.where((s) => !s.startTime.isAfter(now)).toList();

    return [
      if (upcoming.isNotEmpty) ...[
        _sectionHeader(context.l10n.tr('Upcoming'), upcoming.length, _purple),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _PtCard(
              session: upcoming[i],
              isPast: false,
              onEdit: () => _openEditor(context, existing: upcoming[i]),
              onDelete: () => _confirmDelete(context, upcoming[i]),
            ),
            childCount: upcoming.length,
          ),
        ),
      ],
      if (past.isNotEmpty) ...[
        _sectionHeader(context.l10n.tr('Past Sessions'), past.length, Colors.grey),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _PtCard(
              session: past[i],
              isPast: true,
              onEdit: () => _openEditor(context, existing: past[i]),
              onDelete: () => _confirmDelete(context, past[i]),
            ),
            childCount: past.length,
          ),
        ),
      ],
    ];
  }

  Widget _sectionHeader(String label, int count, Color color) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {PersonalTraining? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PtEditorSheet(
        existing: existing,
        gymId: widget.gymId,
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, PersonalTraining session) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Text(l10n.tr('Delete session?'), style: const TextStyle(fontSize: 17)),
          ],
        ),
        content: Text(
          '${l10n.tr('Remove')} "${session.title}" ${l10n.tr('on')} '
          '${DateFormat('EEE d MMM').format(session.startTime)} ${l10n.tr('at')} '
          '${DateFormat('HH:mm').format(session.startTime)}?\n\n'
          '${l10n.tr('The members assigned to this session will no longer see it.')}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _svc.delete(session.id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner
// ─────────────────────────────────────────────────────────────────────────────

class _PtBanner extends StatelessWidget {
  const _PtBanner({required this.count, this.isFiltered = false});
  final int count;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.person_outlined,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFiltered
                      ? l10n.tr('My PT Sessions')
                      : l10n.tr('Private Coaching'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count ${l10n.tr(count == 1 ? 'session scheduled' : 'sessions scheduled')}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, color: Colors.white, size: 13),
                const SizedBox(width: 4),
                Text(l10n.tr('Private'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session card
// ─────────────────────────────────────────────────────────────────────────────

class _PtCard extends StatelessWidget {
  const _PtCard({
    required this.session,
    required this.isPast,
    required this.onEdit,
    required this.onDelete,
  });
  final PersonalTraining session;
  final bool isPast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final dur = session.endTime.difference(session.startTime).inMinutes;
    final isToday = DateUtils.isSameDay(session.startTime, DateTime.now());

    return Opacity(
      opacity: isPast ? 0.65 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPast ? cs.outlineVariant : _purple.withValues(alpha: 0.3),
            width: isPast ? 1 : 1.5,
          ),
          boxShadow: isPast
              ? []
              : [
                  BoxShadow(
                    color: _purple.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          children: [
            // ── Top strip: date + actions ────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isPast
                    ? cs.surfaceContainerHighest
                    : _purple.withValues(alpha: 0.07),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(17)),
              ),
              child: Row(
                children: [
                  // Date pill
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPast
                          ? cs.surfaceContainerHighest
                          : _purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: isPast
                              ? cs.outlineVariant
                              : _purple.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 11, color: isPast ? Colors.grey : _purple),
                        const SizedBox(width: 5),
                        Text(
                          isToday
                              ? '${l10n.tr('Today')} · ${DateFormat('HH:mm').format(session.startTime)}'
                              : DateFormat('EEE d MMM · HH:mm')
                                  .format(session.startTime),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isPast ? Colors.grey : _purple),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Duration
                  Text('$dur ${l10n.tr('min')}',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500)),
                  if (isToday) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(l10n.tr('TODAY'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                  const Spacer(),
                  // Edit / delete
                  IconButton(
                    icon: Icon(Icons.edit_outlined,
                        size: 17, color: isPast ? Colors.grey : _purple),
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.tr('Edit'),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 17, color: Colors.red),
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.tr('Delete'),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + PT badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(session.title,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isPast
                                    ? cs.onSurfaceVariant
                                    : cs.onSurface)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(l10n.tr('PT'),
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: _purple)),
                      ),
                    ],
                  ),

                  if (session.location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 13, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(session.location,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Members
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: session.memberNames.map((name) {
                      final initials = _initials(name);
                      return _MemberChip(
                          name: name, initials: initials, isPast: isPast);
                    }).toList(),
                  ),

                  if (session.notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.notes_outlined,
                              size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(session.notes,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                    height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    return parts
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .take(2)
        .join();
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.name,
    required this.initials,
    required this.isPast,
  });
  final String name;
  final String initials;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPast
            ? Colors.grey.withValues(alpha: 0.1)
            : purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isPast
                ? Colors.grey.withValues(alpha: 0.3)
                : purple.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: isPast
                ? Colors.grey.withValues(alpha: 0.3)
                : purple.withValues(alpha: 0.2),
            child: Text(initials,
                style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: isPast ? Colors.grey : purple)),
          ),
          const SizedBox(width: 6),
          Text(name,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isPast ? Colors.grey : purple)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor bottom sheet (also used from coach portal)
// ─────────────────────────────────────────────────────────────────────────────

class PtEditorSheet extends StatefulWidget {
  const PtEditorSheet({super.key, required this.gymId, this.existing});
  final String gymId;
  final PersonalTraining? existing;

  @override
  State<PtEditorSheet> createState() => _PtEditorSheetState();
}

class _PtEditorSheetState extends State<PtEditorSheet> {
  static const _purple = Color(0xFF7C3AED);

  late final _svc = PersonalTrainingService(gymId: widget.gymId);
  late final _memberSvc = MemberService(gymId: widget.gymId);

  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  DateTime _startTime = DateTime.now()
      .add(const Duration(hours: 1))
      .copyWith(minute: 0, second: 0);
  DateTime _endTime = DateTime.now()
      .add(const Duration(hours: 2))
      .copyWith(minute: 0, second: 0);

  final Map<String, String> _selectedMembers = {}; // uid → displayName
  String _selectedCoachId = '';
  String _selectedCoachName = '';
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _notesCtrl.text = e.notes;
      _locationCtrl.text = e.location;
      _startTime = e.startTime;
      _endTime = e.endTime;
      _selectedCoachId = e.coachId;
      _selectedCoachName = e.coachName;
      for (var i = 0; i < e.memberIds.length; i++) {
        _selectedMembers[e.memberIds[i]] =
            i < e.memberNames.length ? e.memberNames[i] : '';
      }
    } else {
      // Default coach = current logged-in user
      final user = FirebaseAuth.instance.currentUser;
      _selectedCoachId = user?.uid ?? '';
      _selectedCoachName = user?.displayName?.isNotEmpty == true
          ? user!.displayName!
          : (user?.email ?? '');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _locationCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _startTime : _endTime;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _purple),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _purple),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startTime = picked;
        if (!_endTime.isAfter(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.l10n.tr('Please enter a session title.'));
      return;
    }
    if (_selectedCoachId.isEmpty) {
      setState(() => _error = context.l10n.tr('Please select a coach.'));
      return;
    }
    if (_selectedMembers.isEmpty) {
      setState(() => _error = context.l10n.tr('Select at least one member.'));
      return;
    }
    if (!_endTime.isAfter(_startTime)) {
      setState(() => _error = context.l10n.tr('End time must be after start time.'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (!_isEditing) {
        await _svc.create(
          title: title,
          coachId: _selectedCoachId,
          coachName: _selectedCoachName,
          memberIds: _selectedMembers.keys.toList(),
          memberNames: _selectedMembers.values.toList(),
          startTime: _startTime,
          endTime: _endTime,
          notes: _notesCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
        );
      } else {
        await _svc.update(
          id: widget.existing!.id,
          title: title,
          memberIds: _selectedMembers.keys.toList(),
          memberNames: _selectedMembers.values.toList(),
          startTime: _startTime,
          endTime: _endTime,
          notes: _notesCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'savePersonalTraining');
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  void _showCoachPicker(BuildContext context, List<AppUser> coaches) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.sports_outlined, color: _purple, size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.tr('Select Coach'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: coaches.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (_, i) {
                    final c = coaches[i];
                    final name =
                        c.displayName.isNotEmpty ? c.displayName : c.email;
                    final initials = name
                        .trim()
                        .split(' ')
                        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
                        .take(2)
                        .join();
                    final isSelected = c.id == _selectedCoachId;
                    return ListTile(
                      leading: UserAvatar(
                        photoUrl: c.photoUrl,
                        initials: initials,
                        color: _purple,
                        radius: 20,
                      ),
                      title: Text(name,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelected ? _purple : null)),
                      subtitle: Text(
                        c.effectiveRoles
                            .map((r) => r[0].toUpperCase() + r.substring(1))
                            .join(' · '),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded,
                              color: _purple)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedCoachId = c.id;
                          _selectedCoachName = name;
                        });
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_purple, Color(0xFF4F46E5)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_outlined,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing
                            ? l10n.tr('Edit Session')
                            : l10n.tr('New Private Session'),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        l10n.tr('Visible only to assigned members'),
                        style:
                            TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Scrollable form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  _FieldLabel(icon: Icons.title, label: l10n.tr('Session Title')),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleCtrl,
                    decoration: _inputDec(hint: l10n.tr('e.g. Strength & Conditioning')),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),

                  // Coach selector
                  _FieldLabel(icon: Icons.sports_outlined, label: l10n.tr('Coach')),
                  const SizedBox(height: 8),
                  StreamBuilder<List<AppUser>>(
                    stream: _memberSvc.streamCoaches(),
                    builder: (context, snap) {
                      final coaches = snap.data ?? [];
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 48,
                          child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (coaches.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(l10n.tr('No coaches found'),
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13)),
                        );
                      }
                      return Column(
                        children: [
                          // Selected coach tile (or prompt)
                          GestureDetector(
                            onTap: () => _showCoachPicker(context, coaches),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: _selectedCoachId.isEmpty
                                        ? Colors.grey.shade300
                                        : _purple.withValues(alpha: 0.5),
                                    width: _selectedCoachId.isEmpty ? 1 : 1.5),
                                borderRadius: BorderRadius.circular(12),
                                color: _selectedCoachId.isEmpty
                                    ? null
                                    : _purple.withValues(alpha: 0.04),
                              ),
                              child: Row(
                                children: [
                                  if (_selectedCoachId.isNotEmpty) ...[
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          _purple.withValues(alpha: 0.15),
                                      child: Text(
                                        _selectedCoachName.isNotEmpty
                                            ? _selectedCoachName[0]
                                                .toUpperCase()
                                            : 'C',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: _purple),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(_selectedCoachName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14)),
                                          Text(l10n.tr('Coach'),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: _purple.withValues(
                                                      alpha: 0.7))),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    Icon(Icons.person_search_outlined,
                                        color: Colors.grey.shade400, size: 20),
                                    const SizedBox(width: 10),
                                    Text(l10n.tr('Select a coach…'),
                                        style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 14)),
                                    const Spacer(),
                                  ],
                                  Icon(Icons.expand_more_rounded,
                                      color: _selectedCoachId.isEmpty
                                          ? Colors.grey.shade400
                                          : _purple,
                                      size: 20),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Date / Time
                  _FieldLabel(
                      icon: Icons.schedule_outlined, label: l10n.tr('Date & Time')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DateTimeTile(
                          label: l10n.tr('Start'),
                          dt: _startTime,
                          color: _purple,
                          onTap: () => _pickDateTime(isStart: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DateTimeTile(
                          label: l10n.tr('End'),
                          dt: _endTime,
                          color: _purple,
                          onTap: () => _pickDateTime(isStart: false),
                        ),
                      ),
                    ],
                  ),

                  // Duration chip
                  const SizedBox(height: 6),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _purple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_endTime.difference(_startTime).inMinutes} ${l10n.tr('min session')}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _purple),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Location
                  _FieldLabel(
                      icon: Icons.place_outlined, label: l10n.tr('Location (optional)')),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _locationCtrl,
                    decoration: _inputDec(hint: l10n.tr('e.g. Main floor, Room B…')),
                  ),
                  const SizedBox(height: 16),

                  // Members
                  _FieldLabel(icon: Icons.group_outlined, label: l10n.tr('Members')),
                  const SizedBox(height: 8),

                  // Selected chips
                  if (_selectedMembers.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedMembers.entries.map((e) {
                        return _SelectedMemberChip(
                          name: e.value,
                          onRemove: () =>
                              setState(() => _selectedMembers.remove(e.key)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Search field
                  TextField(
                    controller: _searchCtrl,
                    decoration: _inputDec(
                      hint: l10n.tr('Search member by name or email…'),
                      prefix: const Icon(Icons.search_rounded, size: 20),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 4),

                  // Member list
                  StreamBuilder<List<AppUser>>(
                    stream: _memberSvc.streamMembers(),
                    builder: (context, snap) {
                      final all = snap.data ?? [];
                      final q = _searchCtrl.text.toLowerCase();
                      final filtered = all.where((m) {
                        if (_selectedMembers.containsKey(m.id)) return false;
                        if (q.isEmpty) return true;
                        return m.displayName.toLowerCase().contains(q) ||
                            m.email.toLowerCase().contains(q);
                      }).toList();

                      if (filtered.isEmpty && q.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      if (filtered.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: Text('${l10n.tr('No members found for')} "$q"',
                                style: TextStyle(
                                    fontSize: 13, color: cs.onSurfaceVariant)),
                          ),
                        );
                      }
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: cs.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: cs.outlineVariant),
                              itemBuilder: (_, i) {
                                final m = filtered[i];
                                final name = m.displayName.isNotEmpty
                                    ? m.displayName
                                    : m.email;
                                final initials = name
                                    .trim()
                                    .split(' ')
                                    .map((w) =>
                                        w.isNotEmpty ? w[0].toUpperCase() : '')
                                    .take(2)
                                    .join();
                                return ListTile(
                                  dense: true,
                                  leading: UserAvatar(
                                    photoUrl: m.photoUrl,
                                    initials: initials,
                                    color: _purple,
                                    radius: 18,
                                  ),
                                  title: Text(name,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(m.email,
                                      style: const TextStyle(fontSize: 11)),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _purple.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(l10n.tr('Add'),
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: _purple)),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _selectedMembers[m.id] = name;
                                      _searchCtrl.clear();
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  _FieldLabel(
                      icon: Icons.notes_outlined,
                      label: l10n.tr('Session Notes (optional)')),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: _inputDec(
                        hint: l10n.tr('Goals, focus areas, equipment needed…')),
                  ),

                  // Error
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.red))),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Footer buttons
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 16 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(l10n.tr('Cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_outline, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _isEditing
                                    ? l10n.tr('Save Changes')
                                    : l10n.tr('Create Session'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ],
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

  InputDecoration _inputDec({String? hint, Widget? prefix}) => InputDecoration(
        hintText: hint,
        prefixIcon: prefix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _purple, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF7C3AED)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7C3AED))),
      ],
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    required this.label,
    required this.dt,
    required this.color,
    required this.onTap,
  });
  final String label;
  final DateTime dt;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.04),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: color)),
            const SizedBox(height: 4),
            Text(DateFormat('EEE d MMM').format(dt),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            Text(DateFormat('HH:mm').format(dt),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.2)),
          ],
        ),
      ),
    );
  }
}

class _SelectedMemberChip extends StatelessWidget {
  const _SelectedMemberChip({required this.name, required this.onRemove});
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: purple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: purple.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: purple)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 12, color: purple),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outlined,
                  size: 52, color: Color(0xFF7C3AED)),
            ),
            const SizedBox(height: 20),
            Text(l10n.tr('No private sessions yet'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              '${l10n.tr('Create a one-on-one or small group session.')} '
              '${l10n.tr('Assigned members will see it in their schedule.')}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.tr('Create First Session'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
