import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/personal_record.dart';
import '../../models/wod_entry.dart';
import '../../services/wod_service.dart';
import '../../services/workout_tracker_service.dart';
import 'log_score_screen.dart';
import '../../l10n/app_localizations.dart';

Color _primaryTeal = Color(0xFF0F766E);
Color _accentOrange = Color(0xFFF97316);

class WorkoutTrackerScreen extends StatefulWidget {
  const WorkoutTrackerScreen({super.key, this.gymId = ''});

  final String gymId;

  @override
  State<WorkoutTrackerScreen> createState() => _WorkoutTrackerScreenState();
}

class _WorkoutTrackerScreenState extends State<WorkoutTrackerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _Header(uid: uid, gymId: widget.gymId),
            ),
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: context.l10n.tr('WOD History')),
                Tab(text: context.l10n.tr('Personal Records')),
              ],
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(2),
              ),
              dividerColor: Colors.transparent,
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _WodHistoryTab(uid: uid, gymId: widget.gymId),
            _PersonalRecordsTab(uid: uid, gymId: widget.gymId),
          ],
        ),
      ),
    );
  }
}

// ── Header with gradient + stats ─────────────────────────────────────────────

class _Header extends StatefulWidget {
  const _Header({required this.uid, required this.gymId});
  final String uid;
  final String gymId;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  late final _wodService = WodService(gymId: widget.gymId);

