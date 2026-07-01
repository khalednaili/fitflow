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
import '../../../utils/currency.dart';
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
  DateTimeRange? _statsDateRange;

  static const _filters = ['All', 'Unpaid', 'Partial', 'Paid', 'Sent', 'Overdue', 'Void'];

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
    // Auto-mark past-due invoices on open
    _billing.checkAndUpdateOverdueInvoices().ignore();
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
      final stats = await _billing.computeRevenueStats(
        from: _statsDateRange?.start,
        to: _statsDateRange?.end,
      );
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
        : all
            .where((inv) =>
                inv.status ==
                // 'Void' label → InvoiceStatus.void_ = 'void'
                (filter == 'Void' ? 'void' : filter.toLowerCase()))
            .toList();
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

  Future<void> _pickStatsDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _statsDateRange,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: const Color(0xFF0F766E),
              ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _statsDateRange = picked);
    _loadStats();
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
                          message: 'Filter by date range',
                          child: IconButton(
                            icon: Icon(
                              Icons.date_range_outlined,
                              size: 18,
                              color: _statsDateRange != null
                                  ? const Color(0xFF0F766E)
                                  : null,
                            ),
                            onPressed: _pickStatsDateRange,
                          ),
                        ),
                        if (_statsDateRange != null)
                          Tooltip(
                            message: 'Clear date filter',
                            child: IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                setState(() => _statsDateRange = null);
                                _loadStats();
                              },
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
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            '${l10n.tr('Error loading invoices')}: ${snap.error}',
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        );
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
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      '${l10n.tr('Error loading invoices')}: ${snap.error}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
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
    // Audit compliance: an issued invoice is voided (kept in the ledger),
    // never deleted. Only drafts, which were never issued, can be hard-deleted.
    final isDraft = invoice.isDraft;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr(isDraft ? 'Delete Invoice' : 'Void Invoice')),
        content: Text(isDraft
            ? '${l10n.tr('Delete')} ${invoice.invoiceNumber}?'
            : '${l10n.tr('Void')} ${invoice.invoiceNumber}? ${l10n.tr('It will be kept for records.')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr(isDraft ? 'Delete' : 'Void'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (isDraft) {
        await _billing.deleteInvoice(invoice.id);
      } else {
        await _billing.voidInvoice(invoice.id);
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'BillingTab.voidOrDeleteInvoice');
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
                    Currency.format(invoice.totalAmount, invoice.currency),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  if (invoice.remainingAmount > 0)
                    Text(
                      'Due: ${Currency.format(invoice.remainingAmount, invoice.currency)}',
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

  Color _statusColor(String status) => switch (status) {
        'paid' => Colors.green,
        'partial' => Colors.orange,
        'sent' => Colors.purple,
        'overdue' => Colors.red.shade700,
        'void' => Colors.grey,
        'draft' => Colors.blue,
        _ => Colors.red,
      };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'paid' => (Colors.green.shade100, Colors.green.shade800),
      'partial' => (Colors.orange.shade100, Colors.orange.shade800),
      'sent' => (Colors.purple.shade50, Colors.purple.shade700),
      'overdue' => (Colors.red.shade100, Colors.red.shade800),
      'void' => (Colors.grey.shade200, Colors.grey.shade600),
      'draft' => (Colors.blue.shade50, Colors.blue.shade700),
      _ => (Colors.amber.shade100, Colors.amber.shade800),
    };
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
  List<UserSubscription> _selectedSubs = [];
  String _invoiceNumberHint = '';
  num _stampDefault = 0;
  int _vatDefault = 19;

  bool _loadingMembers = true;
  bool _loadingSubs = false;
  bool _saving = false;
  String _error = '';

  List<MembershipPlan?> get _selectedPlans => _selectedSubs
      .map((s) => _plans.cast<MembershipPlan?>().firstWhere(
            (p) => p?.id == s.planId,
            orElse: () => null,
          ))
      .toList();

  List<String> get _selectedPlanLabels => _selectedSubs.asMap().entries
      .map((e) => _selectedPlans[e.key]?.name ?? e.value.planId)
      .toList();

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
      // Always load plans (needed for offer name lookup).
      // Use fetchAllOffers() (one-time get) to avoid a persistent Firestore
      // listener being created and immediately cancelled via .first — that
      // pattern triggers an "Unexpected state" assertion in the Firestore
      // Web SDK when the watch-stream is mid-cycle.
      final plans = await widget.subscriptionService.fetchAllOffers();
      if (mounted) setState(() => _plans = plans);

      if (widget.preselectedMember != null) {
        final subs = await widget.subscriptionService
            .fetchUserSubscriptions(widget.preselectedMember!.id);
        if (mounted) {
          setState(() {
            _memberSubs = subs;
            _loadingSubs = false;
          });
        }
      } else {
        final members = await widget.memberService.fetchMembers();
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
      _selectedSubs = [];
      _loadingSubs = true;
      _step = _InvoiceStep.offer;
    });
    try {
      final subs = await widget.subscriptionService
          .fetchUserSubscriptions(member.id);
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

  void _toggleOffer(UserSubscription sub) {
    setState(() {
      final idx = _selectedSubs.indexWhere((s) => s.id == sub.id);
      if (idx >= 0) {
        _selectedSubs.removeAt(idx);
      } else {
        _selectedSubs.add(sub);
      }
      _error = '';
    });
  }

  Future<void> _confirmOfferSelection() async {
    if (_selectedSubs.isEmpty) return;
    // Validate all selected offers share the same currency.
    final currencies = _selectedSubs.map((s) => s.currency).toSet();
    if (currencies.length > 1) {
      setState(() => _error =
          'All selected offers must use the same currency (${currencies.join(', ')} found).');
      return;
    }
    // Pre-load the invoice number hint (without consuming the counter) and the
    // fiscal defaults (stamp duty + TVA rate) for the confirm step.
    try {
      final hint = await widget.billingService.previewNextInvoiceNumber();
      final settings = await widget.billingService.getInvoiceSettings();
      if (mounted) {
        setState(() {
          _invoiceNumberHint = hint;
          _stampDefault = settings.stampDuty;
          _vatDefault = settings.defaultVatRate;
          _error = '';
          _step = _InvoiceStep.confirm;
        });
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'CreateInvoiceSheet._confirmOffer');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _createInvoice(
      List<InvoiceItem> extraItems, String? customInvoiceNumber,
      num discount, num stamp, bool saveAsDraft) async {
    if (_selectedMember == null || _selectedSubs.isEmpty) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final invoice = await widget.billingService.createInvoice(
        userId: _selectedMember!.id,
        memberName: _selectedMember!.displayName,
        memberEmail: _selectedMember!.email,
        memberPhone: _selectedMember!.phoneNumber,
        memberAddress: _selectedMember!.address,
        subscriptions: _selectedSubs,
        planLabels: _selectedPlanLabels,
        notes: _notesController.text.trim(),
        extraItems: extraItems,
        customInvoiceNumber: customInvoiceNumber,
        discountAmount: discount,
        stampDuty: stamp,
        status: saveAsDraft ? InvoiceStatus.draft : InvoiceStatus.unpaid,
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
        // Keep _selectedSubs so user sees their previous selection.
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
                            selectedIds:
                                _selectedSubs.map((s) => s.id).toSet(),
                            onToggle: _toggleOffer,
                            onConfirm: _confirmOfferSelection,
                            error: _error,
                            l10n: l10n,
                          )
                        : _ConfirmStep(
                            member: _selectedMember!,
                            subs: _selectedSubs,
                            plans: _selectedPlans,
                            invoiceNumberHint: _invoiceNumberHint,
                            defaultStampDuty: _stampDefault,
                            defaultVatRate: _vatDefault,
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
    required this.selectedIds,
    required this.onToggle,
    required this.onConfirm,
    required this.error,
    required this.l10n,
  });
  final AppUser member;
  final List<UserSubscription> subs;
  final List<MembershipPlan> plans;
  final bool loading;
  final Set<String> selectedIds;
  final void Function(UserSubscription) onToggle;
  final VoidCallback onConfirm;
  final String error;
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

    final count = selectedIds.length;

    return Column(
      children: [
        // Offer list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            itemCount: subs.length,
            itemBuilder: (_, i) {
              final sub = subs[i];
              final plan = _planFor(sub);
              final isSelected = selectedIds.contains(sub.id);
              return _OfferCard(
                sub: sub,
                plan: plan,
                isSelected: isSelected,
                l10n: l10n,
                onTap: () => onToggle(sub),
              );
            },
          ),
        ),
        // Error banner
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child:
                  Text(error, style: TextStyle(color: Colors.red.shade700)),
            ),
          ),
        // Continue button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: count > 0 ? onConfirm : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                count == 0
                    ? l10n.tr('Select at least one offer')
                    : count == 1
                        ? l10n.tr('Continue with 1 offer')
                        : l10n.tr('Continue with $count offers'),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.sub,
    required this.plan,
    required this.isSelected,
    required this.l10n,
    required this.onTap,
  });
  final UserSubscription sub;
  final MembershipPlan? plan;
  final bool isSelected;
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
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF0F766E)
              : statusColor.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Plan name + selected check + status chip
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0F766E).withValues(alpha: 0.15)
                          : const Color(0xFF0F766E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.card_membership,
                      size: 18,
                      color: const Color(0xFF0F766E),
                    ),
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
                      value: Currency.format(total, sub.currency),
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Expanded(
                    child: _AmountCell(
                      label: l10n.tr('Paid'),
                      value: Currency.format(paid, sub.currency),
                      color: Colors.green.shade700,
                    ),
                  ),
                  Expanded(
                    child: _AmountCell(
                      label: l10n.tr('Balance'),
                      value: Currency.format(remaining, sub.currency),
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
              // Toggle button
              Align(
                alignment: Alignment.centerRight,
                child: isSelected
                    ? OutlinedButton.icon(
                        onPressed: onTap,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade600,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.remove_circle_outline, size: 16),
                        label: Text(l10n.tr('Remove'),
                            style: const TextStyle(fontSize: 13)),
                      )
                    : FilledButton.icon(
                        onPressed: onTap,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.add_circle_outline, size: 16),
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

/// Read-only summary of one subscription inside the confirm step.
class _OfferSummaryRow extends StatelessWidget {
  const _OfferSummaryRow({
    required this.sub,
    required this.plan,
    required this.currency,
    required this.dateFmt,
    required this.l10n,
  });
  final UserSubscription sub;
  final MembershipPlan? plan;
  final String currency;
  final DateFormat dateFmt;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan?.name ?? sub.planId,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        if (plan != null)
          Text(plan!.offerTypeLabel,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 11, color: Colors.grey.shade400),
            const SizedBox(width: 4),
            Text(
              '${sub.startDate != null ? dateFmt.format(sub.startDate!) : '—'}  →  '
              '${sub.endDate != null ? dateFmt.format(sub.endDate!) : l10n.tr('Open-ended')}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          Currency.format(sub.totalAmount, currency),
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Colors.grey.shade800),
        ),
      ],
    );
  }
}

