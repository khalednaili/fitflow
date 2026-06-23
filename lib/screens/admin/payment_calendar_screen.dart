import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user_subscription.dart';
import '../../services/subscription_service.dart';

/// Shows all pending (unpaid) instalments across every member,
/// grouped by status: Overdue · Due Today · Upcoming.
class PaymentCalendarScreen extends StatefulWidget {
  const PaymentCalendarScreen({super.key, required this.gymId});
  final String gymId;

  @override
  State<PaymentCalendarScreen> createState() => _PaymentCalendarScreenState();
}

class _PaymentCalendarScreenState extends State<PaymentCalendarScreen> {
  late final SubscriptionService _service =
      SubscriptionService(gymId: widget.gymId);

  static const _methodIcons = {
    'cash': Icons.payments_outlined,
    'card': Icons.credit_card_outlined,
    'transfer': Icons.account_balance_outlined,
    'cheque': Icons.receipt_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('Payment Calendar')),
        centerTitle: true,
      ),
      body: StreamBuilder<List<InstalmentWithSubscription>>(
        stream: _service.streamPendingInstalments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('${context.l10n.tr('Error')}: ${snapshot.error}'));
          }

          final all = snapshot.data ?? [];
          if (all.isEmpty) {
            return _EmptyState(cs: cs);
          }

          // ── Split into groups ────────────────────────────────────────
          final overdue = <InstalmentWithSubscription>[];
          final dueToday = <InstalmentWithSubscription>[];
          final upcoming = <InstalmentWithSubscription>[];

          for (final item in all) {
            final due = item.instalment.dueDate;
            final dueDate =
                DateTime(due.year, due.month, due.day);
            if (dueDate.isBefore(todayDate)) {
              overdue.add(item);
            } else if (dueDate.isAtSameMomentAs(todayDate)) {
              dueToday.add(item);
            } else {
              upcoming.add(item);
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (overdue.isNotEmpty) ...[
                _GroupHeader(
                  icon: Icons.warning_amber_rounded,
                  label: context.l10n.tr('Overdue'),
                  count: overdue.length,
                  color: cs.error,
                ),
                const SizedBox(height: 8),
                ...overdue.map((item) => _InstalmentTile(
                      item: item,
                      methodIcons: _methodIcons,
                      statusColor: cs.error,
                      statusIcon: Icons.warning_amber_outlined,
                      onMarkPaid: _handleMarkPaid,
                    )),
                const SizedBox(height: 20),
              ],
              if (dueToday.isNotEmpty) ...[
                _GroupHeader(
                  icon: Icons.today_outlined,
                  label: context.l10n.tr('Due Today'),
                  count: dueToday.length,
                  color: Colors.orange,
                ),
                const SizedBox(height: 8),
                ...dueToday.map((item) => _InstalmentTile(
                      item: item,
                      methodIcons: _methodIcons,
                      statusColor: Colors.orange,
                      statusIcon: Icons.today_outlined,
                      onMarkPaid: _handleMarkPaid,
                    )),
                const SizedBox(height: 20),
              ],
              if (upcoming.isNotEmpty) ...[
                _GroupHeader(
                  icon: Icons.schedule_outlined,
                  label: context.l10n.tr('Upcoming'),
                  count: upcoming.length,
                  color: cs.primary,
                ),
                const SizedBox(height: 8),
                ...upcoming.map((item) => _InstalmentTile(
                      item: item,
                      methodIcons: _methodIcons,
                      statusColor: cs.primary,
                      statusIcon: Icons.schedule_outlined,
                      onMarkPaid: _handleMarkPaid,
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleMarkPaid(
      String subscriptionId, String instalmentId) async {
    await _service.markInstalmentPaid(
      subscriptionId: subscriptionId,
      instalmentId: instalmentId,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: color.withValues(alpha: 0.12),
          ),
          child: Text('$count',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: color.withValues(alpha: 0.3))),
      ],
    );
  }
}

class _InstalmentTile extends StatefulWidget {
  const _InstalmentTile({
    required this.item,
    required this.methodIcons,
    required this.statusColor,
    required this.statusIcon,
    required this.onMarkPaid,
  });

  final InstalmentWithSubscription item;
  final Map<String, IconData> methodIcons;
  final Color statusColor;
  final IconData statusIcon;
  final Future<void> Function(String subId, String instId) onMarkPaid;

  @override
  State<_InstalmentTile> createState() => _InstalmentTileState();
}

class _InstalmentTileState extends State<_InstalmentTile> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = widget.item.subscription;
    final inst = widget.item.instalment;
    final fmt = DateFormat('d MMM yyyy');
    final idx = sub.instalmentSchedule.indexOf(inst);

    // Find member name — stored in subscription userId, load async if needed.
    // For now display the userId until a member lookup is added.
    final memberLabel = sub.userId;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: widget.statusColor.withValues(alpha: 0.3)),
        color: cs.surface,
        boxShadow: [
          BoxShadow(
              color: cs.shadow.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.statusColor.withValues(alpha: 0.12),
            ),
            child: Icon(widget.statusIcon,
                size: 18, color: widget.statusColor),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memberLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      widget.methodIcons[inst.method] ??
                          Icons.payments_outlined,
                      size: 12,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${inst.amount} ${sub.currency}  ·  ${context.l10n.tr('Instalment')} ${idx >= 0 ? idx + 1 : '?'}/${sub.instalmentSchedule.length}',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${context.l10n.tr('Due')}: ${fmt.format(inst.dueDate)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: widget.statusColor,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          // Mark as Paid button
          _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title:
                            Text(context.l10n.tr('Mark as Paid')),
                        content: Text(
                            '${context.l10n.tr('Confirm payment of')} ${inst.amount} ${sub.currency}?'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, false),
                            child:
                                Text(context.l10n.tr('Cancel')),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(ctx, true),
                            child:
                                Text(context.l10n.tr('Confirm')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    setState(() => _loading = true);
                    try {
                      await widget.onMarkPaid(sub.id, inst.id);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('$e'),
                                backgroundColor: cs.error));
                      }
                    } finally {
                      if (mounted) setState(() => _loading = false);
                    }
                  },
                  child: Text(context.l10n.tr('Mark as Paid'),
                      style: const TextStyle(fontSize: 12)),
                ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 56,
              color: Colors.green.shade400),
          const SizedBox(height: 16),
          Text(
            context.l10n.tr('No pending instalments'),
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.tr(
                'All payment plans are up to date.'),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
