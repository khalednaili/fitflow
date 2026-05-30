import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';

import '../../../models/class_template.dart';
import '../../../models/membership_plan.dart';
import '../../../services/class_template_service.dart';
import '../../../services/subscription_service.dart';
import '../select_coaches_screen.dart';

// ── Days of the week ──────────────────────────────────────────────────────────
List<String> _dayLabels(AppLocalizations l10n) => [
  '',
  l10n.tr('Monday'),
  l10n.tr('Tuesday'),
  l10n.tr('Wednesday'),
  l10n.tr('Thursday'),
  l10n.tr('Friday'),
  l10n.tr('Saturday'),
  l10n.tr('Sunday'),
];

// ── Main tab ──────────────────────────────────────────────────────────────────

class AdminTemplatesTab extends StatefulWidget {
  const AdminTemplatesTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminTemplatesTab> createState() => _AdminTemplatesTabState();
}

class _AdminTemplatesTabState extends State<AdminTemplatesTab> {
  late final _svc = ClassTemplateService(gymId: widget.gymId);

  // ── Generate week dialog ──────────────────────────────────────────────────

  Future<void> _showGenerateDialog() async {
    final l10n = context.l10n;
    DateTime picked = DateTime.now();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _GenerateWeekDialog(
        initial: picked,
        onGenerate: (date) async {
          final messenger = ScaffoldMessenger.of(context);
          final count = await _svc.generateWeek(date);
          messenger.showSnackBar(SnackBar(
            content: Text(count == 0
                ? l10n.tr('All classes already exist for this week.')
                : '$count ${l10n.tr('class(es) generated ✓')}'),
            backgroundColor: count == 0 ? null : Colors.green,
          ));
        },
      ),
    );
  }

  Future<void> _deleteTemplate(String id) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('Delete template?')),
        content: Text(l10n.tr('This will not remove already-generated classes.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.tr('Cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.tr('Delete'))),
        ],
      ),
    );
    if (ok == true) await _svc.delete(id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final dayLabels = _dayLabels(l10n);
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: StreamBuilder<List<ClassTemplate>>(
        stream: _svc.streamAll(),
        builder: (context, snap) {
          final templates = snap.data ?? [];

          // Group by day
          final byDay = <int, List<ClassTemplate>>{};
          for (final t in templates) {
            byDay.putIfAbsent(t.dayOfWeek, () => []).add(t);
          }
          final sortedDays = byDay.keys.toList()..sort();

          return CustomScrollView(
            slivers: [
              // ── Header banner ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.primary.withAlpha(200)],
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
                            Text(l10n.tr('Weekly Templates'),
                                style: TextStyle(
                                    color: cs.onPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              '${templates.length} ${l10n.tr(templates.length == 1 ? 'template' : 'templates')} · ${templates.where((t) => t.active).length} ${l10n.tr('active')}',
                              style: TextStyle(
                                  color: cs.onPrimary.withAlpha(200),
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.onPrimary,
                          foregroundColor: cs.primary,
                        ),
                        onPressed: _showGenerateDialog,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(l10n.tr('Generate Week')),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Empty state ───────────────────────────────────────────
              if (templates.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_view_week_outlined,
                            size: 64, color: cs.onSurface.withAlpha(60)),
                        const SizedBox(height: 16),
                        Text(l10n.tr('No templates yet'),
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withAlpha(100))),
                        const SizedBox(height: 8),
                        Text(l10n.tr('Tap + to create a weekly recurring class.'),
                            style:
                                TextStyle(color: cs.onSurface.withAlpha(80))),
                      ],
                    ),
                  ),
                ),

              // ── Day sections ──────────────────────────────────────────
              for (final day in sortedDays) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      dayLabels[day],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final t = byDay[day]![i];
                      return _TemplateCard(
                        template: t,
                        onEdit: () => _showEditor(existing: t),
                        onDelete: () => _deleteTemplate(t.id),
                        onToggle: (v) => _svc.toggleActive(t.id, v),
                      );
                    },
                    childCount: byDay[day]!.length,
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: Text(l10n.tr('New Template')),
      ),
    );
  }

  Future<void> _showEditor({ClassTemplate? existing}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TemplateEditorDialog(
        existing: existing,
        gymId: widget.gymId,
        service: _svc,
      ),
    );
  }
}