/// Controllers for one extra line-item row (description, amount, taxRate).
class _ItemRowControllers {
  _ItemRowControllers({int vatRate = 0})
      : desc = TextEditingController(),
        amount = TextEditingController(),
        taxRate = TextEditingController(text: '$vatRate');
  final TextEditingController desc;
  final TextEditingController amount;
  final TextEditingController taxRate;
  void dispose() {
    desc.dispose();
    amount.dispose();
    taxRate.dispose();
  }
}

class _ConfirmStep extends StatefulWidget {
  const _ConfirmStep({
    required this.member,
    required this.subs,
    required this.plans,
    required this.invoiceNumberHint,
    required this.defaultStampDuty,
    required this.defaultVatRate,
    required this.notesController,
    required this.error,
    required this.saving,
    required this.l10n,
    required this.onSubmit,
  });
  final AppUser member;
  final List<UserSubscription> subs;
  final List<MembershipPlan?> plans;
  final String invoiceNumberHint;

  /// Fiscal stamp (droit de timbre) pre-filled from gym settings.
  final num defaultStampDuty;

  /// TVA rate (%) pre-filled for new line items.
  final int defaultVatRate;
  final TextEditingController notesController;
  final String error;
  final bool saving;
  final AppLocalizations l10n;
  /// Called with extra items, optional custom invoice number, discount amount,
  /// stamp duty, and saveAsDraft flag.
  final void Function(List<InvoiceItem>, String?, num, num, bool) onSubmit;

