import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/crash_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ImportDataDialog
// Allows admins to import Classes or WODs from pasted JSON.
// ─────────────────────────────────────────────────────────────────────────────

class ImportDataDialog extends StatefulWidget {
  const ImportDataDialog({
    super.key,
    required this.gymId,
    this.firestore,
  });

  final String gymId;
  final FirebaseFirestore? firestore;

  @override
  State<ImportDataDialog> createState() => _ImportDataDialogState();
}

class _ImportDataDialogState extends State<ImportDataDialog>
    with SingleTickerProviderStateMixin {
  // ── Theme ─────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF0A1F1A);
  static const _surface = Color(0xFF0D2920);
  static const _card = Color(0xFF112820);
  static const _border = Color(0xFF1A3530);
  static const _accent = Color(0xFF10B981);
  static const _textSub = Color(0xFF9CA3AF);
  static const _red = Color(0xFFEF4444);
  static const _amber = Color(0xFFF59E0B);

  late final TabController _tabCtrl =
      TabController(length: 2, vsync: this);
  late final FirebaseFirestore _db =
      widget.firestore ?? FirebaseFirestore.instance;

  final _ctrl = TextEditingController();
  bool _importing = false;
  List<Map<String, dynamic>>? _preview;
  String? _parseError;
  int _imported = 0;

  @override
  void dispose() {
    _tabCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  void _validate() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() {
        _preview = null;
        _parseError = 'Paste JSON content first.';
        _imported = 0;
      });
      return;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) throw const FormatException('Root must be a JSON array [ … ]');
      final list = decoded.cast<Map<String, dynamic>>();
      setState(() {
        _preview = list;
        _parseError = null;
        _imported = 0;
      });
    } catch (e) {
      setState(() {
        _preview = null;
        _parseError = e.toString().replaceFirst('FormatException: ', '');
        _imported = 0;
      });
    }
  }

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _import() async {
    if (_preview == null || _preview!.isEmpty) return;
    setState(() {
      _importing = true;
      _imported = 0;
    });
    try {
      final isClasses = _tabCtrl.index == 0;
      final collection = isClasses ? 'classes' : 'wods';
      final docs = _preview!;

      // Chunk into Firestore batch-write limit of 500
      for (var i = 0; i < docs.length; i += 500) {
        final chunk = docs.sublist(i, i + 500 > docs.length ? docs.length : i + 500);
        final batch = _db.batch();
        for (final raw in chunk) {
          final docRef = _db.collection(collection).doc();
          final payload = isClasses
              ? _toClassPayload(raw)
              : _toWodPayload(raw);
          batch.set(docRef, payload);
        }
        await batch.commit();
        if (mounted) setState(() => _imported += chunk.length);
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'importDataDialog');
      if (mounted) {
        setState(() {
          _parseError = e.toString().replaceFirst('Exception: ', '');
          _importing = false;
        });
        return;
      }
    }
    if (mounted) {
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          context.l10n.tr(
              'Imported $_imported ${_tabCtrl.index == 0 ? 'class' : 'WOD'} record(s) successfully'),
        ),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  // ── Payload builders ──────────────────────────────────────────────────────

  Map<String, dynamic> _toClassPayload(Map<String, dynamic> raw) {
    final startTime = _parseDateTime(raw['startTime']);
    final endTime = _parseDateTime(raw['endTime']) ??
        startTime?.add(const Duration(hours: 1));
    return <String, dynamic>{
      'title': (raw['title'] ?? 'Class') as String,
      'coachName': (raw['coachName'] ?? '') as String,
      'coachIds': _stringList(raw['coachIds']),
      'coachNames': _stringList(raw['coachNames']),
      'description': (raw['description'] ?? '') as String,
      'startTime': startTime != null ? Timestamp.fromDate(startTime) : Timestamp.now(),
      'endTime': endTime != null ? Timestamp.fromDate(endTime) : Timestamp.now(),
      'requiredOfferPlanId': (raw['requiredOfferPlanId'] ?? '') as String,
      'requiredOfferPlanIds': _stringList(raw['requiredOfferPlanIds']),
      'repeatWeekly': (raw['repeatWeekly'] ?? false) as bool,
      'repeatWeekdays': _intList(raw['repeatWeekdays']),
      'capacity': _toInt(raw['capacity'], 16),
      'bookedCount': 0,
      'waitlistCount': 0,
      'gymId': widget.gymId,
      'classColorValue': raw['classColorValue'] as int?,
      'qrToken': (raw['qrToken'] ?? '') as String,
      'dropInEnabled': (raw['dropInEnabled'] ?? false) as bool,
      'dropInPrice': _toDouble(raw['dropInPrice'], 0.0),
      'coachNote': (raw['coachNote'] ?? '') as String,
      'classTypeId': (raw['classTypeId'] ?? '') as String,
    };
  }

  Map<String, dynamic> _toWodPayload(Map<String, dynamic> raw) {
    final date = _parseDate(raw['date']);
    return <String, dynamic>{
      'title': (raw['title'] ?? 'WOD') as String,
      'description': (raw['description'] ?? '') as String,
      'date': date != null ? Timestamp.fromDate(date) : Timestamp.now(),
      'exercises': _rawList(raw['exercises']),
      'createdBy': (raw['createdBy'] ?? 'admin') as String,
      'createdAt': FieldValue.serverTimestamp(),
      'classTypeId': (raw['classTypeId'] ?? '') as String,
      'classTypeName': (raw['classTypeName'] ?? '') as String,
      'format': (raw['format'] ?? '') as String,
      'timeCap': (raw['timeCap'] ?? '') as String,
      'memberNote': (raw['memberNote'] ?? '') as String,
      'coachNote': (raw['coachNote'] ?? '') as String,
      'warmUp': (raw['warmUp'] ?? '') as String,
      'coolDown': (raw['coolDown'] ?? '') as String,
      'gymId': widget.gymId,
      'parts': _rawList(raw['parts']),
    };
  }

  // ── Type helpers ──────────────────────────────────────────────────────────

  DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return DateTime(d.year, d.month, d.day);
    }
    return null;
  }

  List<String> _stringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const <String>[];
  }

  List<int> _intList(dynamic v) {
    if (v is List) return v.whereType<int>().toList();
    return const <int>[];
  }

  List<dynamic> _rawList(dynamic v) {
    if (v is List) return v;
    return const <dynamic>[];
  }

  int _toInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  double _toDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return fallback;
  }

  // ── Templates ─────────────────────────────────────────────────────────────

  String _classesTemplate() {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day + 1, 7, 0);
    final e = d.add(const Duration(hours: 1));
    return const JsonEncoder.withIndent('  ').convert([
      {
        'title': 'WOD',
        'startTime': d.toIso8601String(),
        'endTime': e.toIso8601String(),
        'capacity': 16,
        'description': 'Daily CrossFit class',
        'coachName': '',
        'dropInEnabled': true,
        'dropInPrice': 10.0,
        'classTypeId': '',
      },
    ]);
  }

  String _wodsTemplate() {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day + 1);
    return const JsonEncoder.withIndent('  ').convert([
      {
        'title': 'Fran',
        'date': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        'description': 'Classic benchmark WOD',
        'format': 'For Time',
        'timeCap': '10 min',
        'warmUp': '400m jog, shoulder warm-up',
        'coolDown': 'Shoulder & hip stretches',
        'classTypeName': 'WOD',
        'parts': [
          {
            'title': '21-15-9 For Time',
            'format': 'For Time',
            'timeCap': '10 min',
            'description': 'Three rounds of descending reps',
            'exercises': [
              {'name': 'Thruster', 'sets': '', 'reps': '21-15-9', 'weight': '43 kg / 29 kg', 'notes': ''},
              {'name': 'Pull-up', 'sets': '', 'reps': '21-15-9', 'weight': '', 'notes': ''},
            ],
            'scales': [
              {'label': 'Rx', 'description': '43 kg / 29 kg', 'exercises': []},
              {'label': 'Scaled', 'description': '29 kg / 20 kg, ring rows', 'exercises': []},
            ],
          },
        ],
      },
    ]);
  }

  Future<void> _copyTemplate() async {
    final template =
        _tabCtrl.index == 0 ? _classesTemplate() : _wodsTemplate();
    await Clipboard.setData(ClipboardData(text: template));
    if (!mounted) return;
    _ctrl.text = template;
    _validate();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.l10n.tr('Template loaded in editor')),
      backgroundColor: const Color(0xFF2563EB),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 700),
        child: Column(
          children: [
            _buildHeader(context),
            _buildTabs(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    _buildSchemaHint(),
                    const SizedBox(height: 12),
                    _buildJsonEditor(context),
                    const SizedBox(height: 12),
                    _buildPreviewBanner(),
                    if (_parseError != null) ...[
                      const SizedBox(height: 10),
                      _buildErrorBanner(),
                    ],
                    const SizedBox(height: 16),
                    _buildActions(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.upload_file_outlined, color: _accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr('Import Data'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800),
                ),
                Text(
                  context.l10n.tr('Paste JSON to bulk-import classes or workouts'),
                  style: const TextStyle(color: _textSub, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _importing ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: _textSub),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: _surface,
      child: TabBar(
        controller: _tabCtrl,
        onTap: (_) => setState(() {
          _ctrl.clear();
          _preview = null;
          _parseError = null;
          _imported = 0;
        }),
        labelColor: _accent,
        unselectedLabelColor: _textSub,
        indicatorColor: _accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: _border,
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fitness_center_outlined, size: 15),
                const SizedBox(width: 6),
                Text(context.l10n.tr('Classes')),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department_outlined, size: 15),
                const SizedBox(width: 6),
                Text(context.l10n.tr('WODs')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemaHint() {
    final isClasses = _tabCtrl.index == 0;
    final fields = isClasses
        ? [
            'title', 'startTime (ISO 8601)', 'endTime (ISO 8601)',
            'capacity', 'description', 'coachName',
            'dropInEnabled', 'dropInPrice', 'classTypeId',
          ]
        : [
            'title', 'date (YYYY-MM-DD)', 'description',
            'format', 'timeCap', 'warmUp', 'coolDown',
            'classTypeName', 'parts [ ]',
          ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF60A5FA), size: 14),
              const SizedBox(width: 6),
              Text(
                context.l10n.tr('Expected JSON fields:'),
                style: const TextStyle(
                    color: Color(0xFF60A5FA),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: fields
                .map((f) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(f,
                          style: const TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 10,
                              fontFamily: 'monospace')),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              context.l10n.tr('JSON Content'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _copyTemplate,
              icon: const Icon(Icons.code_outlined, size: 14),
              label: Text(context.l10n.tr('Load Template'),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF60A5FA),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _ctrl,
          maxLines: 12,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: context.l10n.tr('Paste your JSON array here…'),
            hintStyle: TextStyle(color: _textSub, fontSize: 12),
            filled: true,
            fillColor: _card,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accent),
            ),
          ),
          onChanged: (_) => setState(() {
            _preview = null;
            _parseError = null;
            _imported = 0;
          }),
        ),
      ],
    );
  }

  Widget _buildPreviewBanner() {
    if (_preview == null && _imported == 0) return const SizedBox.shrink();

    final isComplete = _imported > 0 && !_importing;
    final color = isComplete ? _accent : _amber;
    final icon =
        isComplete ? Icons.check_circle_outline : Icons.preview_outlined;

    String message;
    if (isComplete) {
      message = context.l10n.tr(
          '$_imported record(s) imported successfully ✓');
    } else if (_importing) {
      message = context.l10n.tr(
          'Importing… $_imported / ${_preview!.length}');
    } else {
      final type = _tabCtrl.index == 0 ? 'class' : 'WOD';
      message =
          context.l10n.tr('${_preview!.length} $type record(s) ready to import');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600))),
          if (_importing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: color),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _red, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_parseError!,
                  style: const TextStyle(color: _red, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final canImport = _preview != null && _preview!.isNotEmpty && !_importing;
    final canValidate = _ctrl.text.trim().isNotEmpty && !_importing;

    return Row(
      children: [
        // Cancel
        OutlinedButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: _textSub,
            side: const BorderSide(color: _border),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(context.l10n.tr('Cancel')),
        ),
        const SizedBox(width: 10),
        // Validate
        OutlinedButton.icon(
          onPressed: canValidate ? _validate : null,
          icon: const Icon(Icons.check_outlined, size: 16),
          label: Text(context.l10n.tr('Validate')),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: BorderSide(
                color: canValidate
                    ? _accent.withValues(alpha: 0.5)
                    : _border),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(width: 10),
        // Import
        Expanded(
          child: FilledButton.icon(
            onPressed: canImport ? _import : null,
            icon: _importing
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_upload_outlined, size: 16),
            label: Text(
              _importing
                  ? context.l10n.tr('Importing…')
                  : context.l10n.tr('Import to Firestore'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              disabledBackgroundColor: _border,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
