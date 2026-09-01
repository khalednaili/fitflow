import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/personal_record.dart';
import '../../services/progress_service.dart';
import '../../utils/exercise_list.dart';
import '../../utils/weight_units.dart';

const _kTeal = Color(0xFF0F766E);
const _kOrange = Color(0xFFF97316);

/// Lets a member log a personal record (choosing kg or lb) and calculate
/// what weight to use in a workout for a given percentage of a past PR.
class PersonalRecordsScreen extends StatefulWidget {
  const PersonalRecordsScreen({
    super.key,
    this.gymId = '',
    this.defaultUnit = 'kg',
  });

  final String gymId;

  /// The member's global preferred unit, used as the default for new
  /// entries and for the calculator (overridable in each section).
  final String defaultUnit;

  @override
  State<PersonalRecordsScreen> createState() => _PersonalRecordsScreenState();
}

class _PersonalRecordsScreenState extends State<PersonalRecordsScreen> {
  final _service = ProgressService();
  late final String _uid;
  List<PersonalRecord> _prs = const [];
  bool _loading = true;
  StreamSubscription<List<PersonalRecord>>? _prsSub;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Subscribed once here (rather than via a StreamBuilder further down the
    // tree) so the listener survives layout rebuilds — e.g. `LayoutBuilder`
    // swapping between its Row/Column children when the viewport crosses
    // the wide breakpoint would otherwise tear down and recreate a nested
    // StreamBuilder, which re-subscribes to Firestore's *broadcast* stream
    // and misses the snapshot it already delivered, leaving the calculator
    // permanently empty.
    if (_uid.isNotEmpty) {
      _prsSub = _service.streamPersonalRecords(_uid).listen((prs) {
        if (mounted) {
          setState(() {
            _prs = prs;
            _loading = false;
          });
        }
      });
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _prsSub?.cancel();
    super.dispose();
  }

  /// Forces an immediate one-time refresh of the PR list (in addition to the
  /// passive realtime stream), so the calculator/history reflect a newly
  /// saved or deleted PR right away instead of waiting on listener latency.
  Future<void> _reloadPrs() async {
    if (_uid.isEmpty) return;
    final prs = await _service.fetchPersonalRecords(_uid);
    if (mounted) {
      setState(() {
        _prs = prs;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        title: Text(
          context.l10n.tr('Personal Records'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;
          final logCard = _LogPrCard(
            uid: _uid,
            service: _service,
            defaultUnit: widget.defaultUnit,
            onSaved: _reloadPrs,
          );
          final calculatorCard = _CalculatorCard(
            prs: _prs,
            loading: _loading,
            defaultUnit: widget.defaultUnit,
          );
          final historyCard = _PrHistoryCard(
            prs: _prs,
            loading: _loading,
            service: _service,
            onDeleted: _reloadPrs,
          );
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 1000 : 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: logCard),
                              const SizedBox(width: 20),
                              Expanded(child: calculatorCard),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              logCard,
                              const SizedBox(height: 24),
                              calculatorCard,
                            ],
                          ),
                    const SizedBox(height: 24),
                    historyCard,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Log PR card ──────────────────────────────────────────────────────────────

class _LogPrCard extends StatefulWidget {
  const _LogPrCard({
    required this.uid,
    required this.service,
    required this.defaultUnit,
    this.onSaved,
  });

  final String uid;
  final ProgressService service;
  final String defaultUnit;

  /// Called right after a PR is successfully saved, so the parent can force
  /// an immediate refresh of the list instead of waiting on the passive
  /// realtime stream.
  final VoidCallback? onSaved;

  @override
  State<_LogPrCard> createState() => _LogPrCardState();
}

class _LogPrCardState extends State<_LogPrCard> {
  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();
  TextEditingController? _exerciseController;

  late String _unit = widget.defaultUnit == 'lbs' ? 'lbs' : 'kg';
  DateTime _achievedAt = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _achievedAt,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _achievedAt = picked);
  }

  Future<void> _save() async {
    if (widget.uid.isEmpty) return;
    if (!_formKey.currentState!.validate()) return;
    final exerciseName = _exerciseController?.text.trim() ?? '';
    final weight = double.tryParse(_weightController.text.trim());
    if (exerciseName.isEmpty || weight == null) return;

    setState(() => _isSaving = true);
    final l10n = context.l10n;
    try {
      await widget.service.addPersonalRecord(
        PersonalRecord(
          id: '',
          userId: widget.uid,
          exerciseName: exerciseName,
          value: '${_formatNum(weight)} $_unit',
          unit: _unit,
          notes: _notesController.text.trim(),
          achievedAt: _achievedAt,
        ),
      );
      if (!mounted) return;
      _weightController.clear();
      _exerciseController?.clear();
      _notesController.clear();
      widget.onSaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('Personal record saved'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('Could not save personal record'))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.add_task_rounded, color: _kTeal, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.tr('Log a Personal Record'),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: cs.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  return Autocomplete<String>(
                    optionsBuilder: (textEditingValue) =>
                        searchExercises(textEditingValue.text),
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                      // Keep a reference to the field's own controller so
                      // `_save` can read whatever the member typed or
                      // picked, even a custom exercise name that isn't in
                      // the predefined list.
                      _exerciseController = controller;
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Exercise'),
                          hintText: l10n.tr('Search or type an exercise'),
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? l10n.tr('Please enter an exercise name')
                            : null,
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      // Match the popup width to the field's own width
                      // (rather than a fixed size) so it never overflows a
                      // narrow phone or looks undersized on a wide web
                      // layout.
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height:
                                (options.length * 44.0).clamp(0, 220).toDouble(),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    option,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weightController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l10n.tr('Weight'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        return (n == null || n <= 0)
                            ? l10n.tr('Please enter a valid weight')
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  _UnitToggle(
                    unit: _unit,
                    onChanged: (u) => setState(() => _unit = u),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: l10n.tr('Notes (optional)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.tr('Date achieved'),
                    border: const OutlineInputBorder(),
                  ),
                  child: Text(DateFormat('dd MMM yyyy').format(_achievedAt)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: _kTeal),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(l10n.tr('Save Record')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatNum(double v) =>
    v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

// ── Unit toggle (kg / lb) ────────────────────────────────────────────────────

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.unit, required this.onChanged});

  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'kg', label: Text('kg')),
        ButtonSegment(value: 'lbs', label: Text('lb')),
      ],
      selected: {unit},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(BorderSide(color: _kTeal)),
      ),
    );
  }
}

// ── Percentage calculator card ───────────────────────────────────────────────

const List<int> _kPresetPercentages = [50, 55, 60, 65, 70, 75, 80, 85, 90, 95];

class _CalculatorCard extends StatefulWidget {
  const _CalculatorCard({
    required this.prs,
    required this.loading,
    required this.defaultUnit,
  });

  final List<PersonalRecord> prs;
  final bool loading;
  final String defaultUnit;

  @override
  State<_CalculatorCard> createState() => _CalculatorCardState();
}

class _CalculatorCardState extends State<_CalculatorCard> {
  String? _selectedExercise;
  late String _displayUnit = widget.defaultUnit == 'lbs' ? 'lbs' : 'kg';
  final _customPercentController = TextEditingController();

  @override
  void dispose() {
    _customPercentController.dispose();
    super.dispose();
  }

  /// Latest PR (with a parseable numeric value) per exercise, regardless of
  /// unit — weight (kg/lb), reps, time, or other numeric PRs can all have a
  /// percentage calculated from them.
  Map<String, PersonalRecord> get _calculablePrsByExercise {
    final byExercise = <String, PersonalRecord>{};
    for (final pr in widget.prs) {
      if (parsePrValue(pr.value) == null) continue;
      final existing = byExercise[pr.exerciseName];
      if (existing == null || pr.achievedAt.isAfter(existing.achievedAt)) {
        byExercise[pr.exerciseName] = pr;
      }
    }
    return byExercise;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final prs = _calculablePrsByExercise;
    _selectedExercise ??= prs.keys.isNotEmpty ? prs.keys.first : null;
    final selectedPr =
        _selectedExercise != null ? prs[_selectedExercise] : null;
    final isWeightUnit =
        selectedPr != null && (selectedPr.unit == 'kg' || selectedPr.unit == 'lbs');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calculate_rounded, color: _kTeal, size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.tr('Percentage Calculator'),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: cs.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.tr('Select a PR to calculate percentages for it.'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            if (widget.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else if (prs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_outlined,
                        color: cs.onSurfaceVariant, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.tr('Log a PR to use the calculator.'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedExercise,
                      decoration: InputDecoration(
                        labelText: l10n.tr('Exercise'),
                        border: const OutlineInputBorder(),
                      ),
                      items: prs.keys
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedExercise = v),
                    ),
                  ),
                  if (isWeightUnit) ...[
                    const SizedBox(width: 12),
                    _UnitToggle(
                      unit: _displayUnit,
                      onChanged: (u) => setState(() => _displayUnit = u),
                    ),
                  ],
                ],
              ),
              if (selectedPr != null) ...[
                const SizedBox(height: 12),
                _buildResults(context, selectedPr, isWeightUnit),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, PersonalRecord pr, bool isWeightUnit) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final oneRm = parsePrValue(pr.value)!;
    // Weight PRs convert/round to plate increments; other units (reps, time,
    // etc.) are shown in their own unit with no conversion.
    final oneRmInDisplayUnit = isWeightUnit
        ? roundToPlate(convertWeight(oneRm, pr.unit, _displayUnit), _displayUnit)
        : oneRm;
    final displayUnit = isWeightUnit ? _displayUnit : pr.unit;

    final customPercent = double.tryParse(_customPercentController.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _kTeal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(
                l10n.tr('Current PR'),
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '${_formatNum(oneRmInDisplayUnit)} $displayUnit',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16, color: _kTeal),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._kPresetPercentages.map((pct) {
          final raw = oneRmInDisplayUnit * pct / 100;
          final result = isWeightUnit ? roundToPlate(raw, displayUnit) : raw;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text('$pct%',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: cs.onSurface)),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    color: _kOrange,
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.2),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 64, maxWidth: 100),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_formatNum(result)} $displayUnit',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _customPercentController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.tr('Custom %'),
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  customPercent != null && customPercent > 0
                      ? '${_formatNum(isWeightUnit ? roundToPlate(oneRmInDisplayUnit * customPercent / 100, displayUnit) : oneRmInDisplayUnit * customPercent / 100)} $displayUnit'
                      : '${l10n.tr('Result')}: —',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── PR history list ──────────────────────────────────────────────────────────

/// Shows every PR the member has logged, grouped by exercise (newest first),
/// with the ability to delete an entry.
class _PrHistoryCard extends StatelessWidget {
  const _PrHistoryCard({
    required this.prs,
    required this.loading,
    required this.service,
    this.onDeleted,
  });

  final List<PersonalRecord> prs;
  final bool loading;
  final ProgressService service;

  /// Called right after a PR is successfully deleted, so the parent can
  /// force an immediate refresh instead of waiting on the passive stream.
  final VoidCallback? onDeleted;

  /// Groups PRs by exercise, preserving the incoming (newest-first) order
  /// both across and within groups.
  Map<String, List<PersonalRecord>> get _grouped {
    final map = <String, List<PersonalRecord>>{};
    for (final pr in prs) {
      map.putIfAbsent(pr.exerciseName, () => []).add(pr);
    }
    return map;
  }

  Future<void> _confirmDelete(BuildContext context, PersonalRecord pr) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.tr('Delete personal record?')),
        content: Text(l10n.tr('This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await service.deletePersonalRecord(pr.id);
      onDeleted?.call();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('Personal record deleted'))),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('Could not delete personal record'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final grouped = _grouped;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, color: _kTeal, size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.tr('Your Personal Records'),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: cs.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.tr('All the PRs you have logged, grouped by exercise.'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else if (grouped.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_outlined,
                        color: cs.onSurfaceVariant, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.tr('No personal records logged yet.'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...grouped.entries.map(
                (entry) => _PrHistoryGroup(
                  exerciseName: entry.key,
                  records: entry.value,
                  onDelete: (pr) => _confirmDelete(context, pr),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrHistoryGroup extends StatelessWidget {
  const _PrHistoryGroup({
    required this.exerciseName,
    required this.records,
    required this.onDelete,
  });

  final String exerciseName;
  final List<PersonalRecord> records;
  final ValueChanged<PersonalRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final best = records.first; // already sorted newest-first
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 4, bottom: 8),
        leading: const CircleAvatar(
          radius: 16,
          backgroundColor: Color(0x1AF97316),
          child: Icon(Icons.emoji_events_rounded, color: _kOrange, size: 18),
        ),
        title: Text(exerciseName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${best.value} · ${DateFormat('dd MMM yyyy').format(best.achievedAt)}',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        children: records
            .map((pr) => _PrHistoryRow(
                  pr: pr,
                  isBest: identical(pr, best),
                  onDelete: () => onDelete(pr),
                ))
            .toList(),
      ),
    );
  }
}

class _PrHistoryRow extends StatelessWidget {
  const _PrHistoryRow({
    required this.pr,
    required this.isBest,
    required this.onDelete,
  });

  final PersonalRecord pr;
  final bool isBest;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 36),
          Expanded(
            child: Text(
              pr.notes.isNotEmpty ? '${pr.value}  ·  ${pr.notes}' : pr.value,
              style: TextStyle(
                fontWeight: isBest ? FontWeight.w700 : FontWeight.w400,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            DateFormat('dd MMM yyyy').format(pr.achievedAt),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: cs.error,
            tooltip: l10n.tr('Delete'),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
