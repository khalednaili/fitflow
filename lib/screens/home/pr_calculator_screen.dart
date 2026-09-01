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
        if (mounted) setState(() => _prs = prs);
      });
    }
  }

  @override
  void dispose() {
    _prsSub?.cancel();
    super.dispose();
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
          );
          final calculatorCard = _CalculatorCard(
            prs: _prs,
            defaultUnit: widget.defaultUnit,
          );
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 1000 : 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
                child: isWide
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
  });

  final String uid;
  final ProgressService service;
  final String defaultUnit;

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
              Text(
                l10n.tr('Log a Personal Record'),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: cs.onSurface),
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
  const _CalculatorCard({required this.prs, required this.defaultUnit});

  final List<PersonalRecord> prs;
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
            Text(
              l10n.tr('Percentage Calculator'),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.tr('Select a PR to calculate percentages for it.'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            if (prs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  l10n.tr('Log a PR to use the calculator.'),
                  style: TextStyle(color: cs.onSurfaceVariant),
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
