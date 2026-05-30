import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/wod_entry.dart';
import '../../services/wod_service.dart';
import '../../l10n/app_localizations.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kTeal = Color(0xFF0F766E);

// Score type metadata
class _ScoreType {
  _ScoreType({
    required this.value,
    required this.label,
    required this.icon,
    required this.hint,
    required this.color,
  });
  final String value;
  final String label;
  final IconData icon;
  final String hint;
  final Color color;
}

List<_ScoreType> _scoreTypes(AppLocalizations l10n) => <_ScoreType>[
  _ScoreType(
    value: 'time',
    label: l10n.tr('Time'),
    icon: Icons.timer_outlined,
    hint: l10n.tr('MM:SS'),
    color: Color(0xFF0F766E),
  ),
  _ScoreType(
    value: 'rounds_reps',
    label: l10n.tr('Rounds+Reps'),
    icon: Icons.repeat_rounded,
    hint: l10n.tr('e.g. 5+12'),
    color: Color(0xFF7C3AED),
  ),
  _ScoreType(
    value: 'reps',
    label: l10n.tr('Reps'),
    icon: Icons.fitness_center_outlined,
    hint: l10n.tr('Total reps'),
    color: Color(0xFFEA580C),
  ),
  _ScoreType(
    value: 'weight',
    label: l10n.tr('Weight'),
    icon: Icons.monitor_weight_outlined,
    hint: l10n.tr('e.g. 80 kg'),
    color: Color(0xFF0369A1),
  ),
  _ScoreType(
    value: 'custom',
    label: l10n.tr('Custom'),
    icon: Icons.edit_note_outlined,
    hint: l10n.tr('Any value'),
    color: Color(0xFF6B7280),
  ),
];

// Feeling data
class _Feeling {
  _Feeling(
      {required this.value,
      required this.emoji,
      required this.label,
      required this.color});
  final int value;
  final String emoji;
  final String label;
  final Color color;
}

List<_Feeling> _feelings(AppLocalizations l10n) => <_Feeling>[
  _Feeling(
      value: 1,
      emoji: '💀',
      label: l10n.tr('Destroyed'),
      color: Color(0xFFDC2626)),
  _Feeling(
      value: 2,
      emoji: '😓',
      label: l10n.tr('Hard'),
      color: Color(0xFFEA580C)),
  _Feeling(
      value: 3,
      emoji: '😐',
      label: l10n.tr('OK'),
      color: Color(0xFFF59E0B)),
  _Feeling(
      value: 4,
      emoji: '💪',
      label: l10n.tr('Strong'),
      color: Color(0xFF16A34A)),
  _Feeling(
      value: 5,
      emoji: '🔥',
      label: l10n.tr('Beast'),
      color: Color(0xFF0F766E)),
];

// ── Entry point ───────────────────────────────────────────────────────────────

class LogScoreScreen extends StatefulWidget {
  const LogScoreScreen({
    super.key,
    required this.wod,
    required this.gymId,
    this.existingScore,
  });

  final WodEntry wod;
  final String gymId;
  final WodScore? existingScore;

  @override
  State<LogScoreScreen> createState() => _LogScoreScreenState();
}

class _LogScoreScreenState extends State<LogScoreScreen> {
  late final _wodService = WodService(gymId: widget.gymId);
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Score type & value
  late String _scoreType;
  // For 'time'
  final _minsCtrl = TextEditingController();
  final _secsCtrl = TextEditingController();
  // For 'rounds_reps'
  final _roundsCtrl = TextEditingController();
  final _extraRepsCtrl = TextEditingController();
  // For 'reps' / 'weight' / 'custom'
  final _scoreCtrl = TextEditingController();
  String _weightUnit = 'kg';

  // Scale & feeling
  late String _scale;
  late int _feeling;

  // Notes
  final _notesCtrl = TextEditingController();

  bool _saving = false;
  bool _wodExpanded = true;

  WodScore? get _existing => widget.existingScore;