// ── Template card ─────────────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final ClassTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final color = template.classColorValue != null
        ? Color(template.classColorValue!)
        : cs.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: template.active ? color.withAlpha(60) : cs.outlineVariant,
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
          // Color stripe
          Container(
            width: 5,
            height: 72,
            decoration: BoxDecoration(
              color: template.active ? color : cs.outlineVariant,
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(14)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(template.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      if (!template.active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(l10n.tr('Inactive'),
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 13, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(template.timeLabel,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                      const SizedBox(width: 12),
                      Icon(Icons.people_outline,
                          size: 13, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('${template.capacity}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                  if (template.coachNames.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.sports_outlined,
                            size: 13, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(template.coachNames.join(', '),
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Actions
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: template.active,
                onChanged: onToggle,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit,
                    tooltip: l10n.tr('Edit'),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                    onPressed: onDelete,
                    tooltip: l10n.tr('Delete'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Generate week dialog ──────────────────────────────────────────────────────

class _GenerateWeekDialog extends StatefulWidget {
  const _GenerateWeekDialog({required this.initial, required this.onGenerate});
  final DateTime initial;
  final Future<void> Function(DateTime) onGenerate;

  @override
  State<_GenerateWeekDialog> createState() => _GenerateWeekDialogState();
}

class _GenerateWeekDialogState extends State<_GenerateWeekDialog> {
  late DateTime _selected;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  DateTime get _monday =>
      _selected.subtract(Duration(days: _selected.weekday - 1));

  String get _weekLabel {
    final m = _monday;
    final sun = m.add(const Duration(days: 6));
    final fmt = DateFormat('MMM d', Localizations.localeOf(context).toLanguageTag());
    return '${fmt.format(m)} – ${fmt.format(sun)}, ${m.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _selected = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.tr('Generate Week')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.tr('Classes will be created for all active templates for the week of:'),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _loading ? null : _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: cs.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _weekLabel,
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: cs.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tr('Existing classes are skipped automatically.'),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(l10n.tr('Cancel')),
        ),
        FilledButton.icon(
          onPressed: _loading
              ? null
              : () async {
                  setState(() => _loading = true);
                  await widget.onGenerate(_selected);
                  // ignore: use_build_context_synchronously
                  if (mounted) Navigator.pop(context);
                },
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome, size: 16),
          label: Text(l10n.tr('Generate')),
        ),
      ],
    );
  }
}

// ── Template editor dialog ────────────────────────────────────────────────────

class _TemplateEditorDialog extends StatefulWidget {
  const _TemplateEditorDialog({
    this.existing,
    required this.gymId,
    required this.service,
  });
  final ClassTemplate? existing;
  final String gymId;
  final ClassTemplateService service;

  @override
  State<_TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<_TemplateEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _capacityCtrl;
  late final TextEditingController _durationCtrl;

  int _dayOfWeek = 1;
  int _startHour = 7;
  int _startMinute = 0;
  List<CoachSelectionResult> _coaches = [];
  List<MembershipPlan> _plans = [];
  List<String> _selectedPlanIds = [];
  bool _active = true;
  bool _saving = false;

  // Offer plans
  late final _subSvc = SubscriptionService(gymId: widget.gymId);

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _descCtrl = TextEditingController(text: t?.description ?? '');
    _capacityCtrl = TextEditingController(text: (t?.capacity ?? 15).toString());
    _durationCtrl =
        TextEditingController(text: (t?.durationMinutes ?? 60).toString());
    if (t != null) {
      _dayOfWeek = t.dayOfWeek;
      _startHour = t.startHour;
      _startMinute = t.startMinute;
      _coaches = List.generate(
          t.coachIds.length,
          (i) => CoachSelectionResult(
              id: t.coachIds[i],
              name: i < t.coachNames.length ? t.coachNames[i] : ''));
      _selectedPlanIds = List.from(t.requiredOfferPlanIds);
      _active = t.active;
    }
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    final plans = await _subSvc.streamPlans().first;
    if (mounted) setState(() => _plans = plans);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _capacityCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCoaches() async {
    final result = await pickCoaches(
      context: context,
      gymId: widget.gymId,
      initialSelection: _coaches,
    );
    if (result != null) setState(() => _coaches = result);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _startHour, minute: _startMinute),
    );
    if (picked != null) {
      setState(() {
        _startHour = picked.hour;
        _startMinute = picked.minute;
      });
    }
  }

  String get _timeDisplay => '${_startHour.toString().padLeft(2, '0')}:'
      '${_startMinute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_coaches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.tr('Please assign at least one coach')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final t = ClassTemplate(
        id: widget.existing?.id ?? '',
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        dayOfWeek: _dayOfWeek,
        startHour: _startHour,
        startMinute: _startMinute,
        durationMinutes: int.tryParse(_durationCtrl.text) ?? 60,
        capacity: int.tryParse(_capacityCtrl.text) ?? 15,
        coachIds: _coaches.map((c) => c.id).toList(),
        coachNames: _coaches.map((c) => c.name).toList(),
        requiredOfferPlanIds: _selectedPlanIds,
        active: _active,
        classColorValue: widget.existing?.classColorValue,
      );
      if (widget.existing == null) {
        await widget.service.create(t);
      } else {
        await widget.service.update(t);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final dayLabels = _dayLabels(l10n);
    final isNew = widget.existing == null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.primary.withAlpha(180)],
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.repeat, color: cs.onPrimary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isNew ? l10n.tr('New Template') : l10n.tr('Edit Template'),
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
            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      TextFormField(
                        controller: _titleCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Class Title'),
                          prefixIcon: Icon(Icons.fitness_center),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? l10n.tr('Class title is required')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      // Description
                      TextFormField(
                        controller: _descCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Description (optional)'),
                          prefixIcon: Icon(Icons.notes),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),

                      // Day + Time row
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _dayOfWeek,
                              decoration: InputDecoration(
                                labelText: l10n.tr('Day'),
                                prefixIcon: Icon(Icons.today),
                              ),
                              items: List.generate(
                                7,
                                (i) => DropdownMenuItem(
                                  value: i + 1,
                                  child: Text(dayLabels[i + 1]),
                                ),
                              ),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _dayOfWeek = v);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: _pickTime,
                              borderRadius: BorderRadius.circular(12),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: l10n.tr('Start Time'),
                                  prefixIcon: Icon(Icons.access_time),
                                ),
                                child: Text(_timeDisplay),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Duration + Capacity row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _durationCtrl,
                              decoration: InputDecoration(
                                labelText: l10n.tr('Duration (min)'),
                                prefixIcon: Icon(Icons.timer),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) => (int.tryParse(v ?? '') ?? 0) <=
                                      0
                                  ? l10n.tr('Duration must be a positive number of minutes')
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _capacityCtrl,
                              decoration: InputDecoration(
                                labelText: l10n.tr('Capacity'),
                                prefixIcon: Icon(Icons.people),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) =>
                                  (int.tryParse(v ?? '') ?? 0) <= 0
                                      ? l10n.tr('Capacity must be at least 1')
                                      : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Coaches
                      _SectionLabel(icon: Icons.sports, label: l10n.tr('Coaches')),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _pickCoaches,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: cs.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _coaches.isEmpty
                              ? Row(
                                  children: [
                                    Icon(Icons.add,
                                        color: cs.primary, size: 20),
                                    const SizedBox(width: 8),
                                    Text(l10n.tr('Select coaches'),
                                        style: TextStyle(color: cs.primary)),
                                  ],
                                )
                              : Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    ..._coaches.map((c) => Chip(
                                          label: Text(c.name),
                                          onDeleted: () => setState(
                                              () => _coaches.remove(c)),
                                          deleteIconColor: cs.error,
                                        )),
                                    ActionChip(
                                      avatar: Icon(Icons.add,
                                          size: 16, color: cs.primary),
                                      label: Text(l10n.tr('Edit')),
                                      onPressed: _pickCoaches,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Required offers
                      if (_plans.isNotEmpty) ...[
                        _SectionLabel(
                            icon: Icons.card_membership,
                            label: l10n.tr('Required Offers')),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _plans.map((p) {
                            final selected = _selectedPlanIds.contains(p.id);
                            return FilterChip(
                              label: Text(p.name),
                              selected: selected,
                              onSelected: (v) => setState(() => v
                                  ? _selectedPlanIds.add(p.id)
                                  : _selectedPlanIds.remove(p.id)),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Active toggle
                      SwitchListTile(
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                        title: Text(l10n.tr('Active')),
                        subtitle: Text(
                            l10n.tr('Only active templates are included when generating a week')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Footer
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
                            ))
                        : const Icon(Icons.save, size: 18),
                    label: Text(isNew ? l10n.tr('Create') : l10n.tr('Save')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: cs.onSurface)),
      ],
    );
  }
}
