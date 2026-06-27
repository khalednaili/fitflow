import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/crash_logger.dart';
import '../../utils/download_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExportDataDialog
// Fetches gym data from Firestore and lets the admin download / copy it as JSON.
// ─────────────────────────────────────────────────────────────────────────────

class ExportDataDialog extends StatefulWidget {
  const ExportDataDialog({
    super.key,
    required this.gymId,
    this.firestore,
  });

  final String gymId;
  final FirebaseFirestore? firestore;

  @override
  State<ExportDataDialog> createState() => _ExportDataDialogState();
}

class _ExportDataDialogState extends State<ExportDataDialog>
    with SingleTickerProviderStateMixin {
  // ── Theme ─────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF0A1F1A);
  static const _surface = Color(0xFF0D2920);
  static const _card = Color(0xFF112820);
  static const _border = Color(0xFF1A3530);
  static const _accent = Color(0xFF10B981);
  static const _textSub = Color(0xFF9CA3AF);
  static const _blue = Color(0xFF3B82F6);

  late final TabController _tabCtrl = TabController(length: 4, vsync: this);
  late final FirebaseFirestore _db =
      widget.firestore ?? FirebaseFirestore.instance;

  bool _loading = false;
  String? _exportJson;
  int _recordCount = 0;
  String? _error;

  // ── Tab config ────────────────────────────────────────────────────────────

  static const _tabDefs = [
    (label: 'Classes',  icon: Icons.fitness_center_outlined,        collection: 'classes'),
    (label: 'WODs',     icon: Icons.local_fire_department_outlined,  collection: 'wods'),
    (label: 'Members',  icon: Icons.group_outlined,                  collection: 'users'),
    (label: 'Bookings', icon: Icons.event_available_outlined,        collection: 'bookings'),
  ];

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Fetch & convert ───────────────────────────────────────────────────────

  Future<void> _export() async {
    setState(() {
      _loading = true;
      _exportJson = null;
      _error = null;
      _recordCount = 0;
    });

    try {
      final tab = _tabDefs[_tabCtrl.index];
      final query = _db
          .collection(tab.collection)
          .where('gymId', isEqualTo: widget.gymId);

      final snap = await query.get();
      final records = snap.docs.map((doc) {
        final raw = Map<String, dynamic>.from(doc.data());
        raw['_sourceId'] = doc.id; // preserve original Firestore ID
        return _serializeDoc(raw);
      }).toList();

      final json = const JsonEncoder.withIndent('  ').convert(records);
      if (mounted) {
        setState(() {
          _exportJson = json;
          _recordCount = records.length;
          _loading = false;
        });
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'exportDataDialog');
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  /// Recursively converts Firestore types to plain JSON-serialisable values.
  dynamic _serializeDoc(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _serializeDoc(val)));
    }
    if (v is List) return v.map(_serializeDoc).toList();
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    if (v is GeoPoint) return {'lat': v.latitude, 'lng': v.longitude};
    if (v is DocumentReference) return v.path;
    return v;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _copyToClipboard() async {
    if (_exportJson == null) return;
    await Clipboard.setData(ClipboardData(text: _exportJson!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.l10n.tr('Copied to clipboard')),
      backgroundColor: _accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _download() {
    if (_exportJson == null) return;
    final tab = _tabDefs[_tabCtrl.index];
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final filename = '${widget.gymId}_${tab.collection}_$date.json';

    if (kIsWeb) {
      triggerJsonDownload(_exportJson!, filename);
    } else {
      // On mobile/desktop: copy to clipboard as fallback
      _copyToClipboard();
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        child: Column(
          children: [
            _buildHeader(context),
            _buildTabs(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInfoRow(context),
                    const SizedBox(height: 14),
                    _buildExportButton(context),
                    if (_loading) ...[
                      const SizedBox(height: 20),
                      _buildLoadingIndicator(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _buildErrorBanner(),
                    ],
                    if (_exportJson != null) ...[
                      const SizedBox(height: 14),
                      _buildResultBanner(context),
                      const SizedBox(height: 10),
                      _buildJsonPreview(),
                      const SizedBox(height: 14),
                      _buildDownloadRow(context),
                    ],
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
              color: _blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.download_outlined, color: _blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr('Export Gym Data'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800),
                ),
                Text(
                  context.l10n.tr(
                      'Download gym data as JSON — compatible with Import'),
                  style: const TextStyle(color: _textSub, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                _loading ? null : () => Navigator.of(context).pop(),
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
          _exportJson = null;
          _error = null;
          _recordCount = 0;
        }),
        labelColor: _blue,
        unselectedLabelColor: _textSub,
        indicatorColor: _blue,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: _border,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: _tabDefs
            .map((t) => Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon, size: 14),
                      const SizedBox(width: 6),
                      Text(context.l10n.tr(t.label)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context) {
    final tab = _tabDefs[_tabCtrl.index];
    final notes = <String, String>{
      'classes':
          'All scheduled classes for gym "${widget.gymId}". Compatible with Import → Classes.',
      'wods':
          'All WOD entries for gym "${widget.gymId}". Compatible with Import → WODs.',
      'users':
          'Member profiles — no passwords or auth tokens are exported.',
      'bookings':
          'All booking records. userId references existing member accounts.',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _blue.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF60A5FA), size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              notes[tab.collection] ?? '',
              style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton(BuildContext context) {
    return FilledButton.icon(
      onPressed: _loading ? null : _export,
      icon: _loading
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.cloud_download_outlined, size: 16),
      label: Text(
        _loading
            ? context.l10n.tr('Fetching…')
            : context.l10n.tr('Fetch & Export'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: _blue,
        disabledBackgroundColor: _border,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Column(
      children: [
        const LinearProgressIndicator(
          backgroundColor: _surface,
          valueColor: AlwaysStoppedAnimation<Color>(_blue),
          minHeight: 3,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.tr('Fetching records from Firestore…'),
          style: const TextStyle(color: _textSub, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildResultBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: _accent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n
                  .tr('$_recordCount record(s) exported successfully'),
              style: const TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: Color(0xFFEF4444), size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFEF4444), fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildJsonPreview() {
    // Show at most ~60 lines in the preview box.
    final lines = _exportJson!.split('\n');
    final preview = lines.length > 60
        ? '${lines.take(60).join('\n')}\n\n// … ${lines.length - 60} more lines (copy or download to see all)'
        : _exportJson!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.tr('Preview'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _border),
              ),
              child: Text(
                '${_exportJson!.length ~/ 1024} KB',
                style: const TextStyle(color: _textSub, fontSize: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              preview,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadRow(BuildContext context) {
    return Row(
      children: [
        // Close
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: _textSub,
            side: const BorderSide(color: _border),
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(context.l10n.tr('Close')),
        ),
        const SizedBox(width: 10),
        // Copy
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _copyToClipboard,
            icon: const Icon(Icons.copy_outlined, size: 15),
            label: Text(context.l10n.tr('Copy JSON')),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(color: _accent.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        // Download (shown on all platforms; on mobile it falls back to copy)
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: _download,
            icon: Icon(
              kIsWeb
                  ? Icons.download_rounded
                  : Icons.copy_all_outlined,
              size: 15,
            ),
            label: Text(
              kIsWeb
                  ? context.l10n.tr('Download .json')
                  : context.l10n.tr('Copy to Clipboard'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
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