  @override
  void initState() {
    super.initState();
    _scoreType = _existing?.scoreType ?? _inferScoreType();
    _scale = _existing?.scale ?? '';
    _feeling = _existing?.feeling ?? 0;
    _notesCtrl.text = _existing?.notes ?? '';

    if (_existing != null) {
      _populateFromExisting(_existing!);
    }
  }

  String _inferScoreType() {
    final fmt = widget.wod.format.toLowerCase();
    if (fmt.contains('time') || fmt.contains('for time')) return 'time';
    if (fmt.contains('amrap')) return 'rounds_reps';
    if (fmt.contains('emom')) return 'reps';
    return 'custom';
  }

  void _populateFromExisting(WodScore s) {
    final raw = s.score;
    switch (s.scoreType) {
      case 'time':
        final parts = raw.split(':');
        if (parts.length == 2) {
          _minsCtrl.text = parts[0];
          _secsCtrl.text = parts[1];
        } else {
          _scoreCtrl.text = raw;
        }
      case 'rounds_reps':
        final parts = raw.split('+');
        if (parts.length == 2) {
          _roundsCtrl.text = parts[0];
          _extraRepsCtrl.text = parts[1];
        } else {
          _scoreCtrl.text = raw;
        }
      case 'weight':
        // Expect "80 kg" or "175 lbs"
        final parts = raw.trim().split(' ');
        if (parts.length == 2) {
          _scoreCtrl.text = parts[0];
          _weightUnit = parts[1];
        } else {
          _scoreCtrl.text = raw;
        }
      default:
        _scoreCtrl.text = raw;
    }
  }

  String _buildScore() {
    switch (_scoreType) {
      case 'time':
        final m = _minsCtrl.text.trim().padLeft(2, '0');
        final s = _secsCtrl.text.trim().padLeft(2, '0');
        return '$m:$s';
      case 'rounds_reps':
        final r = _roundsCtrl.text.trim();
        final e = _extraRepsCtrl.text.trim();
        if (r.isEmpty) return '';
        return e.isEmpty ? r : '$r+$e';
      case 'weight':
        final v = _scoreCtrl.text.trim();
        if (v.isEmpty) return '';
        return '$v $_weightUnit';
      default:
        return _scoreCtrl.text.trim();
    }
  }

