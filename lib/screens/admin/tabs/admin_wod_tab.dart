import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/class_type.dart';
import '../../../models/wod_entry.dart';
import '../../../services/class_type_service.dart';
import '../../../services/wod_service.dart';

// ── Shared constants ──────────────────────────────────────────────────────────

const _kPartAccents = [
  Color(0xFF2563EB),
  Color(0xFFF97316),
  Color(0xFF7C3AED),
  Color(0xFF059669),
  Color(0xFFDC2626),
  Color(0xFF0891B2),
];

class _FmtMeta {
  const _FmtMeta(this.color, this.icon);
  final Color color;
  final IconData icon;
}

const _kFmtMeta = <String, _FmtMeta>{
  'AMRAP': _FmtMeta(Color(0xFF2563EB), Icons.loop),
  'For Time': _FmtMeta(Color(0xFFF97316), Icons.timer),
  'EMOM': _FmtMeta(Color(0xFF7C3AED), Icons.alarm),
  'Rounds': _FmtMeta(Color(0xFF059669), Icons.refresh),
  'Tabata': _FmtMeta(Color(0xFFDC2626), Icons.electric_bolt),
  'Max Reps': _FmtMeta(Color(0xFF0891B2), Icons.trending_up),
  'Strength': _FmtMeta(Color(0xFF92400E), Icons.fitness_center),
  'Warm-Up': _FmtMeta(Color(0xFF15803D), Icons.directions_run),
  'Mobility': _FmtMeta(Color(0xFF7C3AED), Icons.self_improvement),
};

const _kMeasures = [
  'Time (Speed)',
  'Pounds',
  'Kilos',
  'Reps',
  'Rounds + Reps',
  'Distance',
  'Calories',
  'Load',
];

String _partTitle(AppLocalizations l10n, int index) {
  const labels = ['A', 'B', 'C', 'D', 'E', 'F'];
  final label = index < labels.length ? labels[index] : '${index + 1}';
  return '${l10n.tr('Part')} $label';
}

List<_ScaleData> _defaultScaleData(AppLocalizations l10n) => [
      _ScaleData.empty(l10n.tr('RX')),
      _ScaleData.empty(l10n.tr('INTERMEDIATE')),
      _ScaleData.empty(l10n.tr('SCALED')),
    ];

String _levelLabel(AppLocalizations l10n, int index) =>
    '${l10n.tr('LEVEL')} $index';

class AdminWodTab extends StatelessWidget {
  const AdminWodTab({super.key, required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context) {
    final svc = WodService(gymId: gymId);
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: StreamBuilder<List<WodEntry>>(
        stream: svc.streamRecent(30),
        builder: (context, snap) {
          final wods = snap.data ?? [];
          final isWide = MediaQuery.sizeOf(context).width > 700;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, const Color(0xFFF97316)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.tr('Workouts'),
                              style: TextStyle(
                                color: cs.onPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${wods.length} ${l10n.tr(wods.length == 1 ? 'workout posted' : 'workouts posted')}',
                              style: TextStyle(
                                color: cs.onPrimary.withAlpha(200),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (wods.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fitness_center_outlined,
                          size: 64,
                          color: cs.onSurface.withAlpha(60),
                        ),
                        const SizedBox(height: 16),
                        Text(
              l10n.tr('No workouts yet'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withAlpha(100),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.tr('Tap + to post a workout.'),
                          style: TextStyle(color: cs.onSurface.withAlpha(80)),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  sliver: isWide
                      ? SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _WodAdminCard(
                              wod: wods[i],
                              service: svc,
                              onEdit: () =>
                                  _showEditor(context, svc, existing: wods[i]),
                            ),
                            childCount: wods.length,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 160,
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _WodAdminCard(
                                wod: wods[i],
                                service: svc,
                                onEdit: () => _showEditor(context, svc,
                                    existing: wods[i]),
                              ),
                            ),
                            childCount: wods.length,
                          ),
                        ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, svc),
        icon: const Icon(Icons.add),
        label: Text(l10n.tr('Post Workout')),
      ),
    );
  }

  void _showEditor(BuildContext context, WodService svc, {WodEntry? existing}) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final l10n = context.l10n;
    final dialog = _WodEditorDialog(
      existing: existing,
      service: svc,
      classTypeService: ClassTypeService(gymId: gymId),
      fullscreen: !isWide,
    );

    if (isWide) {
      showDialog<void>(
        context: context,
        builder: (_) => dialog,
      );
      return;
    }

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.tr('Workout editor'),
      barrierColor: Colors.black.withAlpha(120),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => dialog,
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }
}

class _WodAdminCard extends StatelessWidget {
  const _WodAdminCard({
    required this.wod,
    required this.service,
    required this.onEdit,
  });