  @override
  State<_ConfirmStep> createState() => _ConfirmStepState();
}

class _ConfirmStepState extends State<_ConfirmStep> {
  final List<_ItemRowControllers> _extraRows = [];
  late final TextEditingController _invoiceNumberController;
  final _discountCtrl = TextEditingController(text: '0');
  late final TextEditingController _stampCtrl;
  bool _saveAsDraft = false;

  @override
  void initState() {
    super.initState();
    _invoiceNumberController =
        TextEditingController(text: widget.invoiceNumberHint);
    _stampCtrl = TextEditingController(
        text: Currency.formatAmount(widget.defaultStampDuty, maxDecimals: 3));
  }

  @override
  void dispose() {
    for (final row in _extraRows) {
      row.dispose();
    }
    _invoiceNumberController.dispose();
    _discountCtrl.dispose();
    _stampCtrl.dispose();
    super.dispose();
  }

  void _addRow() {
    final row = _ItemRowControllers(vatRate: widget.defaultVatRate);
    row.amount.addListener(() => setState(() {}));
    row.taxRate.addListener(() => setState(() {}));
    setState(() => _extraRows.add(row));
  }

  void _removeRow(int index) {
    setState(() {
      _extraRows.removeAt(index).dispose();
    });
  }


  num get _discount =>
      (Currency.parse(_discountCtrl.text) ?? 0).clamp(0, 999999);