  bool get _canSave {
    final s = _buildScore();
    return s.isNotEmpty && s != ':';
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      await _wodService.saveScore(WodScore(
        id: _existing?.id ?? '',
        wodId: widget.wod.id,
        userId: _uid,
        score: _buildScore(),
        notes: _notesCtrl.text.trim(),
        scale: _scale,
        scoreType: _scoreType,
        feeling: _feeling,
      ));
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: Colors.red, size: 32),
        title: Text(context.l10n.tr('Delete score?')),
        content: Text(
            context.l10n.tr('This will permanently remove your logged score.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _wodService.deleteScore(_existing!.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _minsCtrl.dispose();
    _secsCtrl.dispose();
    _roundsCtrl.dispose();
    _extraRepsCtrl.dispose();
    _scoreCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUpdate = _existing != null;
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, isUpdate),
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: width > 700 ? (width - 680) / 2 : 16,
              vertical: 20,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // WOD summary (collapsible)
                _WodSummaryCard(
                  wod: widget.wod,
                  expanded: _wodExpanded,
                  onToggle: () => setState(() => _wodExpanded = !_wodExpanded),
                ),
                SizedBox(height: 16),

                // Score type selector
                _ScoreTypeCard(
                  selected: _scoreType,
                  onChanged: (t) => setState(() {
                    _scoreType = t;
                    // clear inputs on type change
                    _minsCtrl.clear();
                    _secsCtrl.clear();
                    _roundsCtrl.clear();
                    _extraRepsCtrl.clear();
                    _scoreCtrl.clear();
                  }),
                ),
                SizedBox(height: 16),

                // Score input
                _ScoreInputCard(
                  scoreType: _scoreType,
                  minsCtrl: _minsCtrl,
                  secsCtrl: _secsCtrl,
                  roundsCtrl: _roundsCtrl,
                  extraRepsCtrl: _extraRepsCtrl,
                  scoreCtrl: _scoreCtrl,
                  weightUnit: _weightUnit,
                  onWeightUnitChanged: (u) => setState(() => _weightUnit = u),
                ),
                SizedBox(height: 16),

                // Scale selector
                _SectionCard(
                  icon: Icons.military_tech_outlined,
                  title: context.l10n.tr('Scale'),
                  child: _ScaleSelector(
                    selected: _scale,
                    onChanged: (s) => setState(() => _scale = s),
                  ),
                ),
                SizedBox(height: 16),

                // Feeling / RPE
                _SectionCard(
                  icon: Icons.sentiment_satisfied_outlined,
                  title: context.l10n.tr('How did it feel?'),
                  child: _FeelingSelector(
                    selected: _feeling,
                    onChanged: (f) => setState(() => _feeling = f),
                  ),
                ),
                SizedBox(height: 16),

                // Notes
                _SectionCard(
                  icon: Icons.notes_outlined,
                  title: context.l10n.tr('Notes'),
                  child: TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: context.l10n.tr('Any notes about this workout, modifications…'),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Previous scores
                _PreviousScores(
                  wodId: widget.wod.id,
                  userId: _uid,
                  gymId: widget.gymId,
                  existingId: _existing?.id,
                ),
                SizedBox(height: 120),
              ]),
            ),
          ),
        ],
      ),
      // Sticky bottom bar
      bottomNavigationBar: _BottomBar(
        isUpdate: isUpdate,
        canSave: _canSave,
        saving: _saving,
        onSave: _save,
        onDelete: isUpdate ? _delete : null,
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, bool isUpdate) {
    final wod = widget.wod;
    final dateStr = DateFormat('EEE, d MMM').format(wod.date);

    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (widget.existingScore != null)
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.white70, size: 20),
            tooltip: context.l10n.tr('Delete score'),
            onPressed: _delete,
          ),
        SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF064E3B), Color(0xFF0F766E), Color(0xFF059669)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.fromLTRB(20, 70, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      dateStr,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (wod.format.isNotEmpty) ...[
                    SizedBox(width: 8),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        wod.format.toUpperCase(),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 6),
              Text(
                isUpdate ? context.l10n.tr('Update Score') : context.l10n.tr('Log Score'),
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                wod.title.isEmpty ? context.l10n.tr('Workout of the Day') : wod.title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        titlePadding: EdgeInsets.zero,
        expandedTitleScale: 1,
      ),
    );
  }
}

// ── WOD Summary Card ──────────────────────────────────────────────────────────

class _WodSummaryCard extends StatelessWidget {
  const _WodSummaryCard({
    required this.wod,
    required this.expanded,
    required this.onToggle,
  });
  final WodEntry wod;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Gather all exercises (from parts or legacy list)
    final List<WodExercise> exercises = wod.parts.isNotEmpty
        ? wod.parts.expand((p) => p.exercises).toList()
        : wod.exercises;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _kTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.local_fire_department_outlined,
                        size: 16, color: _kTeal),
                  ),
                  SizedBox(width: 10),
                  Text(context.l10n.tr('Workout Details'),
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Spacer(),
                  AnimatedRotation(
                    turns: expanded ? 0 : 0.5,
                    duration: Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_up_rounded,
                        color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          AnimatedSize(
            duration: Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(height: 1),
                      // Meta row
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (wod.format.isNotEmpty)
                              _MetaPill(
                                label: wod.format.toUpperCase(),
                                icon: Icons.repeat_rounded,
                                color: Color(0xFF7C3AED),
                              ),
                            if (wod.timeCap.isNotEmpty)
                              _MetaPill(
                                label: '⏱ ${wod.timeCap}',
                                icon: null,
                                color: Color(0xFFEA580C),
                              ),
                          ],
                        ),
                      ),
                      // Description
                      if (wod.description.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            wod.description,
                            style: TextStyle(
                                fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                        ),
                      // Parts
                      if (wod.parts.isNotEmpty)
                        ...wod.parts.map((p) => _WodPartTile(part: p))
                      else if (exercises.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.tr('EXERCISES'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              SizedBox(height: 8),
                              ...exercises.map((e) => _ExerciseTile(ex: e)),
                            ],
                          ),
                        ),
                      if (wod.parts.isEmpty && exercises.isEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Text(context.l10n.tr('No exercise details.'),
                              style: TextStyle(fontSize: 13)),
                        ),
                    ],
                  )
                : SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