  final WodEntry wod;
  final WodService service;
  final VoidCallback onEdit;

  Future<void> _delete(BuildContext context) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('Delete workout?')),
        content: Text(
          '${l10n.tr('Delete')} "${wod.title}" ${l10n.tr('for')} ${DateFormat('MMM d').format(wod.date)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (ok == true) await service.delete(wod.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isToday = _isSameDay(wod.date, DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday ? cs.primary.withAlpha(60) : cs.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isToday ? cs.primary : cs.surfaceContainerHighest,
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(14)),
            ),
            child: Column(
              children: [
                Text(
                  wod.date.day.toString(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isToday ? cs.onPrimary : cs.onSurface,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(wod.date),
                  style: TextStyle(
                    fontSize: 11,
                    color: isToday
                        ? cs.onPrimary.withAlpha(200)
                        : cs.onSurfaceVariant,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.onPrimary.withAlpha(60),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.tr('TODAY'),
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wod.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (wod.description.isNotEmpty)
                    Text(
                      wod.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.fitness_center,
                        size: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        wod.parts.isNotEmpty
                            ? '${wod.parts.length} ${l10n.tr(wod.parts.length == 1 ? 'part' : 'parts')}'
                            : '${wod.exercises.length} ${l10n.tr(wod.exercises.length == 1 ? 'exercise' : 'exercises')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (wod.classTypeName.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            wod.classTypeName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                      if (wod.parts.isEmpty && wod.format.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            wod.format,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                      if (wod.timeCap.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.timer_outlined,
                          size: 12,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          wod.timeCap,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.edit_outlined, size: 18, color: cs.primary),
                onPressed: onEdit,
                tooltip: l10n.tr('Edit'),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                onPressed: () => _delete(context),
                tooltip: l10n.tr('Delete'),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _WodEditorDialog extends StatefulWidget {
  const _WodEditorDialog({
    this.existing,
    required this.service,
    required this.classTypeService,
    this.fullscreen = false,
  });

  final WodEntry? existing;
  final WodService service;
  final ClassTypeService classTypeService;
  final bool fullscreen;

  @override
  State<_WodEditorDialog> createState() => _WodEditorDialogState();
}

class _WodEditorDialogState extends State<_WodEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late DateTime _date;
  late List<_PartData> _parts;
  bool _saving = false;
  String _classTypeId = '';
  String _classTypeName = '';
  final _memberNoteCtrl = TextEditingController();
  final _coachNoteCtrl = TextEditingController();

  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;

    final l10n = context.l10n;
    final w = widget.existing;
    _titleCtrl = TextEditingController(text: w?.title ?? '');
    _descCtrl = TextEditingController(text: w?.description ?? '');
    _date = w?.date ?? DateTime.now();
    _classTypeId = w?.classTypeId ?? '';
    _classTypeName = w?.classTypeName ?? '';
    _memberNoteCtrl.text = w?.memberNote ?? '';
    _coachNoteCtrl.text = w?.coachNote ?? '';

    if (w != null && w.parts.isNotEmpty) {
      _parts = w.parts.map(_PartData.fromPart).toList();
    } else if (w != null && w.exercises.isNotEmpty) {
      _parts = [
        _PartData(
          titleCtrl: TextEditingController(text: _partTitle(l10n, 0)),
          descCtrl: TextEditingController(text: w.description),
          timeCapCtrl: TextEditingController(text: w.timeCap),
          format: w.format,
          exercises: w.exercises.map(_ExRow.fromExercise).toList(),
        ),
      ];
    } else {
      _parts = [_PartData.empty(0, l10n)];
    }

    _didInit = true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _memberNoteCtrl.dispose();
    _coachNoteCtrl.dispose();
    for (final p in _parts) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _addPart() =>
      setState(() => _parts.add(_PartData.empty(_parts.length, context.l10n)));

  void _removePart(int i) {
    final part = _parts.removeAt(i);
    part.dispose();
    setState(() {});
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_parts.isEmpty) {
      _showError(context.l10n.tr('Add at least one workout part'));
      return;
    }

    for (int pi = 0; pi < _parts.length; pi++) {
      final part = _parts[pi];
      if (part.titleCtrl.text.trim().isEmpty) {
        _showError(
          '${context.l10n.tr('Part')} ${pi + 1} ${context.l10n.tr('needs a title')}',
        );
        return;
      }

      if (part.useScales) {
        final activeScales = part.scales
            .where((s) => s.labelCtrl.text.trim().isNotEmpty)
            .toList();
        if (activeScales.isEmpty) {
          _showError(
            '${context.l10n.tr('Part')} ${pi + 1} ${context.l10n.tr('needs at least one scaling level')}',
          );
          return;
        }

        for (int si = 0; si < part.scales.length; si++) {
          final scale = part.scales[si];
          final label = scale.labelCtrl.text.trim();
          final hasContent = scale.descCtrl.text.trim().isNotEmpty ||
              scale.exercises.any((e) =>
                  e.name.text.trim().isNotEmpty ||
                  e.sets.text.trim().isNotEmpty ||
                  e.reps.text.trim().isNotEmpty ||
                  e.weight.text.trim().isNotEmpty ||
                  e.notes.text.trim().isNotEmpty);
          if (label.isEmpty && hasContent) {
            _showError(
              '${context.l10n.tr('Scale')} ${si + 1} ${context.l10n.tr('in part')} ${pi + 1} ${context.l10n.tr('needs a label')}',
            );
            return;
          }
          if (label.isEmpty) continue;
          final emptyEx =
              scale.exercises.indexWhere((r) => r.name.text.trim().isEmpty);
          if (emptyEx != -1) {
            _showError(
              '${context.l10n.tr('Exercise name cannot be empty')} (${context.l10n.tr('part')} ${pi + 1}, ${context.l10n.tr('scale')} ${si + 1}, ${context.l10n.tr('exercise')} ${emptyEx + 1})',
            );
            return;
          }
        }
      } else {
        final emptyEx =
            part.exercises.indexWhere((r) => r.name.text.trim().isEmpty);
        if (emptyEx != -1) {
          _showError(
            '${context.l10n.tr('Exercise name cannot be empty')} (${context.l10n.tr('part')} ${pi + 1}, ${context.l10n.tr('exercise')} ${emptyEx + 1})',
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      final duplicate = await widget.service.existsForDateAndType(
        _date,
        _classTypeId,
        excludeId: widget.existing?.id ?? '',
      );
      if (duplicate) {
        if (mounted) {
          setState(() => _saving = false);
          _showError(
              '${context.l10n.tr('A')} "$_classTypeName" ${context.l10n.tr('workout already exists for this date.')}');
        }
        return;
      }

      final parts = _parts.map((p) {
        final scales = p.useScales
            ? p.scales
                .where((s) => s.labelCtrl.text.trim().isNotEmpty)
                .map(
                  (s) => WodScale(
                    label: s.labelCtrl.text.trim(),
                    description: s.descCtrl.text.trim(),
                    exercises: s.exercises
                        .map(
                          (r) => WodExercise(
                            name: r.name.text.trim(),
                            sets: r.sets.text.trim(),
                            reps: r.reps.text.trim(),
                            weight: r.weight.text.trim(),
                            notes: r.notes.text.trim(),
                          ),
                        )
                        .where((e) => e.name.isNotEmpty)
                        .toList(),
                  ),
                )
                .toList()
            : <WodScale>[];

        final exercises = p.useScales
            ? <WodExercise>[]
            : p.exercises
                .map(
                  (r) => WodExercise(
                    name: r.name.text.trim(),
                    sets: r.sets.text.trim(),
                    reps: r.reps.text.trim(),
                    weight: r.weight.text.trim(),
                    notes: r.notes.text.trim(),
                  ),
                )
                .where((e) => e.name.isNotEmpty)
                .toList();

        return WodPart(
          title: p.titleCtrl.text.trim(),
          format: p.format,
          measure: p.measure,
          timeCap: p.timeCapCtrl.text.trim(),
          description: p.descCtrl.text.trim(),
          exercises: exercises,
          scales: scales,
        );
      }).toList();

      final w = WodEntry(
        id: widget.existing?.id ?? '',
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        date: _date,
        exercises: const [],
        createdBy: widget.existing?.createdBy.isNotEmpty == true
            ? widget.existing!.createdBy
            : (FirebaseAuth.instance.currentUser?.uid ?? ''),
        classTypeId: _classTypeId,
        classTypeName: _classTypeName,
        memberNote: _memberNoteCtrl.text.trim(),
        coachNote: _coachNoteCtrl.text.trim(),
        parts: parts,
      );

      if (widget.existing == null) {
        await widget.service.create(w);
      } else {
        await widget.service.update(w);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: context.l10n.tr('Date'),
          prefixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(DateFormat('EEEE, MMM d, y').format(_date)),
      ),
    );
  }

  Widget _buildClassTypeField() {
    return StreamBuilder<List<ClassType>>(
      stream: widget.classTypeService.streamClassTypes(),
      builder: (ctx, snap) {
        final types = snap.data ?? [];
        return DropdownButtonFormField<String>(
          value: _classTypeId.isEmpty ? null : _classTypeId,
          decoration: InputDecoration(
            labelText: context.l10n.tr('Class Type'),
            prefixIcon: const Icon(Icons.category_outlined),
          ),
          hint: Text(context.l10n.tr('Select class type')),
          items: types
              .map(
                (t) => DropdownMenuItem(
                  value: t.id,
                  child: Text(t.name),
                ),
              )
              .toList(),
          onChanged: (val) {
            final picked = types.firstWhere(
              (t) => t.id == val,
              orElse: () => const ClassType(id: '', name: ''),
            );
            setState(() {
              _classTypeId = picked.id;
              _classTypeName = picked.name;
            });
          },
          validator: (v) => (v == null || v.isEmpty)
              ? context.l10n.tr('Please select a class type')
              : null,
        );
      },
    );
  }

  Widget _buildNoteBox({
    required Color tint,
    required IconData icon,
    required String title,
    required String subtitle,
    required String hint,
    required TextEditingController controller,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: tint.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withAlpha(80)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: tint.withAlpha(180),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: null,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: tint.withAlpha(90)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: tint.withAlpha(80)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: tint, width: 1.3),
              ),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: Colors.white.withAlpha(170),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isNew = widget.existing == null;
    final screenHeight = MediaQuery.sizeOf(context).height;

    final content = Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, const Color(0xFFF97316)],
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.fitness_center, color: cs.onPrimary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isNew ? l10n.tr('Post Workout') : l10n.tr('Edit Workout'),
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: cs.onPrimary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWideForm = constraints.maxWidth >= 500;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isWideForm)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildDateField()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildClassTypeField()),
                          ],
                        )
                      else ...[
                        _buildDateField(),
                        const SizedBox(height: 14),
                        _buildClassTypeField(),
                      ],
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _titleCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Workout Title'),
                          prefixIcon: const Icon(Icons.title),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? l10n.tr('Workout title is required')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _descCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Description / Instructions'),
                          prefixIcon: const Icon(Icons.notes),
                        ),
                        minLines: 3,
                        maxLines: null,
                      ),
                      const SizedBox(height: 14),
                      _buildNoteBox(
                        tint: const Color(0xFFF59E0B),
                        icon: Icons.lightbulb_outline,
                        title: l10n.tr('Member Notes · Stimulus'),
                        subtitle: l10n.tr('— visible to members in the workout view'),
                        hint:
                            l10n.tr('STIMULUS, pacing goals, strategy, movement intent…'),
                        controller: _memberNoteCtrl,
                      ),
                      const SizedBox(height: 14),
                      _buildNoteBox(
                        tint: const Color(0xFF854D0E),
                        icon: Icons.lock_outline,
                        title: l10n.tr('Coach Note (private)'),
                        subtitle: l10n.tr('— visible only to coaches & admins'),
                        hint: l10n.tr('Cues, scaling notes, things to watch for…'),
                        controller: _coachNoteCtrl,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(Icons.view_list_outlined,
                              size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(
                            l10n.tr('Workout Parts'),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _addPart,
                            icon: const Icon(Icons.add, size: 16),
                            label: Text(l10n.tr('Add Part')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_parts.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              l10n.tr('Tap "Add Part" to structure your workout'),
                              style: TextStyle(
                                color: cs.onSurface.withAlpha(100),
                              ),
                            ),
                          ),
                        ),
                      ..._parts.asMap().entries.map((entry) {
                        final pi = entry.key;
                        final part = entry.value;
                        return _PartSection(
                          part: part,
                          index: pi,
                          canRemove: _parts.length > 1,
                          onRemove: () => _removePart(pi),
                          onSetState: () => setState(() {}),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(l10n.tr('Cancel')),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(isNew ? l10n.tr('Post') : l10n.tr('Save')),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.fullscreen) {
      return Dialog.fullscreen(child: SafeArea(child: content));
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: math.min(900, screenHeight * 0.92),
        ),
        child: content,
      ),
    );
  }
}

