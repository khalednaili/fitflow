import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/invoice.dart';
import '../../../models/membership_plan.dart';
import '../../../models/user_subscription.dart';
import '../../../services/billing_service.dart';
import '../../../services/member_service.dart';
import '../../../services/subscription_service.dart';
import '../member_detail_screen.dart';

// ─────────────────────────────────────────────
//  Data holder – merges three live streams
// ─────────────────────────────────────────────
class _FinanceData {
  const _FinanceData({
    required this.subs,
    required this.membersById,
    required this.plansById,
  });
  final List<UserSubscription> subs;
  final Map<String, AppUser> membersById;
  final Map<String, MembershipPlan> plansById;
}

// ─────────────────────────────────────────────
//  Period filter values
// ─────────────────────────────────────────────
enum _Period { today, week, month, all }

extension _PeriodLabel on _Period {
  String get label => switch (this) {
        _Period.today => 'Today',
        _Period.week => 'This Week',
        _Period.month => 'This Month',
        _Period.all => 'All Time',
      };
}

// ─────────────────────────────────────────────
//  Main widget
// ─────────────────────────────────────────────
class AdminFinanceTab extends StatefulWidget {
  const AdminFinanceTab({super.key, required this.gymId});
  final String gymId;

  @override
  State<AdminFinanceTab> createState() => _AdminFinanceTabState();
}