  num get _stamp => (Currency.parse(_stampCtrl.text) ?? 0).clamp(0, 999999);

  List<InvoiceItem> _buildExtraItems() {
    final currency = widget.subs.first.currency;
    final result = <InvoiceItem>[];
    for (final row in _extraRows) {
      final desc = row.desc.text.trim();
      final amt = Currency.parse(row.amount.text) ?? 0;
      final tax = (int.tryParse(row.taxRate.text.trim()) ?? 0).clamp(0, 100);
      if (desc.isNotEmpty && amt > 0) {
        result.add(InvoiceItem(
            description: desc, amount: amt, currency: currency, taxRate: tax));
      }
    }
    return result;
  }

  /// Returns the custom invoice number if the admin changed it from the hint,
  /// or null to use auto-generated numbering.
  String? _customInvoiceNumber() {
    final text = _invoiceNumberController.text.trim();
    return (text.isNotEmpty && text != widget.invoiceNumberHint) ? text : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final dateFmt = DateFormat('d MMM yyyy');
    final currency = widget.subs.first.currency;
    final baseTotal =
        widget.subs.fold<num>(0, (acc, s) => acc + s.totalAmount);
    final extraSubtotal = _extraRows.fold<num>(
        0, (s, r) => s + (Currency.parse(r.amount.text) ?? 0));
    final extraTax = _extraRows.fold<num>(0, (s, r) {
      final amt = Currency.parse(r.amount.text) ?? 0;
      final tax = (int.tryParse(r.taxRate.text.trim()) ?? 0).clamp(0, 100);
      return s + Currency.roundMillimes(amt * tax / 100);
    });
    final subtotal = baseTotal + extraSubtotal;
    final stamp = _stamp;
    final total = Currency.roundMillimes(
        (subtotal + extraTax + stamp - _discount).clamp(0, 999999999));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Invoice Number ───────────────────────────────────────────────
          _PreviewSection(
            icon: Icons.tag,
            title: l10n.tr('Invoice Number'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                _invoiceNumberController.text.isNotEmpty
                    ? _invoiceNumberController.text
                    : widget.invoiceNumberHint,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Member ──────────────────────────────────────────────────────
          _PreviewSection(
            icon: Icons.person_outline,
            title: l10n.tr('Member'),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor:
                    const Color(0xFF0F766E).withValues(alpha: 0.1),
                child: Text(
                  widget.member.displayName.isNotEmpty
                      ? widget.member.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Color(0xFF0F766E), fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(widget.member.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(widget.member.email,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 12),
          // ── Selected Offers ──────────────────────────────────────────────
          _PreviewSection(
            icon: Icons.card_membership_outlined,
            title: l10n.tr(widget.subs.length == 1
                ? 'Offer'
                : 'Offers (${widget.subs.length})'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < widget.subs.length; i++) ...[
                  if (i > 0) const Divider(height: 14),
                  _OfferSummaryRow(
                    sub: widget.subs[i],
                    plan: i < widget.plans.length ? widget.plans[i] : null,
                    currency: currency,
                    dateFmt: dateFmt,
                    l10n: l10n,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── Extra items ──────────────────────────────────────────────────
          _PreviewSection(
            icon: Icons.add_shopping_cart_outlined,
            title: l10n.tr('Additional Items'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_extraRows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l10n.tr('No additional items'),
                      style:
                          const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                for (int i = 0; i < _extraRows.length; i++) ...[
                  _ExtraItemRow(
                    key: ValueKey(i),
                    row: _extraRows[i],
                    currency: currency,
                    onRemove: () => _removeRow(i),
                    l10n: l10n,
                  ),
                  const SizedBox(height: 8),
                ],
                TextButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.tr('Add Item')),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── Discount ─────────────────────────────────────────────────────
          _PreviewSection(
            icon: Icons.local_offer_outlined,
            title: l10n.tr('Discount'),
            child: TextField(
              controller: _discountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixText: '${Currency.normalize(currency)} ',
                hintText: '0',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Timbre fiscal (fiscal stamp) ─────────────────────────────────
          _PreviewSection(
            icon: Icons.receipt_outlined,
            title: l10n.tr('Timbre Fiscal'),
            child: TextField(
              controller: _stampCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixText: '${Currency.normalize(currency)} ',
                hintText: '0',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Invoice total preview ────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F4C45).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF0F4C45).withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                _TotalPreviewRow(
                    label: l10n.tr('Subtotal'), value: Currency.format(subtotal, currency)),
                if (extraTax > 0) ...[
                  const SizedBox(height: 4),
                  _TotalPreviewRow(
                      label: l10n.tr('VAT / Tax'),
                      value: '+ ${Currency.format(extraTax, currency)}'),
                ],
                if (_discount > 0) ...[
                  const SizedBox(height: 4),
                  _TotalPreviewRow(
                      label: l10n.tr('Discount'),
                      value: '− ${Currency.format(_discount, currency)}'),
                ],
                if (stamp > 0) ...[
                  const SizedBox(height: 4),
                  _TotalPreviewRow(
                      label: l10n.tr('Timbre Fiscal'),
                      value: '+ ${Currency.format(stamp, currency)}'),
                ],
                const Divider(height: 16),
                _TotalPreviewRow(
                  label: l10n.tr('Total'),
                  value: Currency.format(total, currency),
                  bold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── Save as draft toggle ─────────────────────────────────────────
          SwitchListTile(
            value: _saveAsDraft,
            onChanged: (v) => setState(() => _saveAsDraft = v),
            title: Text(l10n.tr('Save as Draft'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(l10n.tr(
                'Draft invoices are not sent to the member automatically')),
            activeColor: const Color(0xFF0F766E),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          // ── Notes ────────────────────────────────────────────────────────
          _PreviewSection(
            icon: Icons.notes_outlined,
            title: l10n.tr('Notes (optional)'),
            child: TextField(
              controller: widget.notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: l10n.tr('Add a note to this invoice…'),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── Error ────────────────────────────────────────────────────────
          if (widget.error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(widget.error,
                  style: TextStyle(color: Colors.red.shade700)),
            ),
          // ── Generate button ──────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: widget.saving
                  ? null
                  : () => widget.onSubmit(_buildExtraItems(),
                      _customInvoiceNumber(), _discount, _stamp, _saveAsDraft),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: widget.saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.receipt_long_outlined),
              label: Text(
                widget.saving
                    ? l10n.tr('Generating…')
                    : _saveAsDraft
                        ? l10n.tr('Save as Draft')
                        : l10n.tr('Generate Invoice'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the extra-items editor.
class _ExtraItemRow extends StatelessWidget {
  const _ExtraItemRow({
    super.key,
    required this.row,
    required this.currency,
    required this.onRemove,
    required this.l10n,
  });
  final _ItemRowControllers row;
  final String currency;
  final VoidCallback onRemove;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: row.desc,
                decoration: InputDecoration(
                  hintText: l10n.tr('Description'),
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: TextField(
                controller: row.amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: l10n.tr('Amount'),
                  prefixText: '${Currency.normalize(currency)} ',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 64,
              child: TextField(
                controller: row.taxRate,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: '%',
                  labelText: l10n.tr('TVA'),
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              padding: const EdgeInsets.only(left: 4),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        // TVA quick-presets (Tunisian rates).
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Wrap(
              spacing: 6,
              children: [7, 13, 19].map((rate) {
                return ChoiceChip(
                  label: Text('$rate%', style: const TextStyle(fontSize: 11)),
                  selected: row.taxRate.text.trim() == '$rate',
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => row.taxRate.text = '$rate',
                  selectedColor: const Color(0xFF0F766E).withValues(alpha: 0.15),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _TotalPreviewRow extends StatelessWidget {
  const _TotalPreviewRow(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: bold ? 14 : 13,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
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
                            Currency.format(inv.totalAmount, inv.currency),
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
                                ? Currency.format(
                                    inv.remainingAmount, inv.currency)
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
  final _companyCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _matriculeCtrl = TextEditingController();
  final _stampCtrl = TextEditingController();
  final _vatCtrl = TextEditingController();
  bool _resetCounter = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _currentNextSeq = 1;
  int _padding = 4;
  String? _activePreset; // 'inv' | 'year' | 'yearmonth' | null (custom)

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _startCtrl.dispose();
    _companyCtrl.dispose();
    _addressCtrl.dispose();
    _matriculeCtrl.dispose();
    _stampCtrl.dispose();
    _vatCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.billing.getInvoiceSettings();
      if (!mounted) return;
      setState(() {
        _prefixCtrl.text = settings.prefix;
        _startCtrl.text = settings.startNumber.toString();
        _companyCtrl.text = settings.companyName;
        _addressCtrl.text = settings.companyAddress;
        _matriculeCtrl.text = settings.matriculeFiscal;
        // Suggest the Tunisian standard stamp (1.000) when none is configured
        // yet; it is only charged once the admin saves a non-zero value.
        _stampCtrl.text = Currency.formatAmount(
            settings.stampDuty > 0
                ? settings.stampDuty
                : InvoiceSettings.suggestedStampDutyTND,
            maxDecimals: 3);
        _vatCtrl.text = settings.defaultVatRate.toString();
        _currentNextSeq = settings.nextSequence;
        _padding = settings.padding;
        _activePreset = _detectPreset(settings.prefix);
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

  String? _detectPreset(String prefix) {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    if (prefix == 'INV-') return 'inv';
    if (prefix == '$year-') return 'year';
    if (prefix == '$year-$month-') return 'yearmonth';
    return null;
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    setState(() {
      _activePreset = preset;
      switch (preset) {
        case 'inv':
          _prefixCtrl.text = 'INV-';
        case 'year':
          _prefixCtrl.text = '$year-';
        case 'yearmonth':
          _prefixCtrl.text = '$year-$month-';
      }
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final prefix = _prefixCtrl.text;
    final startNumber = int.tryParse(_startCtrl.text.trim());

    if (prefix.isEmpty) {
      setState(() => _error = l10n.tr('Prefix cannot be empty.'));
      return;
    }
    if (startNumber == null || startNumber < 1) {
      setState(() => _error = l10n.tr('Start number must be a positive integer.'));
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
        padding: _padding,
        resetCounter: _resetCounter,
        companyName: _companyCtrl.text.trim(),
        companyAddress: _addressCtrl.text.trim(),
        matriculeFiscal: _matriculeCtrl.text.trim(),
        stampDuty: Currency.parse(_stampCtrl.text) ?? 0,
        defaultVatRate: (int.tryParse(_vatCtrl.text.trim()) ?? 19).clamp(0, 100),
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

  String get _preview {
    final prefix = _prefixCtrl.text.isEmpty ? 'INV-' : _prefixCtrl.text;
    final seq = _resetCounter
        ? (int.tryParse(_startCtrl.text.trim()) ?? 1)
        : _currentNextSeq;
    return '$prefix${seq.toString().padLeft(_padding, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');

    final presets = [
      (id: 'inv', label: 'INV-', sample: 'INV-'),
      (id: 'year', label: '$year-', sample: '$year-'),
      (id: 'yearmonth', label: '$year-$month-', sample: '$year-$month-'),
    ];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.receipt_long_outlined,
                color: Color(0xFF0F766E), size: 20),
          ),
          const SizedBox(width: 10),
          Text(l10n.tr('Invoice Settings'),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Quick Presets ───────────────────────────────────────
                    _SettingsLabel(l10n.tr('Quick Presets')),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...presets.map((p) {
                          final active = _activePreset == p.id;
                          return _PresetChip(
                            label: p.label,
                            active: active,
                            onTap: () => _applyPreset(p.id),
                          );
                        }),
                        _PresetChip(
                          label: l10n.tr('Custom'),
                          icon: Icons.edit_outlined,
                          active: _activePreset == null,
                          onTap: () => setState(() => _activePreset = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // ── Prefix ──────────────────────────────────────────────
                    _SettingsLabel(l10n.tr('Prefix')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _prefixCtrl,
                      decoration: InputDecoration(
                        hintText: 'INV-',
                        helperText: l10n.tr(
                            'Appears before the number — include any separators (e.g. INV-, 2026-06-)'),
                        helperMaxLines: 2,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFF0F766E), width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      onChanged: (_) => setState(() => _activePreset = null),
                    ),
                    const SizedBox(height: 20),
                    // ── Sequence Length ──────────────────────────────────────
                    _SettingsLabel(l10n.tr('Sequence Length')),
                    const SizedBox(height: 8),
                    Row(
                      children: [3, 4, 5, 6].map((digits) {
                        final active = _padding == digits;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _padding = digits),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: active
                                    ? const Color(0xFF0F766E)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: active
                                      ? const Color(0xFF0F766E)
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${'0' * (digits - 1)}1',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: active
                                          ? Colors.white
                                          : Colors.black87,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '$digits ${l10n.tr('digits')}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: active
                                          ? Colors.white70
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    // ── Starting Number ─────────────────────────────────────
                    _SettingsLabel(l10n.tr('Starting Number')),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _startCtrl,
                        decoration: InputDecoration(
                          hintText: '1',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFF0F766E), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Reset Counter ───────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: CheckboxListTile(
                        value: _resetCounter,
                        onChanged: (v) =>
                            setState(() => _resetCounter = v ?? false),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: const Color(0xFF0F766E),
                        title: Text(l10n.tr('Reset counter to start number'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${l10n.tr('Current next')}: #${_currentNextSeq.toString().padLeft(_padding, '0')}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── Fiscal identity (Tunisia) ───────────────────────────
                    _SettingsLabel(l10n.tr('Fiscal (Tunisia)')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _companyCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.tr('Company Name'),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: l10n.tr('Company Address'),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _matriculeCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.tr('Matricule Fiscal'),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stampCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText: l10n.tr('Timbre Fiscal'),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _vatCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l10n.tr('Default TVA'),
                              suffixText: '%',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── Live Preview ────────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE6F4F1), Color(0xFFF0FAF8)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.visibility_outlined,
                              size: 18, color: Color(0xFF0F766E)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.tr('Next invoice number'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _preview,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F766E),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
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
              backgroundColor: const Color(0xFF0F766E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
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

// ── Small helpers ─────────────────────────────────────────────────────────────

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.8,
        ),
      );
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF0F766E)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? const Color(0xFF0F766E)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 13,
                  color: active ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
