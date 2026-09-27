import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../../models/gym.dart';
import '../../models/gym_usage.dart';
import '../../models/invoice.dart';
import '../../services/gym_service.dart';
import '../../services/invoice_pdf_service.dart';
import '../../services/platform_billing_service.dart';
import '../../utils/currency.dart';
import '../../utils/platform_pricing.dart';
import '../../l10n/app_localizations.dart';

/// Super admin screen: shows each gym's Firebase usage footprint (writes,
/// deletes, storage — reads aren't tracked, see [GymUsage]) and the
/// resulting estimated platform charge, and lets the super admin generate a
/// real invoice billing the gym for it.
class GymUsageScreen extends StatefulWidget {
  const GymUsageScreen({super.key});

  @override
  State<GymUsageScreen> createState() => _GymUsageScreenState();
}

class _GymUsageScreenState extends State<GymUsageScreen> {
  bool _backfilling = false;

  Future<void> _runBackfill() async {
    setState(() => _backfilling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'superAdminBackfillGymUsage',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
          )
          .call();
      final count = (result.data['gymsBackfilled'] as num?) ?? 0;
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10n.tr('Backfilled usage for')} $count '
              '${context.l10n.tr('gyms')}.',
            ),
          ),
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'backfillGymUsage');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${context.l10n.tr('Error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gymService = GymService();
    final billing = PlatformBillingService();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('Usage & Billing')),
        actions: [
          if (_backfilling)
            Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.refresh),
              tooltip: context.l10n
                  .tr('Backfill usage from existing data (run once)'),
              onPressed: _runBackfill,
            ),
        ],
      ),
      body: StreamBuilder<List<Gym>>(
        stream: gymService.watchAllGyms(),
        builder: (context, gymSnap) {
          if (!gymSnap.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          final gyms = gymSnap.data!;

          return StreamBuilder<Map<String, GymUsage>>(
            stream: billing.watchAllUsage(),
            builder: (context, usageSnap) {
              final usageByGym = usageSnap.data ?? {};

              final rows = gyms
                  .map((gym) => (
                        gym: gym,
                        usage: usageByGym[gym.id] ?? GymUsage.empty(gym.id),
                      ))
                  .toList()
                ..sort((a, b) => PlatformPricing.compute(b.usage)
                    .total
                    .compareTo(PlatformPricing.compute(a.usage).total));

              final totalEstimated =
                  computeEstimatedPlatformRevenue(gyms, usageByGym);

              return ListView(
                padding: EdgeInsets.all(24),
                children: [
                  _SummaryBanner(totalEstimated: totalEstimated),
                  SizedBox(height: 24),
                  if (rows.isEmpty)
                    Text(context.l10n.tr('No gyms yet.'))
                  else
                    ...rows.map(
                      (r) => _GymUsageCard(gym: r.gym, usage: r.usage),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.totalEstimated});

  final num totalEstimated;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.receipt_long, color: cs.onPrimaryContainer, size: 32),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context
                        .l10n
                        .tr('Estimated charge this period (active gyms)'),
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                  SizedBox(height: 4),
                  Text(
                    Currency.format(totalEstimated, PlatformPricing.currency),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold),
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

class _GymUsageCard extends StatefulWidget {
  const _GymUsageCard({required this.gym, required this.usage});

  final Gym gym;
  final GymUsage usage;

  @override
  State<_GymUsageCard> createState() => _GymUsageCardState();
}

class _GymUsageCardState extends State<_GymUsageCard> {
  final _billing = PlatformBillingService();
  bool _generating = false;

  Future<void> _generateInvoice(PlatformCharge charge) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.tr('Generate Invoice')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ctx.l10n
                .tr('Bill "${widget.gym.name}" for this period\'s usage?')),
            SizedBox(height: 12),
            ...charge.lines.map(
              (l) => Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(l.description)),
                    Text(Currency.format(l.amount, charge.currency)),
                  ],
                ),
              ),
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(ctx.l10n.tr('Total'),
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(Currency.format(charge.total, charge.currency),
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.tr('Generate')),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _generating = true);
    try {
      final invoice = await _billing.generateInvoiceForGym(widget.gym);
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10n.tr('Invoice')} ${invoice.invoiceNumber} '
            '${context.l10n.tr('created')}.',
          ),
          action: SnackBarAction(
            label: context.l10n.tr('Share PDF'),
            onPressed: () => InvoicePdfService.shareInvoice(invoice),
          ),
        ),
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'generatePlatformInvoice');
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.tr('Error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final charge = PlatformPricing.compute(widget.usage);
    final storageMb = widget.usage.totalStorageBytes / (1024 * 1024);
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.gym.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  Currency.format(charge.total, charge.currency),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _MiniStat(
                  label: context.l10n.tr('Docs'),
                  value: '${widget.usage.docCount}',
                ),
                _MiniStat(
                  label: context.l10n.tr('Ops this period'),
                  value: '${charge.periodOps}',
                ),
                _MiniStat(
                  label: context.l10n.tr('Storage'),
                  value: '${storageMb.toStringAsFixed(1)} MB',
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: Icon(Icons.history),
                  label: Text(context.l10n.tr('Invoices')),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => GymPlatformInvoicesScreen(gym: widget.gym),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                _generating
                    ? Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : FilledButton.icon(
                        icon: Icon(Icons.request_quote_outlined),
                        label: Text(context.l10n.tr('Generate Invoice')),
                        onPressed: () => _generateInvoice(charge),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

/// Lists the platform invoices billed to a single gym, with share/print and
/// "mark as paid" actions.
class GymPlatformInvoicesScreen extends StatelessWidget {
  const GymPlatformInvoicesScreen({super.key, required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) {
    final billing = PlatformBillingService();
    return Scaffold(
      appBar: AppBar(
        title: Text('${context.l10n.tr('Invoices')} · ${gym.name}'),
      ),
      body: StreamBuilder<List<Invoice>>(
        stream: billing.streamInvoicesForGym(gym.id),
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          final invoices = snap.data!;
          if (invoices.isEmpty) {
            return Center(
              child: Text(context.l10n.tr('No invoices yet.')),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.all(16),
            itemCount: invoices.length,
            separatorBuilder: (_, __) => SizedBox(height: 8),
            itemBuilder: (context, i) {
              final invoice = invoices[i];
              return Card(
                child: ListTile(
                  title: Text(invoice.invoiceNumber),
                  subtitle: Text(
                    '${invoice.planName}\n'
                    '${Currency.format(invoice.totalAmount, invoice.currency)}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      Chip(
                        label: Text(
                          invoice.status.toUpperCase(),
                          style: TextStyle(fontSize: 11),
                        ),
                        backgroundColor: invoice.isPaid
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                      ),
                      IconButton(
                        icon: Icon(Icons.share_outlined),
                        tooltip: context.l10n.tr('Share PDF'),
                        onPressed: () =>
                            InvoicePdfService.shareInvoice(invoice),
                      ),
                      if (!invoice.isPaid)
                        IconButton(
                          icon: Icon(Icons.check_circle_outline),
                          tooltip: context.l10n.tr('Mark as paid'),
                          onPressed: () async {
                            await billing.markInvoicePaid(invoice.id);
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