class _AdminFinanceTabState extends State<AdminFinanceTab> {
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);
  late final _memberService = MemberService(gymId: widget.gymId);
  late final _billingService = BillingService(gymId: widget.gymId);

  _Period _period = _Period.month;
  RevenueStats? _stats;
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _loadingStats = true);
    final stats = await _billingService.computeRevenueStats();
    if (mounted) setState(() { _stats = stats; _loadingStats = false; });
  }

  bool _inPeriod(DateTime? dt) {
    if (dt == null) return false;
    final now = DateTime.now();
    return switch (_period) {
      _Period.today => dt.year == now.year && dt.month == now.month && dt.day == now.day,
      _Period.week => now.difference(dt).inDays <= 7,
      _Period.month => now.difference(dt).inDays <= 30,
      _Period.all => true,
    };
  }

  void _openMember(BuildContext context, AppUser member) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close',
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => Center(
          child: Container(
            width: width * 0.85,
            height: MediaQuery.sizeOf(context).height * 0.88,
            constraints: const BoxConstraints(maxWidth: 1280),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
            child: MemberDetailScreen(member: member, asDialog: true),
          ),
        ),
        transitionBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child),
        ),
      );
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MemberDetailScreen(member: member),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<UserSubscription>>(
            stream: _subscriptionService.streamAllUserSubscriptions(),
            builder: (context, subSnap) {
              return StreamBuilder<List<AppUser>>(
                stream: _memberService.streamMembers(),
                builder: (context, memberSnap) {
                  return StreamBuilder<List<MembershipPlan>>(
                    stream: _subscriptionService.streamAllOffers(),
                    builder: (context, planSnap) {
                      final data = _FinanceData(
                        subs: subSnap.data ?? [],
                        membersById: {
                          for (final m in memberSnap.data ?? <AppUser>[]) m.id: m,
                        },
                        plansById: {
                          for (final p in planSnap.data ?? <MembershipPlan>[]) p.id: p,
                        },
                      );
                      return _FinanceContent(
                        data: data,
                        stats: _stats,
                        loadingStats: _loadingStats,
                        period: _period,
                        inPeriod: _inPeriod,
                        onPeriodChanged: (p) => setState(() => _period = p),
                        onRefreshStats: _loadStats,
                        onOpenMember: _openMember,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Stateless content shell (receives all data)
// ─────────────────────────────────────────────
class _FinanceContent extends StatelessWidget {
  const _FinanceContent({
    required this.data,
    required this.stats,
    required this.loadingStats,
    required this.period,
    required this.inPeriod,
    required this.onPeriodChanged,
    required this.onRefreshStats,
    required this.onOpenMember,
  });

  final _FinanceData data;
  final RevenueStats? stats;
  final bool loadingStats;
  final _Period period;
  final bool Function(DateTime?) inPeriod;
  final ValueChanged<_Period> onPeriodChanged;
  final VoidCallback onRefreshStats;
  final void Function(BuildContext, AppUser) onOpenMember;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // ── New purchases in selected period ──
    final newOffers = data.subs
        .where((s) => inPeriod(s.startDate))
        .toList()
      ..sort((a, b) => (b.startDate ?? now).compareTo(a.startDate ?? now));

    // ── Outstanding balances (non-cancelled, have debt) ──
    final outstanding = data.subs
        .where((s) => s.remainingAmount > 0 && s.status != 'cancelled')
        .toList()
      ..sort((a, b) => b.remainingAmount.compareTo(a.remainingAmount));

    // ── Expiring in 30 days ──
    final expiring = data.subs
        .where((s) =>
            s.endDate != null &&
            s.status == 'active' &&
            s.endDate!.isAfter(now) &&
            s.endDate!.difference(now).inDays <= 30)
        .toList()
      ..sort((a, b) => a.endDate!.compareTo(b.endDate!));

    // ── Collection rate from live subs ──
    final totalPaid = data.subs.fold<int>(0, (sum, s) => sum + s.amountPaid);
    final totalDue = data.subs.fold<int>(0, (sum, s) => sum + s.totalAmount);
    final collectionRate = totalDue > 0 ? (totalPaid / totalDue * 100) : 0.0;

    final currency = stats?.currency ?? '';
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return CustomScrollView(
      slivers: [
        // ── Top padding ──
        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // ── KPI row ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _KpiRow(
              stats: stats,
              loading: loadingStats,
              collectionRate: collectionRate,
              currency: currency,
              onRefresh: onRefreshStats,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Period filter + "New Offer Purchases" header ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const _SectionIcon(icon: Icons.trending_up_rounded, color: Color(0xFF0F766E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'New Offer Purchases',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                _PeriodSelector(value: period, onChanged: onPeriodChanged),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // ── Activity feed ──
        if (newOffers.isEmpty)
          SliverToBoxAdapter(
            child: _EmptyCard(
              icon: Icons.shopping_bag_outlined,
              message: 'No new purchases ${period == _Period.today ? 'today' : 'in this period'}.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final sub = newOffers[i];
                  final member = data.membersById[sub.userId];
                  return _ActivityCard(
                    sub: sub,
                    member: member,
                    plan: data.plansById[sub.planId],
                    currency: currency,
                    onTap: member == null ? null : () => onOpenMember(context, member),
                  );
                },
                childCount: newOffers.length,
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── Outstanding + Expiry (2 columns on wide, stacked on narrow) ──
        SliverToBoxAdapter(
          child: isWide
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _OutstandingSection(
                          items: outstanding,
                          membersById: data.membersById,
                          plansById: data.plansById,
                          currency: currency,
              onOpenMember: (sub) {
                final m = data.membersById[sub.userId];
                if (m != null) onOpenMember(context, m);
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _ExpirySection(
              items: expiring,
              membersById: data.membersById,
              plansById: data.plansById,
              onOpenMember: (sub) {
                final m = data.membersById[sub.userId];
                if (m != null) onOpenMember(context, m);
              },
            ),
          ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
          _OutstandingSection(
            items: outstanding,
            membersById: data.membersById,
            plansById: data.plansById,
            currency: currency,
            onOpenMember: (sub) {
              final m = data.membersById[sub.userId];
              if (m != null) onOpenMember(context, m);
            },
          ),
          const SizedBox(height: 20),
          _ExpirySection(
            items: expiring,
            membersById: data.membersById,
            plansById: data.plansById,
            onOpenMember: (sub) {
              final m = data.membersById[sub.userId];
              if (m != null) onOpenMember(context, m);
            },
          ),
                    ],
                  ),
                ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  KPI Row
// ─────────────────────────────────────────────
class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.stats,
    required this.loading,
    required this.collectionRate,
    required this.currency,
    required this.onRefresh,
  });

  final RevenueStats? stats;
  final bool loading;
  final double collectionRate;
  final String currency;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Finance Overview',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Tooltip(
              message: 'Refresh stats',
              child: IconButton(
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
                onPressed: loading ? null : onRefresh,
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            final cards = [
              _KpiCard(
                label: 'Revenue Today',
                value: loading || s == null ? null : '${s.revenueToday} $currency',
                icon: Icons.today_rounded,
                color: const Color(0xFF0F766E),
                subtitle: loading ? null : 'vs ${s?.revenueLastMonth ?? 0} last month',
              ),
              _KpiCard(
                label: 'This Month',
                value: loading || s == null ? null : '${s.revenueThisMonth} $currency',
                icon: Icons.calendar_month_rounded,
                color: const Color(0xFF2563EB),
                subtitle: loading ? null : '${s?.newPaymentsThisMonth ?? 0} payments',
              ),
              _KpiCard(
                label: 'Outstanding',
                value: loading || s == null ? null : '${s.totalOutstanding} $currency',
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFDC2626),
                subtitle: context.l10n.tr('Balance due'),
                valueColor: s != null && s.totalOutstanding > 0 ? const Color(0xFFDC2626) : null,
              ),
              _KpiCard(
                label: 'Collection Rate',
                value: '${collectionRate.toStringAsFixed(1)}%',
                icon: Icons.percent_rounded,
                color: collectionRate >= 80
                    ? const Color(0xFF059669)
                    : collectionRate >= 50
                        ? const Color(0xFFF97316)
                        : const Color(0xFFDC2626),
                subtitle: context.l10n.tr('Paid / Total due'),
                valueColor: collectionRate >= 80
                    ? const Color(0xFF059669)
                    : collectionRate >= 50
                        ? const Color(0xFFF97316)
                        : const Color(0xFFDC2626),
              ),
            ];
            if (wide) {
              return Row(
                children: cards
                    .map((c) => Expanded(child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: c,
                        )))
                    .toList(),
              );
            }
            return GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
              children: cards,
            );
          },
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.valueColor,
  });

  final String label;
  final String? value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          value == null
              ? const SizedBox(
                  height: 14,
                  width: 60,
                  child: LinearProgressIndicator(borderRadius: BorderRadius.all(Radius.circular(4))),
                )
              : Text(
                  value!,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: valueColor,
                        fontSize: 18,
                      ),
                ),
          const SizedBox(height: 2),
          Text(
            context.l10n.tr(label),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500,
                ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Period selector
// ─────────────────────────────────────────────
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});
  final _Period value;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _Period.values.map((p) {
          final selected = p == value;
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  p.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? cs.onPrimaryContainer : cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Activity card – one subscription purchase
// ─────────────────────────────────────────────
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.sub,
    required this.member,
    required this.plan,
    required this.currency,
    required this.onTap,
  });

  final UserSubscription sub;
  final AppUser? member;
  final MembershipPlan? plan;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = member?.displayName ?? 'Unknown Member';
    final planName = plan?.name ?? sub.planId;
    final pct = sub.paymentPercentage;
    final paid = sub.amountPaid;
    final total = sub.totalAmount;
    final remaining = sub.remainingAmount;

    final statusColor = switch (sub.status) {
      'active' => const Color(0xFF059669),
      'pending' => const Color(0xFFF97316),
      'cancelled' => const Color(0xFFDC2626),
      _ => const Color(0xFF6B7280),
    };

    final startLabel = sub.startDate != null ? _formatDate(sub.startDate!) : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              _MemberAvatar(name: name, photoUrl: member?.photoUrl ?? ''),
              const SizedBox(width: 12),
              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _StatusBadge(label: sub.status, color: statusColor),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.card_membership_rounded, size: 12, color: cs.onSurface.withValues(alpha: 0.45)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            planName,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.55),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.calendar_today_rounded, size: 10, color: cs.onSurface.withValues(alpha: 0.35)),
                        const SizedBox(width: 3),
                        Text(
                          startLabel,
                          style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.45)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Payment bar
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 5,
                              backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                              valueColor: AlwaysStoppedAnimation(statusColor),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$paid / $total $currency',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: remaining > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                    if (remaining > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '$remaining $currency remaining',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.3), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Outstanding balances section
// ─────────────────────────────────────────────
class _OutstandingSection extends StatelessWidget {
  const _OutstandingSection({
    required this.items,
    required this.membersById,
    required this.plansById,
    required this.currency,
    required this.onOpenMember,
  });

  final List<UserSubscription> items;
  final Map<String, AppUser> membersById;
  final Map<String, MembershipPlan> plansById;
  final String currency;
  final ValueChanged<UserSubscription> onOpenMember;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionIcon(icon: Icons.account_balance_wallet_outlined, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Text(
              'Outstanding Balances',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            if (items.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          _EmptyCard(
            icon: Icons.check_circle_outline_rounded,
            message: 'All balances are settled!',
            color: const Color(0xFF059669),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: items.take(10).indexed.map<Widget>((entry) {
                final (i, sub) = entry;
                final member = membersById[sub.userId];
                final plan = plansById[sub.planId];
                final name = member?.displayName ?? 'Unknown';
                final planName = plan?.name ?? sub.planId;
                final isLast = i == items.take(10).length - 1;
                return Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.vertical(
                        top: i == 0 ? const Radius.circular(12) : Radius.zero,
                        bottom: isLast ? const Radius.circular(12) : Radius.zero,
                      ),
                      onTap: () => onOpenMember(sub),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            _MemberAvatar(name: name, photoUrl: member?.photoUrl ?? '', size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    planName,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: cs.onSurface.withValues(alpha: 0.5),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${sub.remainingAmount} $currency',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                                Text(
                                  'due',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurface.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_right_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast)
                      Divider(height: 1, indent: 52, color: cs.outlineVariant.withValues(alpha: 0.4)),
                  ],
                );
              }).toList(),
            ),
          ),
        if (items.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '+${items.length - 10} more — view in Members tab',
              style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4)),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Expiring soon section
// ─────────────────────────────────────────────
class _ExpirySection extends StatelessWidget {
  const _ExpirySection({
    required this.items,
    required this.membersById,
    required this.plansById,
    required this.onOpenMember,
  });

  final List<UserSubscription> items;
  final Map<String, AppUser> membersById;
  final Map<String, MembershipPlan> plansById;
  final ValueChanged<UserSubscription> onOpenMember;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionIcon(icon: Icons.timer_outlined, color: Color(0xFFF97316)),
            const SizedBox(width: 8),
            Text(
              'Expiring in 30 Days',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            if (items.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF97316),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const _EmptyCard(
            icon: Icons.event_available_outlined,
            message: 'No offers expiring in the next 30 days.',
            color: Color(0xFF0F766E),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: items.take(10).indexed.map<Widget>((entry) {
                final (i, sub) = entry;
                final member = membersById[sub.userId];
                final plan = plansById[sub.planId];
                final name = member?.displayName ?? 'Unknown';
                final planName = plan?.name ?? sub.planId;
                final daysLeft = sub.endDate!.difference(now).inDays;
                final urgentColor = daysLeft <= 7
                    ? const Color(0xFFDC2626)
                    : daysLeft <= 14
                        ? const Color(0xFFF97316)
                        : const Color(0xFF059669);
                final isLast = i == items.take(10).length - 1;
                return Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.vertical(
                        top: i == 0 ? const Radius.circular(12) : Radius.zero,
                        bottom: isLast ? const Radius.circular(12) : Radius.zero,
                      ),
                      onTap: () => onOpenMember(sub),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            _MemberAvatar(name: name, photoUrl: member?.photoUrl ?? '', size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    planName,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: cs.onSurface.withValues(alpha: 0.5),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: urgentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$daysLeft days',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: urgentColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDate(sub.endDate!),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurface.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_right_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast)
                      Divider(height: 1, indent: 52, color: cs.outlineVariant.withValues(alpha: 0.4)),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Shared small widgets
// ─────────────────────────────────────────────
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, required this.photoUrl, this.size = 38});
  final String name;
  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').take(2).join();
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(photoUrl),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF0F766E).withValues(alpha: 0.15),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.35,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0F766E),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _SectionIcon extends StatelessWidget {
  const _SectionIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message, this.color});
  final IconData icon;
  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurface.withValues(alpha: 0.3);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: c.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.45)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────
String _formatDate(DateTime dt) {
  final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}