class _WodPartTile extends StatelessWidget {
  const _WodPartTile({required this.part});
  final WodPart part;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(part.title,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              if (part.format.isNotEmpty) ...[
                SizedBox(width: 8),
                _MetaPill(
                    label: part.format.toUpperCase(), color: Color(0xFF7C3AED)),
              ],
              if (part.timeCap.isNotEmpty) ...[
                SizedBox(width: 6),
                _MetaPill(label: '⏱ ${part.timeCap}', color: Color(0xFFEA580C)),
              ],
            ],
          ),
          if (part.description.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(part.description,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ...part.exercises.map((e) => _ExerciseTile(ex: e)),
          SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.ex});
  final WodExercise ex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final detail = ex.shortLabel;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _kTeal.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(ex.name,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          if (detail.isNotEmpty)
            Text(detail,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Score Type Card ───────────────────────────────────────────────────────────

class _ScoreTypeCard extends StatelessWidget {
  const _ScoreTypeCard({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.category_outlined,
                  size: 16, color: cs.onSurfaceVariant),
              SizedBox(width: 8),
              Text(context.l10n.tr('Score Type'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          SizedBox(height: 12),
          // 5-item grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _scoreTypes(context.l10n).map((t) {
              final isSelected = selected == t.value;
              return InkWell(
                onTap: () => onChanged(t.value),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? t.color.withValues(alpha: 0.12)
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? t.color.withValues(alpha: 0.6)
                          : cs.outlineVariant.withValues(alpha: 0.4),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon,
                          size: 16,
                          color: isSelected ? t.color : cs.onSurfaceVariant),
                      SizedBox(width: 6),
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? t.color : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Score Input Card ──────────────────────────────────────────────────────────

class _ScoreInputCard extends StatelessWidget {
  const _ScoreInputCard({
    required this.scoreType,
    required this.minsCtrl,
    required this.secsCtrl,
    required this.roundsCtrl,
    required this.extraRepsCtrl,
    required this.scoreCtrl,
    required this.weightUnit,
    required this.onWeightUnitChanged,
  });
  final String scoreType;
  final TextEditingController minsCtrl;
  final TextEditingController secsCtrl;
  final TextEditingController roundsCtrl;
  final TextEditingController extraRepsCtrl;
  final TextEditingController scoreCtrl;
  final String weightUnit;
  final ValueChanged<String> onWeightUnitChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final types = _scoreTypes(context.l10n);
    final type = types.firstWhere(
      (t) => t.value == scoreType,
      orElse: () => types.last,
    );

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: type.color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: type.color.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: Offset(0, 3)),
        ],
      ),
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: type.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(type.icon, size: 18, color: type.color),
              ),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.tr('Your Score'),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: type.color)),
                  Text(type.hint,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          SizedBox(height: 16),
          _buildInput(context, type),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context, _ScoreType type) {
    final cs = Theme.of(context).colorScheme;

    switch (scoreType) {
      case 'time':
        return Row(
          children: [
            Expanded(
              child: _BigNumberField(
                controller: minsCtrl,
                label: context.l10n.tr('MIN'),
                hint: '00',
                color: type.color,
                maxLength: 2,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(':',
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: type.color)),
            ),
            Expanded(
              child: _BigNumberField(
                controller: secsCtrl,
                label: context.l10n.tr('SEC'),
                hint: '00',
                color: type.color,
                maxLength: 2,
              ),
            ),
          ],
        );

      case 'rounds_reps':
        return Row(
          children: [
            Expanded(
              child: _BigNumberField(
                controller: roundsCtrl,
                label: context.l10n.tr('ROUNDS'),
                hint: '0',
                color: type.color,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('+',
                  style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: type.color.withValues(alpha: 0.6))),
            ),
            Expanded(
              child: _BigNumberField(
                controller: extraRepsCtrl,
                label: context.l10n.tr('REPS'),
                hint: '0',
                color: type.color,
              ),
            ),
          ],
        );

      case 'weight':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _BigNumberField(
                controller: scoreCtrl,
                label: context.l10n.tr('WEIGHT'),
                hint: '0',
                color: type.color,
                allowDecimal: true,
              ),
            ),
            SizedBox(width: 12),
            // kg / lbs toggle
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.tr('UNIT'),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: cs.onSurfaceVariant)),
                SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'kg', label: Text(context.l10n.tr('kg'))),
                    ButtonSegment(
                        value: 'lbs', label: Text(context.l10n.tr('lbs'))),
                  ],
                  selected: {weightUnit},
                  onSelectionChanged: (v) => onWeightUnitChanged(v.first),
                  style: SegmentedButton.styleFrom(
                    selectedForegroundColor: Colors.white,
                    selectedBackgroundColor: type.color,
                  ),
                ),
              ],
            ),
          ],
        );

      case 'reps':
        return _BigNumberField(
          controller: scoreCtrl,
          label: context.l10n.tr('TOTAL REPS'),
          hint: '0',
          color: type.color,
        );

      default:
        return TextField(
          controller: scoreCtrl,
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, color: type.color),
          decoration: InputDecoration(
            hintText: type.hint,
            hintStyle: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w400,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            filled: true,
            fillColor: type.color.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: type.color.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: type.color, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        );
    }
  }
}

