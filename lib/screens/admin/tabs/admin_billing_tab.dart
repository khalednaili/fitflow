import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/invoice.dart';
import '../../../models/membership_plan.dart';
import '../../../models/user_subscription.dart';
import '../../../services/billing_service.dart';
import '../../../services/member_service.dart';
import '../../../services/subscription_service.dart';
import '../../../utils/crash_logger.dart';
import '../invoice_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin Billing Tab
// ─────────────────────────────────────────────────────────────────────────────

class AdminBillingTab extends StatefulWidget {
  const AdminBillingTab({super.key, required this.gymId});
  final String gymId;

  @override
  State<AdminBillingTab> createState() => _AdminBillingTabState();
}

class _AdminBillingTabState extends State<AdminBillingTab>
    with SingleTickerProviderStateMixin {
  late final BillingService _billing;
  late final MemberService _members;
  late final SubscriptionService _subs;
  late final TabController _filterController;
  final _searchCtrl = TextEditingController();

  RevenueStats? _stats;
  bool _statsLoading = true;
  String _searchQuery = '';
  String _sortColumn = 'date';
  bool _sortAscending = false;

  static const _filters = ['All', 'Paid', 'Partial', 'Unpaid'];

  @override
  void initState() {
    super.initState();
    _billing = BillingService(gymId: widget.gymId);
    _members = MemberService(gymId: widget.gymId);
    _subs = SubscriptionService(gymId: widget.gymId);
    _filterController = TabController(length: _filters.length, vsync: this);
    _searchCtrl.addListener(
        () => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
    _loadStats();
  }

  @override
  void dispose() {
    _filterController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final stats = await _billing.computeRevenueStats();
      if (mounted) setState(() => _stats = stats);
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'BillingTab._loadStats');
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  List<Invoice> _applyFilterAndSearch(List<Invoice> all, String filter) {
    var list = filter == 'All'
        ? List.of(all)
        : all.where((inv) => inv.status == filter.toLowerCase()).toList();
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((inv) =>
              inv.memberName.toLowerCase().contains(_searchQuery) ||
              inv.invoiceNumber.toLowerCase().contains(_searchQuery) ||
              inv.planName.toLowerCase().contains(_searchQuery))
          .toList();
    }
    list.sort((a, b) {
      final cmp = switch (_sortColumn) {
        'member' => a.memberName.compareTo(b.memberName),
        'number' => a.invoiceNumber.compareTo(b.invoiceNumber),
        'status' => a.status.compareTo(b.status),
        'total' => a.totalAmount.compareTo(b.totalAmount),
        'due' => a.remainingAmount.compareTo(b.remainingAmount),
        _ => a.issuedAt.compareTo(b.issuedAt),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return isWide
        ? _buildWideLayout(context, l10n)
        : _buildNarrowLayout(context, l10n);
  }

  // ── Wide layout ────────────────────────────────────────────────────────────

  Widget _buildWideLayout(BuildContext context, AppLocalizations l10n) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left: stats + chart ──────────────────────────────────────────
          SizedBox(
            width: 340,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Billing & Revenue',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F4C45),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Refresh stats',
                          child: IconButton(
                            icon: _statsLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18),
                            onPressed: _statsLoading ? null : _loadStats,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _StatsRow(
                      stats: _stats,
                      loading: _statsLoading,
                      onRefresh: _loadStats,
                    ),
                    const SizedBox(height: 16),
                    if (_stats != null && _stats!.monthlyTrend.isNotEmpty)
                      _MonthlyTrendCard(stats: _stats!, tallBars: true),
                  ],
                ),
              ),
            ),
          ),
          // ── Divider ──────────────────────────────────────────────────────
          const VerticalDivider(width: 1, thickness: 1),
          // ── Right: invoice panel ─────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InvoicePanelHeader(
                  searchCtrl: _searchCtrl,
                  filterController: _filterController,
                  filters: _filters,
                  l10n: l10n,
                  onNew: _openCreateInvoiceSheet,
                  onSettings: _openInvoiceSettings,
                ),
                Expanded(
                  child: StreamBuilder<List<Invoice>>(
                    stream: _billing.streamInvoices(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final all = snap.data ?? [];
                      return AnimatedBuilder(
                        animation: _filterController,
                        builder: (context, _) {
                          final filter = _filters[_filterController.index];
                          final filtered = _applyFilterAndSearch(all, filter);
                          if (filtered.isEmpty) {
                            return _EmptyState(filter: filter, l10n: l10n);
                          }
                          return _InvoiceTable(
                            invoices: filtered,
                            sortColumn: _sortColumn,
                            sortAscending: _sortAscending,
                            onSort: _onSort,
                            onDelete: _confirmDelete,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Narrow layout (unchanged) ──────────────────────────────────────────────

  Widget _buildNarrowLayout(BuildContext context, AppLocalizations l10n) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Billing & Revenue',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F4C45),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Invoice Settings',
                      child: IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: _openInvoiceSettings,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _StatsRow(
                    stats: _stats,
                    loading: _statsLoading,
                    onRefresh: _loadStats),
                const SizedBox(height: 16),
                if (_stats != null && _stats!.monthlyTrend.isNotEmpty)
                  _MonthlyTrendCard(stats: _stats!),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TabBar(
                controller: _filterController,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.normal),
                indicatorColor: const Color(0xFF0F766E),
                labelColor: const Color(0xFF0F766E),
                unselectedLabelColor: Colors.grey,
                tabs: _filters.map((f) => Tab(text: l10n.tr(f))).toList(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Invoice>>(
              stream: _billing.streamInvoices(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? [];
                return TabBarView(
                  controller: _filterController,
                  children: _filters.map((filter) {
                    final filtered = _applyFilterAndSearch(all, filter);
                    if (filtered.isEmpty) {
                      return _EmptyState(filter: filter, l10n: l10n);
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _InvoiceCard(
                        invoice: filtered[i],
                        onDelete: () => _confirmDelete(filtered[i]),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateInvoiceSheet,
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text(l10n.tr('New Invoice')),
      ),
    );
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(Invoice invoice) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('Delete Invoice')),
        content: Text('${l10n.tr('Delete')} ${invoice.invoiceNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('Delete'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _billing.deleteInvoice(invoice.id);
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'BillingTab.deleteInvoice');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

   // ── Create invoice: dialog on web, bottom sheet on mobile ─────────────────

  Future<void> _openCreateInvoiceSheet() async {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    Widget sheet(BuildContext ctx) => CreateInvoiceSheet(
          gymId: widget.gymId,
          memberService: _members,
          subscriptionService: _subs,
          billingService: _billing,
          onCreated: (inv) {
            Navigator.of(ctx).pop();
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => InvoiceDetailScreen(invoice: inv),
            ));
            _loadStats();
          },
        );

    if (isWide) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 560,
            height: MediaQuery.sizeOf(context).height * 0.85,
            child: sheet(ctx),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: sheet,
      );
    }
  }

  // ── Invoice settings ────────────────────────────────────────────────────

  Future<void> _openInvoiceSettings() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InvoiceSettingsDialog(billing: _billing),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats row
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.stats,
    required this.loading,
    required this.onRefresh,
  });
  final RevenueStats? stats;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final cur = stats?.currency ?? '';

    if (loading) {
      return SizedBox(
        height: 90,
        child: Center(
          child: CircularProgressIndicator(
            color: const Color(0xFF0F766E),
            strokeWidth: 2,
          ),
        ),
      );
    }

    return Column(
      children: [
        // Row 1: Today, This Month
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.today_outlined,
                color: const Color(0xFF0F766E),
                label: context.l10n.tr("Today's Revenue"),
                value: stats == null ? '—' : '$cur ${stats!.revenueToday}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.calendar_month_outlined,
                color: const Color(0xFF2563EB),
                label: context.l10n.tr('This Month'),
                value: stats == null ? '—' : '$cur ${stats!.revenueThisMonth}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Row 2: New Payments, Outstanding
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.add_card_outlined,
                color: const Color(0xFF7C3AED),
                label: context.l10n.tr('New Payments'),
                value: stats == null ? '—' : '${stats!.newPaymentsThisMonth}',
                subtitle: context.l10n.tr('this month'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFDC2626),
                label: context.l10n.tr('Outstanding'),
                value: stats == null ? '—' : '$cur ${stats!.totalOutstanding}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Row 3: Last month + Method breakdown
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.history_outlined,
                color: const Color(0xFFF97316),
                label: context.l10n.tr('Last Month'),
                value: stats == null ? '—' : '$cur ${stats!.revenueLastMonth}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MethodBreakdownCard(stats: stats, cur: cur),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodBreakdownCard extends StatelessWidget {
  const _MethodBreakdownCard({required this.stats, required this.cur});
  final RevenueStats? stats;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final methods = stats?.revenueByMethod ?? {};

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.tr('By Method'),
            style: const TextStyle(
                fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          if (methods.isEmpty)
            const Text('—', style: TextStyle(fontSize: 13, color: Colors.grey))
          else
            ...methods.entries.take(3).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Icon(_methodIcon(e.key),
                            size: 12, color: _methodColor(e.key)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            e.key.toUpperCase(),
                            style: const TextStyle(fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$cur ${e.value}',
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  IconData _methodIcon(String m) {
    switch (m.toLowerCase()) {
      case 'card':
        return Icons.credit_card;
      case 'transfer':
        return Icons.swap_horiz;
      default:
        return Icons.payments_outlined;
    }
  }

  Color _methodColor(String m) {
    switch (m.toLowerCase()) {
      case 'card':
        return const Color(0xFF2563EB);
      case 'transfer':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF059669);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Monthly trend chart (simple bar chart)
// ─────────────────────────────────────────────────────────────────────────────

class _MonthlyTrendCard extends StatelessWidget {
  const _MonthlyTrendCard({required this.stats, this.tallBars = false});
  final RevenueStats stats;
  final bool tallBars;

  @override
  Widget build(BuildContext context) {
    final trend = stats.monthlyTrend;
    if (trend.isEmpty) return const SizedBox.shrink();

    final maxVal = trend.values.fold(0, (a, b) => a > b ? a : b);
    final cur = stats.currency;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.tr('Monthly Revenue (last 6 months)'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFF0F4C45),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: tallBars ? 160 : 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: trend.entries.map((entry) {
                final ratio = maxVal > 0 ? entry.value / maxVal : 0.0;
                final monthLabel = _shortMonth(entry.key);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (entry.value > 0)
                          Text(
                            '$cur ${entry.value}',
                            style: const TextStyle(
                                fontSize: 8, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 4),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          height: (100 * ratio).clamp(4, 100).toDouble(),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF0F766E),
                                Color(0xFF14B8A6),
                              ],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          monthLabel,
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _shortMonth(String yearMonth) {
    // "2024-05" → "May"
    final parts = yearMonth.split('-');
    if (parts.length < 2) return yearMonth;
    final month = int.tryParse(parts[1]) ?? 1;
    const names = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return names[month];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invoice card in list
// ─────────────────────────────────────────────────────────────────────────────

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, required this.onDelete});
  final Invoice invoice;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    final statusColor = _statusColor(invoice.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => InvoiceDetailScreen(invoice: invoice),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 4,
                height: 56,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            invoice.memberName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _StatusChip(status: invoice.status),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      invoice.invoiceNumber,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      invoice.planName,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Amount + date
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${invoice.currency} ${invoice.totalAmount}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  if (invoice.remainingAmount > 0)
                    Text(
                      'Due: ${invoice.currency} ${invoice.remainingAmount}',
                      style:
                          TextStyle(fontSize: 10, color: Colors.red.shade400),
                    ),
                  Text(
                    dateFmt.format(invoice.issuedAt),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.grey),
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 16,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'paid':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        break;
      case 'partial':
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
        break;
      default:
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.l10n});
  final String filter;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            l10n.tr('No invoices'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            filter == 'All'
                ? l10n.tr('Tap the button below to generate your first invoice')
                : '${l10n.tr('No')} ${filter.toLowerCase()} ${l10n.tr('invoices yet')}',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Invoice bottom sheet  (3-step wizard)
// ─────────────────────────────────────────────────────────────────────────────

enum _InvoiceStep { member, offer, confirm }

class CreateInvoiceSheet extends StatefulWidget {
  const CreateInvoiceSheet({
    super.key,
    required this.gymId,
    required this.memberService,
    required this.subscriptionService,
    required this.billingService,
    required this.onCreated,
    this.preselectedMember,
  });

  final String gymId;
  final MemberService memberService;
  final SubscriptionService subscriptionService;
  final BillingService billingService;
  final void Function(Invoice) onCreated;

  /// When set, step 1 (member selection) is skipped and the sheet opens
  /// directly on step 2 (offer selection) for this member.
  final AppUser? preselectedMember;

  @override
  State<CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends State<CreateInvoiceSheet> {
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  _InvoiceStep _step = _InvoiceStep.member;

  List<AppUser> _members = [];
  List<AppUser> _filtered = [];
  AppUser? _selectedMember;
  List<UserSubscription> _memberSubs = [];
  List<MembershipPlan> _plans = [];
  UserSubscription? _selectedSub;
  MembershipPlan? _selectedPlan;

  bool _loadingMembers = true;
  bool _loadingSubs = false;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // If a member is pre-selected, jump directly to offer step
    if (widget.preselectedMember != null) {
      _selectedMember = widget.preselectedMember;
      _step = _InvoiceStep.offer;
      _loadingMembers = false;
      _loadingSubs = true;
    }
    _loadMembersAndPlans();
    _searchController.addListener(_filterMembers);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembersAndPlans() async {
    try {
      // Always load plans (needed for offer name lookup)
      final plans = await widget.subscriptionService.streamAllOffers().first;
      if (mounted) setState(() => _plans = plans);

      if (widget.preselectedMember != null) {
        // Skip loading all members; load this member's subscriptions directly
        final subs = await widget.subscriptionService
            .streamUserSubscriptions(widget.preselectedMember!.id)
            .first;
        if (mounted) {
          setState(() {
            _memberSubs = subs;
            _loadingSubs = false;
          });
        }
      } else {
        final members = await widget.memberService.streamMembers().first;
        if (mounted) {
          setState(() {
            _members = members;
            _filtered = members;
            _loadingMembers = false;
          });
        }
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'CreateInvoiceSheet._load');
      if (mounted) {
        setState(() {
          _loadingMembers = false;
          _loadingSubs = false;
        });
      }
    }
  }

  void _filterMembers() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _members
          : _members
              .where((m) =>
                  m.displayName.toLowerCase().contains(q) ||
                  m.email.toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _selectMember(AppUser member) async {
    setState(() {
      _selectedMember = member;
      _memberSubs = [];
      _selectedSub = null;
      _selectedPlan = null;
      _loadingSubs = true;
      _step = _InvoiceStep.offer;
    });
    try {
      final subs = await widget.subscriptionService
          .streamUserSubscriptions(member.id)
          .first;
      if (mounted) {
        setState(() {
          _memberSubs = subs;
          _loadingSubs = false;
        });
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'CreateInvoiceSheet._selectMember');
      if (mounted) setState(() => _loadingSubs = false);
    }
  }

  void _selectOffer(UserSubscription sub) {
    final plan = _plans.cast<MembershipPlan?>().firstWhere(
          (p) => p?.id == sub.planId,
          orElse: () => null,
        );
    setState(() {
      _selectedSub = sub;
      _selectedPlan = plan;
      _step = _InvoiceStep.confirm;
    });
  }

  Future<void> _createInvoice() async {
    if (_selectedMember == null || _selectedSub == null) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final planName = _selectedPlan?.name ?? _selectedSub!.planId;
      final invoice = await widget.billingService.createInvoice(
        userId: _selectedMember!.id,
        memberName: _selectedMember!.displayName,
        memberEmail: _selectedMember!.email,
        memberPhone: _selectedMember!.phoneNumber,
        subscription: _selectedSub!,
        planName: planName,
        notes: _notesController.text.trim(),
      );
      widget.onCreated(invoice);
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'CreateInvoiceSheet._create');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  void _goBack() {
    if (_step == _InvoiceStep.confirm) {
      setState(() {
        _error = '';
        _step = _InvoiceStep.offer;
        _selectedSub = null;
        _selectedPlan = null;
      });
    } else if (_step == _InvoiceStep.offer) {
      if (widget.preselectedMember != null) {
        // Member was pre-selected — closing goes back to caller
        Navigator.of(context).pop();
      } else {
        setState(() {
          _error = '';
          _step = _InvoiceStep.member;
          _selectedMember = null;
          _memberSubs = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mq = MediaQuery.of(context);
    final isPreselected = widget.preselectedMember != null;

    // When member is pre-selected we only have 2 steps: offer → confirm
    final stepTitles = isPreselected
        ? [l10n.tr('Select Offer'), l10n.tr('Generate Invoice')]
        : [
            l10n.tr('Select Member'),
            l10n.tr('Select Offer'),
            l10n.tr('Generate Invoice'),
          ];
    final stepIndex = isPreselected
        ? (_step == _InvoiceStep.offer ? 0 : 1)
        : _InvoiceStep.values.indexOf(_step);

    return Container(
      height: mq.size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header with back + step indicator
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 16, 0),
            child: Row(
              children: [
                if (_step != _InvoiceStep.member)
                  IconButton(
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        stepTitles[stepIndex],
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      _StepProgress(
                          current: stepIndex, total: isPreselected ? 2 : 3),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          // Body
          Expanded(
            child: _loadingMembers
                ? const Center(child: CircularProgressIndicator())
                : _step == _InvoiceStep.member
                    ? _MemberPicker(
                        searchController: _searchController,
                        members: _filtered,
                        onSelect: _selectMember,
                        l10n: l10n,
                      )
                    : _step == _InvoiceStep.offer
                        ? _OfferPicker(
                            member: _selectedMember!,
                            subs: _memberSubs,
                            plans: _plans,
                            loading: _loadingSubs,
                            onSelect: _selectOffer,
                            l10n: l10n,
                          )
                        : _ConfirmStep(
                            member: _selectedMember!,
                            sub: _selectedSub!,
                            plan: _selectedPlan,
                            notesController: _notesController,
                            error: _error,
                            saving: _saving,
                            l10n: l10n,
                            onSubmit: _createInvoice,
                          ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step progress dots
// ─────────────────────────────────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        final done = i < current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color:
                done || active ? const Color(0xFF0F766E) : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 — Member picker
// ─────────────────────────────────────────────────────────────────────────────

class _MemberPicker extends StatelessWidget {
  const _MemberPicker({
    required this.searchController,
    required this.members,
    required this.onSelect,
    required this.l10n,
  });
  final TextEditingController searchController;
  final List<AppUser> members;
  final void Function(AppUser) onSelect;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.tr('Search member…'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: members.isEmpty
              ? Center(child: Text(l10n.tr('No members found')))
              : ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (_, i) {
                    final m = members[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            const Color(0xFF0F766E).withValues(alpha: 0.1),
                        child: Text(
                          m.displayName.isNotEmpty
                              ? m.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Color(0xFF0F766E),
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(m.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle:
                          Text(m.email, style: const TextStyle(fontSize: 12)),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => onSelect(m),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 — Offer picker (visual cards)
// ─────────────────────────────────────────────────────────────────────────────

class _OfferPicker extends StatelessWidget {
  const _OfferPicker({
    required this.member,
    required this.subs,
    required this.plans,
    required this.loading,
    required this.onSelect,
    required this.l10n,
  });
  final AppUser member;
  final List<UserSubscription> subs;
  final List<MembershipPlan> plans;
  final bool loading;
  final void Function(UserSubscription) onSelect;
  final AppLocalizations l10n;

  MembershipPlan? _planFor(UserSubscription sub) =>
      plans.cast<MembershipPlan?>().firstWhere(
            (p) => p?.id == sub.planId,
            orElse: () => null,
          );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (subs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.card_membership_outlined,
                  size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                l10n.tr('No subscriptions found'),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                '${member.displayName} ${l10n.tr('has no active subscription')}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: subs.length,
      itemBuilder: (_, i) {
        final sub = subs[i];
        final plan = _planFor(sub);
        return _OfferCard(
          sub: sub,
          plan: plan,
          l10n: l10n,
          onTap: () => onSelect(sub),
        );
      },
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.sub,
    required this.plan,
    required this.l10n,
    required this.onTap,
  });
  final UserSubscription sub;
  final MembershipPlan? plan;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    final paid = sub.amountPaid;
    final total = sub.totalAmount;
    final remaining = total - paid;
    final pct = total > 0 ? paid / total : 0.0;

    final Color statusColor;
    final String statusLabel;
    if (remaining <= 0) {
      statusColor = Colors.green;
      statusLabel = l10n.tr('Paid');
    } else if (paid > 0) {
      statusColor = Colors.orange;
      statusLabel = l10n.tr('Partial');
    } else {
      statusColor = Colors.red;
      statusLabel = l10n.tr('Unpaid');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Plan name + status chip
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.card_membership,
                        size: 18, color: Color(0xFF0F766E)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan?.name ?? sub.planId,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (plan != null)
                          Text(
                            plan!.offerTypeLabel,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Amounts row
              Row(
                children: [
                  Expanded(
                    child: _AmountCell(
                      label: l10n.tr('Total'),
                      value: '${sub.currency} $total',
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Expanded(
                    child: _AmountCell(
                      label: l10n.tr('Paid'),
                      value: '${sub.currency} $paid',
                      color: Colors.green.shade700,
                    ),
                  ),
                  Expanded(
                    child: _AmountCell(
                      label: l10n.tr('Balance'),
                      value: '${sub.currency} $remaining',
                      color: remaining > 0
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 8),
              // Dates row
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(
                    sub.startDate != null
                        ? dateFmt.format(sub.startDate!)
                        : '—',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const Text('  →  ',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(
                    sub.endDate != null
                        ? dateFmt.format(sub.endDate!)
                        : l10n.tr('Open-ended'),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const Spacer(),
                  Text(
                    '${(pct * 100).toStringAsFixed(0)}% ${l10n.tr('paid')}',
                    style: TextStyle(fontSize: 11, color: statusColor),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Select button
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text(l10n.tr('Select this offer'),
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountCell extends StatelessWidget {
  const _AmountCell(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13, color: color)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 3 — Confirm & generate
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.member,
    required this.sub,
    required this.plan,
    required this.notesController,
    required this.error,
    required this.saving,
    required this.l10n,
    required this.onSubmit,
  });
  final AppUser member;
  final UserSubscription sub;
  final MembershipPlan? plan;
  final TextEditingController notesController;
  final String error;
  final bool saving;
  final AppLocalizations l10n;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    final paid = sub.amountPaid;
    final total = sub.totalAmount;
    final remaining = total - paid;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Member ──────────────────────────────────────────────────────
          _PreviewSection(
            icon: Icons.person_outline,
            title: l10n.tr('Member'),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF0F766E).withValues(alpha: 0.1),
                child: Text(
                  member.displayName.isNotEmpty
                      ? member.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Color(0xFF0F766E), fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(member.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle:
                  Text(member.email, style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 12),
          // ── Offer ────────────────────────────────────────────────────────
          _PreviewSection(
            icon: Icons.card_membership_outlined,
            title: l10n.tr('Offer'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan?.name ?? sub.planId,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                if (plan != null)
                  Text(plan!.offerTypeLabel,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: _AmountCell(
                            label: l10n.tr('Total'),
                            value: '${sub.currency} $total',
                            color: Colors.grey.shade700)),
                    Expanded(
                        child: _AmountCell(
                            label: l10n.tr('Paid'),
                            value: '${sub.currency} $paid',
                            color: Colors.green.shade700)),
                    Expanded(
                        child: _AmountCell(
                            label: l10n.tr('Balance Due'),
                            value: '${sub.currency} $remaining',
                            color: remaining > 0
                                ? Colors.red.shade700
                                : Colors.green.shade700)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      '${sub.startDate != null ? dateFmt.format(sub.startDate!) : '—'}  →  '
                      '${sub.endDate != null ? dateFmt.format(sub.endDate!) : l10n.tr('Open-ended')}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── Notes ────────────────────────────────────────────────────────
          _PreviewSection(
            icon: Icons.notes_outlined,
            title: l10n.tr('Notes (optional)'),
            child: TextField(
              controller: notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: l10n.tr('Add a note to this invoice…'),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── Error ────────────────────────────────────────────────────────
          if (error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(error, style: TextStyle(color: Colors.red.shade700)),
            ),
          // ── Generate button ──────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.receipt_long_outlined),
              label: Text(
                saving ? l10n.tr('Generating…') : l10n.tr('Generate Invoice'),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection(
      {required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF0F766E)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F766E),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers kept from old implementation
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Wide layout: invoice panel header (search + filter + new button)
// ─────────────────────────────────────────────────────────────────────────────

class _InvoicePanelHeader extends StatelessWidget {
  const _InvoicePanelHeader({
    required this.searchCtrl,
    required this.filterController,
    required this.filters,
    required this.l10n,
    required this.onNew,
    required this.onSettings,
  });

  final TextEditingController searchCtrl;
  final TabController filterController;
  final List<String> filters;
  final AppLocalizations l10n;
  final VoidCallback onNew;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText:
                          context.l10n.tr('Search member, invoice #, plan…'),
                      hintStyle: const TextStyle(fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: l10n.tr('Invoice Settings'),
                child: IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  onPressed: onSettings,
                ),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: onNew,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.tr('New Invoice'),
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TabBar(
            controller: filterController,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.normal),
            indicatorColor: const Color(0xFF0F766E),
            labelColor: const Color(0xFF0F766E),
            unselectedLabelColor: Colors.grey,
            tabs: filters.map((f) => Tab(text: l10n.tr(f))).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wide layout: sortable invoice data table
// ─────────────────────────────────────────────────────────────────────────────

class _InvoiceTable extends StatelessWidget {
  const _InvoiceTable({
    required this.invoices,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.onDelete,
  });

  final List<Invoice> invoices;
  final String sortColumn;
  final bool sortAscending;
  final void Function(String) onSort;
  final void Function(Invoice) onDelete;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header row ──────────────────────────────────────────────────────
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _SortHeader('MEMBER', 'member', sortColumn, sortAscending, onSort,
                  flex: 3),
              _SortHeader(
                  'INVOICE #', 'number', sortColumn, sortAscending, onSort,
                  flex: 2),
              _SortHeader('PLAN', 'plan', sortColumn, sortAscending, onSort,
                  flex: 2),
              _SortHeader('STATUS', 'status', sortColumn, sortAscending, onSort,
                  flex: 1),
              _SortHeader('TOTAL', 'total', sortColumn, sortAscending, onSort,
                  flex: 2, rightAlign: true),
              _SortHeader('DUE', 'due', sortColumn, sortAscending, onSort,
                  flex: 2, rightAlign: true),
              _SortHeader('DATE', 'date', sortColumn, sortAscending, onSort,
                  flex: 2),
              const SizedBox(width: 40),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Data rows ──────────────────────────────────────────────────────
        Expanded(
          child: ListView.separated(
            itemCount: invoices.length,
            separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Colors.grey.shade100),
            itemBuilder: (context, i) {
              final inv = invoices[i];
              final statusColor = _statusColor(inv.status);
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => InvoiceDetailScreen(invoice: inv),
                    ),
                  ),
                  hoverColor: const Color(0xFF0F766E).withValues(alpha: 0.03),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    child: Row(
                      children: [
                        // Member
                        Expanded(
                          flex: 3,
                          child: Text(
                            inv.memberName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Invoice #
                        Expanded(
                          flex: 2,
                          child: Text(
                            inv.invoiceNumber,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Plan
                        Expanded(
                          flex: 2,
                          child: Text(
                            inv.planName,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Status badge
                        Expanded(
                          flex: 1,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                inv.status.toUpperCase(),
                                style: TextStyle(
                                    color: statusColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                        // Total
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${inv.currency} ${inv.totalAmount}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        // Due
                        Expanded(
                          flex: 2,
                          child: Text(
                            inv.remainingAmount > 0
                                ? '${inv.currency} ${inv.remainingAmount}'
                                : '—',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: inv.remainingAmount > 0
                                  ? Colors.red.shade600
                                  : Colors.grey.shade400,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        // Date
                        Expanded(
                          flex: 2,
                          child: Text(
                            dateFmt.format(inv.issuedAt),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ),
                        // Delete
                        SizedBox(
                          width: 40,
                          child: IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 16, color: Colors.grey.shade400),
                            onPressed: () => onDelete(inv),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                maxWidth: 32, maxHeight: 32),
                            tooltip: context.l10n.tr('Delete'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // ── Footer count ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border:
                Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: Text(
            '${invoices.length} invoice${invoices.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }
}

class _SortHeader extends StatelessWidget {
  const _SortHeader(
    this.label,
    this.column,
    this.sortColumn,
    this.sortAscending,
    this.onSort, {
    this.flex = 1,
    this.rightAlign = false,
  });

  final String label;
  final String column;
  final String sortColumn;
  final bool sortAscending;
  final void Function(String) onSort;
  final int flex;
  final bool rightAlign;

  @override
  Widget build(BuildContext context) {
    final isActive = sortColumn == column;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => onSort(column),
        borderRadius: BorderRadius.circular(4),
        child: Row(
          mainAxisAlignment:
              rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color:
                    isActive ? const Color(0xFF0F766E) : Colors.grey.shade500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              isActive
                  ? (sortAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded)
                  : Icons.unfold_more_rounded,
              size: 12,
              color: isActive ? const Color(0xFF0F766E) : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invoice Settings Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _InvoiceSettingsDialog extends StatefulWidget {
  const _InvoiceSettingsDialog({required this.billing});
  final BillingService billing;

  @override
  State<_InvoiceSettingsDialog> createState() => _InvoiceSettingsDialogState();
}

class _InvoiceSettingsDialogState extends State<_InvoiceSettingsDialog> {
  final _prefixCtrl = TextEditingController();
  final _startCtrl = TextEditingController();
  bool _resetCounter = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _currentNextSeq = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _startCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.billing.getInvoiceSettings();
      if (!mounted) return;
      setState(() {
        _prefixCtrl.text = settings.prefix;
        _startCtrl.text = settings.startNumber.toString();
        _currentNextSeq = settings.nextSequence;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final prefix = _prefixCtrl.text.trim();
    final startNumber = int.tryParse(_startCtrl.text.trim());

    if (prefix.isEmpty) {
      setState(() => _error = 'Prefix cannot be empty.');
      return;
    }
    if (startNumber == null || startNumber < 1) {
      setState(() => _error = 'Start number must be a positive integer.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.billing.saveInvoiceSettings(
        prefix: prefix,
        startNumber: startNumber,
        resetCounter: _resetCounter,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  /// Preview what the next invoice number will look like.
  String get _preview {
    final prefix = _prefixCtrl.text.trim().isEmpty ? 'INV' : _prefixCtrl.text.trim();
    final startNumber = int.tryParse(_startCtrl.text.trim()) ?? 1;
    final seq = _resetCounter ? startNumber : _currentNextSeq;
    final year = DateTime.now().year;
    return '$prefix-$year-${seq.toString().padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.receipt_long_outlined,
              color: Color(0xFF0F766E), size: 22),
          const SizedBox(width: 8),
          Text(l10n.tr('Invoice Settings'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prefix
                  TextField(
                    controller: _prefixCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.tr('Invoice Prefix'),
                      hintText: 'INV',
                      helperText: l10n.tr('Letters/numbers only, e.g. INV or GYM'),
                      border: const OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  // Start number
                  TextField(
                    controller: _startCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.tr('Starting Number'),
                      hintText: '1',
                      helperText: l10n.tr('First sequence number when counter resets'),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  // Reset counter
                  CheckboxListTile(
                    value: _resetCounter,
                    onChanged: (v) => setState(() => _resetCounter = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(l10n.tr('Reset counter to start number'),
                        style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      l10n.tr('Current next: #${_currentNextSeq.toString().padLeft(4, '0')}'),
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Preview
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F4F1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.visibility_outlined,
                            size: 16, color: Color(0xFF0F766E)),
                        const SizedBox(width: 8),
                        Text(
                          '${l10n.tr('Next invoice')}: $_preview',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.tr('Cancel')),
        ),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E)),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(l10n.tr('Save')),
        ),
      ],
    );
  }
}