class _ExRow {
  _ExRow({
    required this.name,
    required this.sets,
    required this.reps,
    required this.weight,
    required this.notes,
  });

  factory _ExRow.empty() => _ExRow(
        name: TextEditingController(),
        sets: TextEditingController(),
        reps: TextEditingController(),
        weight: TextEditingController(),
        notes: TextEditingController(),
      );

  factory _ExRow.fromExercise(WodExercise e) => _ExRow(
        name: TextEditingController(text: e.name),
        sets: TextEditingController(text: e.sets),
        reps: TextEditingController(text: e.reps),
        weight: TextEditingController(text: e.weight),
        notes: TextEditingController(text: e.notes),
      );

  final TextEditingController name;
  final TextEditingController sets;
  final TextEditingController reps;
  final TextEditingController weight;
  final TextEditingController notes;

  void dispose() {
    name.dispose();
    sets.dispose();
    reps.dispose();
    weight.dispose();
    notes.dispose();
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.row,
    required this.index,
    required this.onRemove,
  });

  final _ExRow row;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration:
                    BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.name,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Exercise name'),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: cs.error, size: 18),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.sets,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Sets'),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.reps,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Reps'),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.weight,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Weight'),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.notes,
            minLines: 1,
            maxLines: null,
            decoration: InputDecoration(
              labelText: l10n.tr('Notes (optional)'),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartData {
  _PartData({
    required this.titleCtrl,
    required this.descCtrl,
    required this.timeCapCtrl,
    this.format = '',
    this.measure = '',
    this.useScales = false,
    List<_ExRow>? exercises,
    List<_ScaleData>? scales,
  })  : exercises = exercises ?? [],
        scales = scales ?? [];

  factory _PartData.empty(int index, AppLocalizations l10n) {
    return _PartData(
      titleCtrl: TextEditingController(text: _partTitle(l10n, index)),
      descCtrl: TextEditingController(),
      timeCapCtrl: TextEditingController(),
    );
  }

  factory _PartData.fromPart(WodPart p) => _PartData(
        titleCtrl: TextEditingController(text: p.title),
        descCtrl: TextEditingController(text: p.description),
        timeCapCtrl: TextEditingController(text: p.timeCap),
        format: p.format,
        measure: p.measure,
        useScales: p.scales.isNotEmpty,
        exercises: p.exercises.map(_ExRow.fromExercise).toList(),
        scales: p.scales.map(_ScaleData.fromScale).toList(),
      );

  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController timeCapCtrl;
  String format;
  String measure;
  bool useScales;
  final List<_ExRow> exercises;
  final List<_ScaleData> scales;

  void dispose() {
    titleCtrl.dispose();
    descCtrl.dispose();
    timeCapCtrl.dispose();
    for (final r in exercises) {
      r.dispose();
    }
    for (final scale in scales) {
      scale.dispose();
    }
  }
}

class _ScaleData {
  _ScaleData({
    required this.labelCtrl,
    required this.descCtrl,
    List<_ExRow>? exercises,
  }) : exercises = exercises ?? [];

  factory _ScaleData.empty(String label) => _ScaleData(
        labelCtrl: TextEditingController(text: label),
        descCtrl: TextEditingController(),
      );

  factory _ScaleData.fromScale(WodScale s) => _ScaleData(
        labelCtrl: TextEditingController(text: s.label),
        descCtrl: TextEditingController(text: s.description),
        exercises: s.exercises.map(_ExRow.fromExercise).toList(),
      );

  final TextEditingController labelCtrl;
  final TextEditingController descCtrl;
  final List<_ExRow> exercises;

  void dispose() {
    labelCtrl.dispose();
    descCtrl.dispose();
    for (final r in exercises) {
      r.dispose();
    }
  }
}

class _PartSection extends StatelessWidget {
  const _PartSection({
    required this.part,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onSetState,
  });

  final _PartData part;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onSetState;

  static const _labels = ['A', 'B', 'C', 'D', 'E', 'F'];

  String get _label => index < _labels.length ? _labels[index] : '${index + 1}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final accent = _kPartAccents[index % _kPartAccents.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: accent.withAlpha(26),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      _label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: part.titleCtrl,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.tr('Part title…'),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (canRemove)
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                    onPressed: onRemove,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: l10n.tr('Remove part'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FormatPicker(
                  selected: part.format,
                  onChanged: (f) {
                    part.format = f;
                    onSetState();
                  },
                ),
                const SizedBox(height: 12),
                _MeasurePicker(
                  selected: part.measure,
                  onChanged: (measure) {
                    part.measure = measure;
                    onSetState();
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: part.timeCapCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Time Cap (optional)'),
                    prefixIcon: const Icon(Icons.timer_outlined),
                    hintText: l10n.tr('e.g. 20 min'),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: part.descCtrl,
                  minLines: 3,
                  maxLines: null,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Description / Instructions'),
                    prefixIcon: const Icon(Icons.notes),
                    alignLabelWithHint: true,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                Divider(color: cs.outlineVariant),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.layers_outlined, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      l10n.tr('Scaling Levels'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: part.useScales,
                      onChanged: (value) {
                        part.useScales = value;
                        if (value && part.scales.isEmpty) {
                          part.scales.addAll(_defaultScaleData(l10n));
                        }
                        onSetState();
                      },
                    ),
                  ],
                ),
                Text(
                  part.useScales
                      ? l10n.tr('Each level can have its own description and exercises.')
                      : l10n.tr('Use one shared exercise list for this part.'),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (!part.useScales) ...[
                  Row(
                    children: [
                      Icon(Icons.format_list_numbered, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        l10n.tr('Exercises'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          part.exercises.add(_ExRow.empty());
                          onSetState();
                        },
                        icon: const Icon(Icons.add, size: 14),
                        label:
                            Text(l10n.tr('Add'), style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  if (part.exercises.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          l10n.tr('No exercises — optional'),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withAlpha(100),
                          ),
                        ),
                      ),
                    ),
                  ...part.exercises.asMap().entries.map((entry) {
                    final ei = entry.key;
                    final row = entry.value;
                    return _ExerciseRow(
                      row: row,
                      index: ei + 1,
                      onRemove: () {
                        final removed = part.exercises.removeAt(ei);
                        removed.dispose();
                        onSetState();
                      },
                    );
                  }),
                ] else ...[
                  ...part.scales.asMap().entries.map((entry) {
                    final si = entry.key;
                    final scale = entry.value;
                    return _ScaleSection(
                      scale: scale,
                      accent: accent,
                      index: si,
                      canRemove: part.scales.length > 1,
                      onRemove: () {
                        final removed = part.scales.removeAt(si);
                        removed.dispose();
                        onSetState();
                      },
                      onSetState: onSetState,
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        part.scales.add(
                          _ScaleData.empty(_levelLabel(l10n, part.scales.length + 1)),
                        );
                        onSetState();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(l10n.tr('Add Level')),
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

class _ScaleSection extends StatelessWidget {
  const _ScaleSection({
    required this.scale,
    required this.accent,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onSetState,
  });

  final _ScaleData scale;
  final Color accent;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onSetState;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withAlpha(24),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_outlined, size: 14, color: accent),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 80),
                      child: IntrinsicWidth(
                        child: TextField(
                          controller: scale.labelCtrl,
                          decoration: InputDecoration(
                            hintText: l10n.tr('Level'),
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  tooltip: l10n.tr('Remove level'),
                  icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: scale.descCtrl,
            minLines: 3,
            maxLines: null,
            decoration: InputDecoration(
              labelText: l10n.tr('Description'),
              alignLabelWithHint: true,
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.format_list_bulleted, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                l10n.tr('Exercises'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  scale.exercises.add(_ExRow.empty());
                  onSetState();
                },
                icon: const Icon(Icons.add, size: 14),
                label: Text(l10n.tr('Add'), style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          if (scale.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.tr('No exercises yet for this level'),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ...scale.exercises.asMap().entries.map((entry) {
            final ei = entry.key;
            final row = entry.value;
            return _ExerciseRow(
              row: row,
              index: ei + 1,
              onRemove: () {
                final removed = scale.exercises.removeAt(ei);
                removed.dispose();
                onSetState();
              },
            );
          }),
          if (index == 0) const SizedBox.shrink(),
        ],
      ),
    );
  }
}

const _kFormats = [
  'AMRAP',
  'For Time',
  'EMOM',
  'Rounds',
  'Tabata',
  'Max Reps',
  'Strength',
  'Warm-Up',
  'Mobility',
];

class _MeasurePicker extends StatelessWidget {
  const _MeasurePicker({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.straighten, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              l10n.tr('Measure Type'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
            if (selected.isNotEmpty) ...[
              const Spacer(),
              TextButton(
                onPressed: () => onChanged(''),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(l10n.tr('Clear'), style: const TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _kMeasures
              .map(
                (measure) => ChoiceChip(
                  label: Text(measure),
                  selected: selected == measure,
                  onSelected: (_) =>
                      onChanged(selected == measure ? '' : measure),
                  showCheckmark: false,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _FormatPicker extends StatelessWidget {
  const _FormatPicker({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sports_score_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              l10n.tr('Workout Format'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
            if (selected.isNotEmpty) ...[
              const Spacer(),
              TextButton(
                onPressed: () => onChanged(''),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(l10n.tr('Clear'), style: const TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _kFormats.map((format) {
            final meta = _kFmtMeta[format] ??
                const _FmtMeta(Color(0xFF2563EB), Icons.label_outline);
            final isSelected = selected == format;
            return ChoiceChip(
              avatar: Icon(
                meta.icon,
                size: 16,
                color: isSelected ? Colors.white : meta.color,
              ),
              label: Text(format),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : meta.color,
                fontWeight: FontWeight.w700,
              ),
              selected: isSelected,
              selectedColor: meta.color,
              backgroundColor: Colors.transparent,
              side: BorderSide(color: meta.color.withAlpha(110)),
              shape: StadiumBorder(
                  side: BorderSide(color: meta.color.withAlpha(110))),
              onSelected: (_) => onChanged(isSelected ? '' : format),
              showCheckmark: false,
            );
          }).toList(),
        ),
      ],
    );
  }
}