  int _computeStreak(List<WodScore> scores) {
    if (scores.isEmpty) return 0;
    final days = scores
        .where((s) => s.loggedAt != null)
        .map((s) {
          final d = s.loggedAt!;
          return DateTime(d.year, d.month, d.day);
        })
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (days.isEmpty) return 0;

    int streak = 1;
    for (int i = 1; i < days.length; i++) {
      if (days[i - 1].difference(days[i]).inDays == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  int _thisWeekCount(List<WodScore> scores) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    return scores
        .where((s) => s.loggedAt != null && !s.loggedAt!.isBefore(weekStart))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WodScore>>(
      stream: _wodService.streamScoresForUser(widget.uid),
      builder: (context, snap) {
        final scores = snap.data ?? [];
        final total = scores.length;
        final thisWeek = _thisWeekCount(scores);
        final streak = _computeStreak(scores);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryTeal, _accentOrange],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.fromLTRB(20, 60, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.tr('My Progress'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                context.l10n.tr('Workout Tracker'),
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              SizedBox(height: 14),
              Row(
                children: [
                  _StatChip(label: context.l10n.tr('Total Logged'), value: '$total'),
                  SizedBox(width: 10),
                  _StatChip(label: context.l10n.tr('This Week'), value: '$thisWeek'),
                  SizedBox(width: 10),
                  _StatChip(label: context.l10n.tr('Best Streak'), value: '${streak}d'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(50)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ── WOD History tab ──────────────────────────────────────────────────────────

class _WodHistoryTab extends StatefulWidget {
  const _WodHistoryTab({required this.uid, required this.gymId});
  final String uid;
  final String gymId;

  @override
  State<_WodHistoryTab> createState() => _WodHistoryTabState();
}

class _WodHistoryTabState extends State<_WodHistoryTab> {
  late final _wodService = WodService(gymId: widget.gymId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WodScore>>(
      stream: _wodService.streamScoresForUser(widget.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        final scores = snap.data ?? [];
        if (scores.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sports_score_outlined,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withAlpha(100)),
                SizedBox(height: 12),
                Text(
                  context.l10n.tr('No scores logged yet'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 700),
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: scores.length,
              itemBuilder: (ctx, i) => _ScoreCard(
                  score: scores[i], uid: widget.uid, gymId: widget.gymId),
            ),
          ),
        );
      },
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score, required this.uid, required this.gymId});
  final WodScore score;
  final String uid;
  final String gymId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loggedDate = score.loggedAt;
    final dateLabel = loggedDate != null
        ? DateFormat('MMM d, yyyy').format(loggedDate)
        : context.l10n.tr('Unknown date');

    // Load the WOD entry to pass to LogScoreScreen
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future:
          FirebaseFirestore.instance.collection('wods').doc(score.wodId).get(),
      builder: (context, snap) {
        WodEntry? wod;
        if (snap.hasData && snap.data!.exists) {
          wod = WodEntry.fromSnapshot(snap.data!);
        }
        final wodTitle = wod?.title.isNotEmpty == true ? wod!.title : context.l10n.tr('WOD');

        // Scale badge color
        final scaleColor = score.scale == 'rx'
            ? _primaryTeal
            : score.scale == 'scaled'
                ? Color(0xFF7C3AED)
                : score.scale == 'masters'
                    ? Color(0xFFF59E0B)
                    : null;

        // Feeling emoji
        String? feelingEmoji;
        if (score.feeling > 0 && score.feeling <= 5) {
          const emojis = ['💀', '😓', '😐', '💪', '🔥'];
          feelingEmoji = emojis[score.feeling - 1];
        }

        return InkWell(
          onTap: wod == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LogScoreScreen(
                        wod: wod!,
                        gymId: gymId,
                        existingScore: score,
                      ),
                    ),
                  ),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: EdgeInsets.only(bottom: 12),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withAlpha(10),
                    blurRadius: 8,
                    offset: Offset(0, 2)),
              ],
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: score
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date + scale
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(dateLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onPrimaryContainer)),
                          ),
                          if (score.scale.isNotEmpty && scaleColor != null) ...[
                            SizedBox(width: 6),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: scaleColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: scaleColor.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                score.scale.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: scaleColor),
                              ),
                            ),
                          ],
                          if (feelingEmoji != null) ...[
                            SizedBox(width: 6),
                            Text(feelingEmoji, style: TextStyle(fontSize: 14)),
                          ],
                        ],
                      ),
                      SizedBox(height: 6),
                      // WOD title
                      Text(wodTitle,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      SizedBox(height: 4),
                      // Score value
                      Text(
                        score.score,
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: _primaryTeal,
                            letterSpacing: -0.5),
                      ),
                      if (score.notes.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(score.notes,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                // Right: edit arrow
                Icon(Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Personal Records tab ─────────────────────────────────────────────────────

class _PersonalRecordsTab extends StatefulWidget {
  const _PersonalRecordsTab({required this.uid, required this.gymId});
  final String uid;
  final String gymId;

  @override
  State<_PersonalRecordsTab> createState() => _PersonalRecordsTabState();
}

class _PersonalRecordsTabState extends State<_PersonalRecordsTab> {
  late final _trackerService = WorkoutTrackerService();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<PersonalRecord>>(
      stream: _trackerService.streamPRsForUser(widget.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        final prs = snap.data ?? [];
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 700),
            child: Stack(
              children: [
                prs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.emoji_events_outlined,
                                size: 64,
                                color: cs.onSurfaceVariant.withAlpha(100)),
                            SizedBox(height: 12),
                            Text(context.l10n.tr('No personal records yet'),
                                style: TextStyle(color: cs.onSurfaceVariant)),
                            SizedBox(height: 6),
                            Text(
                              context.l10n.tr('Tap + to add your first PR'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant.withAlpha(150)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: prs.length,
                        itemBuilder: (ctx, i) =>
                            _PRCard(pr: prs[i], uid: widget.uid),
                      ),
                Positioned(
                  bottom: 24,
                  right: 16,
                  child: FloatingActionButton.extended(
                    heroTag: 'add_pr_fab',
                    onPressed: () => _showAddEditSheet(
                      context: context,
                      uid: widget.uid,
                    ),
                    icon: Icon(Icons.add),
                    label: Text(context.l10n.tr('Add PR')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PRCard extends StatelessWidget {
  const _PRCard({required this.pr, required this.uid});
  final PersonalRecord pr;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateLabel = DateFormat('MMM d, yyyy').format(pr.achievedAt);

    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(12),
              blurRadius: 10,
              offset: Offset(0, 2)),
        ],
        border: Border.all(color: cs.outline.withAlpha(60)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pr.exerciseName,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _accentOrange.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _accentOrange.withAlpha(80)),
                      ),
                      child: Text(
                        '${pr.value} ${pr.unit}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: _accentOrange),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      dateLabel,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                if (pr.notes.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    pr.notes,
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
            onSelected: (v) async {
              if (v == 'edit') {
                await _showAddEditSheet(
                    context: context, uid: uid, existing: pr);
              } else if (v == 'delete') {
                await WorkoutTrackerService().deletePR(pr.id);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'edit', child: Text(context.l10n.tr('Edit'))),
              PopupMenuItem(
                  value: 'delete', child: Text(context.l10n.tr('Delete'))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Add / Edit PR bottom sheet ────────────────────────────────────────────────

Future<void> _showAddEditSheet({
  required BuildContext context,
  required String uid,
  PersonalRecord? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AddEditPRSheet(uid: uid, existing: existing),
  );
}

class _AddEditPRSheet extends StatefulWidget {
  const _AddEditPRSheet({required this.uid, this.existing});
  final String uid;
  final PersonalRecord? existing;

  @override
  State<_AddEditPRSheet> createState() => _AddEditPRSheetState();
}

class _AddEditPRSheetState extends State<_AddEditPRSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _notesCtrl;
  late String _unit;
  late DateTime _achievedAt;
  bool _saving = false;

  static const _units = ['kg', 'lbs', 'time', 'reps', 'other'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.exerciseName ?? '');
    _valueCtrl = TextEditingController(text: e?.value ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _unit = e?.unit ?? 'kg';
    _achievedAt = e?.achievedAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _achievedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _achievedAt = picked);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final pr = PersonalRecord(
        id: widget.existing?.id ?? '',
        userId: widget.uid,
        exerciseName: _nameCtrl.text.trim(),
        value: _valueCtrl.text.trim(),
        unit: _unit,
        notes: _notesCtrl.text.trim(),
        achievedAt: _achievedAt,
      );
      await WorkoutTrackerService().savePR(pr);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              widget.existing == null
                  ? context.l10n.tr('Add Personal Record')
                  : context.l10n.tr('Edit Personal Record'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                  labelText: context.l10n.tr('Exercise name'),
                  prefixIcon: Icon(Icons.fitness_center)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? context.l10n.tr('Required') : null,
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _valueCtrl,
                    decoration: InputDecoration(
                        labelText: context.l10n.tr('Value'),
                        prefixIcon: Icon(Icons.bar_chart_rounded)),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? context.l10n.tr('Required') : null,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _unit,
                    decoration:
                        InputDecoration(labelText: context.l10n.tr('Unit')),
                    items: _units
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _unit = v);
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                  labelText: context.l10n.tr('Notes (optional)'),
                  prefixIcon: Icon(Icons.notes)),
              maxLines: 2,
            ),
            SizedBox(height: 12),
            // Date picker row
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outline),
                  borderRadius: BorderRadius.circular(12),
                  color: cs.surfaceContainerLowest,
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 18, color: cs.onSurfaceVariant),
                    SizedBox(width: 12),
                    Text(
                      DateFormat('MMM d, yyyy').format(_achievedAt),
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Spacer(),
                    Icon(Icons.edit_calendar_outlined,
                        size: 16, color: cs.primary),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.tr('Cancel')),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(
                            widget.existing == null
                                ? context.l10n.tr('Save PR')
                                : context.l10n.tr('Update PR')),
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
