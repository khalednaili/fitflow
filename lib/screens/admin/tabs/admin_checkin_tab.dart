import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:fit_flow/utils/crash_logger.dart';
import '../../../widgets/qr_code_dialog.dart';

class AdminCheckinTab extends StatefulWidget {
  const AdminCheckinTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminCheckinTab> createState() => _AdminCheckinTabState();
}

class _AdminCheckinTabState extends State<AdminCheckinTab> {
  final _firestore = FirebaseFirestore.instance;
  bool _regenerating = false;

  Future<void> _generateOrRegenerate() async {
    setState(() => _regenerating = true);
    try {
      final token = generateGymToken();
      await _firestore
          .collection('settings')
          .doc(widget.gymId.isNotEmpty ? widget.gymId : 'gym')
          .set({'gymQrToken': token, 'gymId': widget.gymId}, SetOptions(merge: true));
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'generateGymQr');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.tr('Failed to generate QR')}: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<bool> _confirmRegenerate() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Regenerate QR Code?')), 
        content: Text(
          context.l10n.tr(
            'The old QR code will stop working immediately.\nMake sure to print or display the new one before your next class.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              child: Text(context.l10n.tr('Regenerate'))),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('settings')
          .doc(widget.gymId.isNotEmpty ? widget.gymId : 'gym')
          .snapshots()
          .cast<DocumentSnapshot<Map<String, dynamic>>>(),
      builder: (context, snap) {
        final token = snap.data?.data()?['gymQrToken'] as String? ?? '';
        final loading = snap.connectionState == ConnectionState.waiting;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Header ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F4C45), Color(0xFF0D7377)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.qr_code_2_rounded,
                              size: 32, color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.tr('Gym Check-in QR'),
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              SizedBox(height: 4),
                              Text(
                                l10n.tr('One QR code for all classes.\nMembers scan it to check in.'),
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── QR display or generate prompt ─────────────────────
                  if (loading)
                    const CircularProgressIndicator()
                  else if (token.isEmpty) ...[
                    Icon(Icons.qr_code_rounded,
                        size: 80,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text(
                      l10n.tr('No QR code yet'),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.tr('Generate your gym QR code once and display it\nat the entrance for members to scan.'),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _regenerating ? null : _generateOrRegenerate,
                      icon: _regenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.qr_code_2_rounded),
                      label: Text(l10n.tr('Generate QR Code')), 
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4C45),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                      ),
                    ),
                  ] else ...[
                    GymQrCodeWidget(gymToken: token),
                    const SizedBox(height: 28),

                    // ── How to use hint ───────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          _HintRow(
                            icon: Icons.print_rounded,
                            text:
                                l10n.tr('Print this QR code and post it at the entrance'),
                          ),
                          const SizedBox(height: 10),
                          _HintRow(
                            icon: Icons.phone_iphone_rounded,
                            text:
                                l10n.tr('Members open their app and tap "Scan" to check in'),
                          ),
                          const SizedBox(height: 10),
                          _HintRow(
                            icon: Icons.timer_outlined,
                            text:
                                l10n.tr('Check-in window: 30 min before → 30 min after class'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Regenerate button ─────────────────────────────
                    OutlinedButton.icon(
                      onPressed: _regenerating
                          ? null
                          : () async {
                              if (await _confirmRegenerate()) {
                                await _generateOrRegenerate();
                              }
                            },
                      icon: _regenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(l10n.tr('Regenerate QR Code')), 
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        side: BorderSide(color: Colors.red.shade300),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.tr('Only regenerate if the QR is compromised.'),
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0D7377)),
        const SizedBox(width: 10),
        Expanded(
          child:
              Text(text, style: TextStyle(color: cs.onSurface, fontSize: 13)),
        ),
      ],
    );
  }
}