class _BigNumberField extends StatelessWidget {
  const _BigNumberField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.color,
    this.maxLength,
    this.allowDecimal = false,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final Color color;
  final int? maxLength;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: cs.onSurfaceVariant)),
        SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
                allowDecimal ? RegExp(r'[\d.]') : RegExp(r'\d')),
            if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
          ],
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w300,
                color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
            filled: true,
            fillColor: color.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color.withValues(alpha: 0.25)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
        ),
      ],
    );
  }
}

// ── Scale Selector ────────────────────────────────────────────────────────────

class _ScaleSelector extends StatelessWidget {
  const _ScaleSelector({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scales = [
      (
        value: '',
        label: context.l10n.tr('Not set'),
        icon: Icons.remove,
        color: Color(0xFF6B7280)
      ),
      (
        value: 'rx',
        label: context.l10n.tr('Rx'),
        icon: Icons.star_rounded,
        color: Color(0xFF0F766E)
      ),
      (
        value: 'scaled',
        label: context.l10n.tr('Scaled'),
        icon: Icons.tune_rounded,
        color: Color(0xFF7C3AED)
      ),
      (
        value: 'masters',
        label: context.l10n.tr('Masters'),
        icon: Icons.workspace_premium_outlined,
        color: Color(0xFFF59E0B)
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: scales.map((s) {
        final isSelected = selected == s.value;
        final color = s.color;
        return InkWell(
          onTap: () => onChanged(s.value),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.12)
                  : Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? color
                    : Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.4),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.icon,
                    size: 15,
                    color: isSelected
                        ? color
                        : Theme.of(context).colorScheme.onSurfaceVariant),
                SizedBox(width: 6),
                Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? color
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Feeling Selector ──────────────────────────────────────────────────────────

class _FeelingSelector extends StatelessWidget {
  const _FeelingSelector({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: _feelings(context.l10n).map((f) {
        final isSelected = selected == f.value;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(isSelected ? 0 : f.value),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 180),
              margin: EdgeInsets.symmetric(horizontal: 3),
              padding: EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? f.color.withValues(alpha: 0.12)
                    : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? f.color
                      : cs.outlineVariant.withValues(alpha: 0.4),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(f.emoji,
                      style: TextStyle(fontSize: isSelected ? 26 : 22)),
                  SizedBox(height: 2),
                  Text(
                    f.label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected ? f.color : cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Section Card wrapper ──────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              SizedBox(width: 8),
              Text(title,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Previous Scores ───────────────────────────────────────────────────────────

class _PreviousScores extends StatelessWidget {
  const _PreviousScores({
    required this.wodId,
    required this.userId,
    required this.gymId,
    this.existingId,
  });
  final String wodId;
  final String userId;
  final String gymId;
  final String? existingId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final svc = WodService(gymId: gymId);

    return StreamBuilder<List<WodScore>>(
      stream: svc.streamScoresForWod(wodId),
      builder: (context, snap) {
        final all = snap.data ?? [];
        // All scores for this WOD, sorted newest first
        final scores = all.where((s) => s.id != (existingId ?? '')).toList()
          ..sort((a, b) {
            final aT = a.loggedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bT = b.loggedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bT.compareTo(aT);
          });

        if (scores.isEmpty) return SizedBox.shrink();

        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Icon(Icons.leaderboard_outlined,
                        size: 16, color: cs.onSurfaceVariant),
                    SizedBox(width: 8),
                    Text(
                      '${context.l10n.tr('Class Leaderboard')} (${scores.length})',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Divider(height: 1),
              ...scores.take(10).map((s) => _ScoreTile(
                    score: s,
                    rank: scores.indexOf(s) + 1,
                    isMe: s.userId == userId,
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({
    required this.score,
    required this.rank,
    required this.isMe,
  });
  final WodScore score;
  final int rank;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateStr = score.loggedAt != null
        ? DateFormat('d MMM').format(score.loggedAt!)
        : '';

    final rankColor = rank == 1
        ? Color(0xFFD97706)
        : rank == 2
            ? Color(0xFF6B7280)
            : rank == 3
                ? Color(0xFFB45309)
                : cs.onSurfaceVariant;

    return Container(
      color: isMe ? _kTeal.withValues(alpha: 0.05) : null,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: rankColor),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 10),
          // Score value
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      score.score,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isMe ? _kTeal : cs.onSurface,
                      ),
                    ),
                    if (score.scale.isNotEmpty) ...[
                      SizedBox(width: 8),
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kTeal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          score.scale.toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _kTeal),
                        ),
                      ),
                    ],
                    if (isMe) ...[
                      SizedBox(width: 8),
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kTeal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context.l10n.tr('YOU'),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: _kTeal),
                        ),
                      ),
                    ],
                  ],
                ),
                if (score.feeling > 0)
                  Text(
                    _feelings(context.l10n)[score.feeling - 1].emoji,
                    style: TextStyle(fontSize: 13),
                  ),
              ],
            ),
          ),
          // Date
          Text(dateStr,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          Divider(),
        ],
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isUpdate,
    required this.canSave,
    required this.saving,
    required this.onSave,
    this.onDelete,
  });
  final bool isUpdate;
  final bool canSave;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    return Container(
      padding: EdgeInsets.fromLTRB(
        width > 700 ? (width - 680) / 2 : 16,
        12,
        width > 700 ? (width - 680) / 2 : 16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (onDelete != null) ...[
            OutlinedButton.icon(
              onPressed: saving ? null : onDelete,
              icon: Icon(Icons.delete_outline, size: 16),
              label: Text(context.l10n.tr('Delete')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade600,
                side: BorderSide(color: Colors.red.shade300),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              ),
            ),
            SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: (canSave && !saving) ? onSave : null,
              icon: saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.onPrimary),
                    )
                  : Icon(isUpdate ? Icons.update_rounded : Icons.save_outlined,
                      size: 18),
              label: Text(
                saving
                    ? context.l10n.tr('Saving…')
                    : isUpdate
                        ? context.l10n.tr('Update Score')
                        : context.l10n.tr('Save Score'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: canSave ? _kTeal : null,
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
