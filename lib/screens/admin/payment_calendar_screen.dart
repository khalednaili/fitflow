import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/membership_plan.dart';
import '../../services/member_service.dart';
import '../../services/subscription_service.dart';
import 'member_detail_screen.dart';

/// Admin screen — shows all pending (unpaid) instalments across every member,
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
  late final MemberService _memberService =
      MemberService(gymId: widget.gymId);

  Map<String, AppUser> _membersById = {};
  Map<String, String> _planNamesById = {};
  bool _metadataReady = false;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    _searchController.addListener(
        () => setState(() => _searchQuery = _searchController.text.trim()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    final results = await Future.wait([
      _memberService.fetchMembers(),
      _service.streamAllOffers().first,
    ]);
    if (!mounted) return;
    final members = results[0] as List<AppUser>;
    final plans = results[1] as List<MembershipPlan>;
    setState(() {
      _membersById = {for (final m in members) m.id: m};
      _planNamesById = {for (final p in plans) p.id: p.name};
      _metadataReady = true;
    });
  }

  Future<void> _handleMarkPaid(
      String subscriptionId, String instalmentId) async {
    await _service.markInstalmentPaid(
      subscriptionId: subscriptionId,
      instalmentId: instalmentId,
    );
  }

  Future<void> _handleEditInstalment(InstalmentWithSubscription item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditInstalmentSheet(
        item: item,
        onSave: (amount, dueDate, method, notes) async {
          await _service.updateInstalment(
            subscriptionId: item.subscription.id,
            instalmentId: item.instalment.id,
            amount: amount,
            dueDate: dueDate,
            method: method,
            notes: notes,
          );
        },
      ),
    );
  }

  void _openProfile(BuildContext context, AppUser member) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemberDetailScreen(member: member),
      ),
    );
  }

  /// Returns true when [item] matches the current [_searchQuery].
  /// Matches against member name, plan name, amount and method.
  bool _matches(InstalmentWithSubscription item) {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return true;
    final sub = item.instalment;
    final memberName = (_membersById[item.subscription.userId]?.displayName ?? item.subscription.userId).toLowerCase();
    final planName = (_planNamesById[item.subscription.planId] ?? item.subscription.planId).toLowerCase();
    final amount = '${sub.amount}';
    final method = sub.method.toLowerCase();
    return memberName.contains(q) ||
        planName.contains(q) ||
        amount.contains(q) ||
        method.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLowest,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              context.l10n.tr('Payment Calendar'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ],
        ),
        actions: [
          if (!_metadataReady)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: _loadMetadata,
          ),
        ],
      ),
      body: StreamBuilder<List<InstalmentWithSubscription>>(
        stream: _service.streamPendingInstalments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(error: '${snapshot.error}');
          }

          final all = snapshot.data ?? [];
          if (all.isEmpty) {
            return const _EmptyState();
          }

          // Apply search filter
          final filtered =
              _searchQuery.isEmpty ? all : all.where(_matches).toList();

          // Group by status
          final overdue = <InstalmentWithSubscription>[];
          final dueToday = <InstalmentWithSubscription>[];
          final upcoming = <InstalmentWithSubscription>[];

          for (final item in filtered) {
            final d = item.instalment.dueDate;
            final due = DateTime(d.year, d.month, d.day);
            if (due.isBefore(todayDate)) {
              overdue.add(item);
            } else if (due.isAtSameMomentAs(todayDate)) {
              dueToday.add(item);
            } else {
              upcoming.add(item);
            }
          }

          int groupTotal(List<InstalmentWithSubscription> g) =>
              g.fold(0, (s, i) => s + i.instalment.amount);

          final currency = all.first.subscription.currency;
          final hasResults =
              overdue.isNotEmpty || dueToday.isNotEmpty || upcoming.isNotEmpty;

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 760;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryBar(
                    overdueCount: overdue.length,
                    overdueTotal: groupTotal(overdue),
                    todayCount: dueToday.length,
                    todayTotal: groupTotal(dueToday),
                    upcomingCount: upcoming.length,
                    upcomingTotal: groupTotal(upcoming),
                    currency: currency,
                  ),
                  // ── Search bar ────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        isWide ? 24 : 16, 12, isWide ? 24 : 16, 4),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: context.l10n.tr(
                            'Search by member, plan, amount or method…'),
                        hintStyle: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant
                                .withValues(alpha: 0.6)),
                        prefixIcon: Icon(Icons.search_outlined,
                            size: 20, color: cs.onSurfaceVariant),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close,
                                    size: 18,
                                    color: cs.onSurfaceVariant),
                                tooltip:
                                    context.l10n.tr('Clear search'),
                                onPressed: () =>
                                    _searchController.clear(),
                              )
                            : null,
                        filled: true,
                        fillColor: cs.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: cs.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  // ── No results state ──────────────────────────────
                  if (!hasResults)
                    Expanded(
                      child: _NoResultsState(query: _searchQuery),
                    )
                  else
                    Expanded(
                      child: ListView(
                      padding: EdgeInsets.fromLTRB(
                          isWide ? 24 : 16, 16, isWide ? 24 : 16, 32),
                      children: [
                        if (overdue.isNotEmpty) ...[
                          _GroupHeader(
                            icon: Icons.warning_amber_rounded,
                            label: context.l10n.tr('Overdue'),
                            count: overdue.length,
                            color: cs.error,
                          ),
                          const SizedBox(height: 10),
                          _TileGrid(
                            items: overdue,
                            statusColor: cs.error,
                            statusIcon: Icons.warning_amber_outlined,
                            membersById: _membersById,
                            planNamesById: _planNamesById,
                            todayDate: todayDate,
                            isWide: isWide,
                            onMarkPaid: _handleMarkPaid,
                            onViewProfile: (m) => _openProfile(context, m),
                            onEditInstalment: _handleEditInstalment,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (dueToday.isNotEmpty) ...[
                          _GroupHeader(
                            icon: Icons.today_outlined,
                            label: context.l10n.tr('Due Today'),
                            count: dueToday.length,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(height: 10),
                          _TileGrid(
                            items: dueToday,
                            statusColor: Colors.orange.shade700,
                            statusIcon: Icons.today_outlined,
                            membersById: _membersById,
                            planNamesById: _planNamesById,
                            todayDate: todayDate,
                            isWide: isWide,
                            onMarkPaid: _handleMarkPaid,
                            onViewProfile: (m) => _openProfile(context, m),
                            onEditInstalment: _handleEditInstalment,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (upcoming.isNotEmpty) ...[
                          _GroupHeader(
                            icon: Icons.schedule_outlined,
                            label: context.l10n.tr('Upcoming'),
                            count: upcoming.length,
                            color: cs.primary,
                          ),
                          const SizedBox(height: 10),
                          _TileGrid(
                            items: upcoming,
                            statusColor: cs.primary,
                            statusIcon: Icons.schedule_outlined,
                            membersById: _membersById,
                            planNamesById: _planNamesById,
                            todayDate: todayDate,
                            isWide: isWide,
                            onMarkPaid: _handleMarkPaid,
                            onViewProfile: (m) => _openProfile(context, m),
                            onEditInstalment: _handleEditInstalment,
                          ),
                        ],
                      ],
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// _SummaryBar
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.overdueCount,
    required this.overdueTotal,
    required this.todayCount,
    required this.todayTotal,
    required this.upcomingCount,
    required this.upcomingTotal,
    required this.currency,
  });

  final int overdueCount, overdueTotal;
  final int todayCount, todayTotal;
  final int upcomingCount, upcomingTotal;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
            bottom:
                BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _SummaryChip(
            label: context.l10n.tr('Overdue'),
            count: overdueCount,
            amount: overdueTotal,
            currency: currency,
            color: cs.error,
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(width: 10),
          _SummaryChip(
            label: context.l10n.tr('Today'),
            count: todayCount,
            amount: todayTotal,
            currency: currency,
            color: Colors.orange.shade700,
            icon: Icons.today_outlined,
          ),
          const SizedBox(width: 10),
          _SummaryChip(
            label: context.l10n.tr('Upcoming'),
            count: upcomingCount,
            amount: upcomingTotal,
            currency: currency,
            color: cs.primary,
            icon: Icons.schedule_outlined,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.amount,
    required this.currency,
    required this.color,
    required this.icon,
  });

  final String label;
  final int count, amount;
  final String currency;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                          letterSpacing: 0.4)),
                  Text(
                    count == 0
                        ? context.l10n.tr('None')
                        : '$count  ·  $amount $currency',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: count == 0
                            ? color.withValues(alpha: 0.4)
                            : color),
                    overflow: TextOverflow.ellipsis,
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

// ─────────────────────────────────────────────────────────────────────────────
// _GroupHeader
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
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 7),
        Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: color.withValues(alpha: 0.12),
          ),
          child: Text('$count',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: color.withValues(alpha: 0.25))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TileGrid — responsive 1-col / 2-col
// ─────────────────────────────────────────────────────────────────────────────

class _TileGrid extends StatelessWidget {
  const _TileGrid({
    required this.items,
    required this.statusColor,
    required this.statusIcon,
    required this.membersById,
    required this.planNamesById,
    required this.todayDate,
    required this.isWide,
    required this.onMarkPaid,
    required this.onViewProfile,
    required this.onEditInstalment,
  });

  final List<InstalmentWithSubscription> items;
  final Color statusColor;
  final IconData statusIcon;
  final Map<String, AppUser> membersById;
  final Map<String, String> planNamesById;
  final DateTime todayDate;
  final bool isWide;
  final Future<void> Function(String subId, String instId) onMarkPaid;
  final void Function(AppUser) onViewProfile;
  final Future<void> Function(InstalmentWithSubscription item) onEditInstalment;

  Widget _tile(InstalmentWithSubscription item) => _InstalmentTile(
        item: item,
        statusColor: statusColor,
        statusIcon: statusIcon,
        member: membersById[item.subscription.userId],
        planName: planNamesById[item.subscription.planId],
        todayDate: todayDate,
        onMarkPaid: onMarkPaid,
        onViewProfile: onViewProfile,
        onEditInstalment: onEditInstalment,
      );

  @override
  Widget build(BuildContext context) {
    if (!isWide) {
      return Column(children: items.map(_tile).toList());
    }
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _tile(items[i])),
            const SizedBox(width: 12),
            Expanded(
                child: i + 1 < items.length
                    ? _tile(items[i + 1])
                    : const SizedBox.shrink()),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InstalmentTile
// ─────────────────────────────────────────────────────────────────────────────

class _InstalmentTile extends StatefulWidget {
  const _InstalmentTile({
    required this.item,
    required this.statusColor,
    required this.statusIcon,
    required this.todayDate,
    required this.onMarkPaid,
    required this.onViewProfile,
    required this.onEditInstalment,
    this.member,
    this.planName,
  });

  final InstalmentWithSubscription item;
  final Color statusColor;
  final IconData statusIcon;
  final AppUser? member;
  final String? planName;
  final DateTime todayDate;
  final Future<void> Function(String subId, String instId) onMarkPaid;
  final void Function(AppUser) onViewProfile;
  final Future<void> Function(InstalmentWithSubscription item) onEditInstalment;

  @override
  State<_InstalmentTile> createState() => _InstalmentTileState();
}

class _InstalmentTileState extends State<_InstalmentTile> {
  bool _loading = false;

  static const _methodIcons = <String, IconData>{
    'cash': Icons.payments_outlined,
    'card': Icons.credit_card_outlined,
    'transfer': Icons.account_balance_outlined,
    'cheque': Icons.receipt_outlined,
  };

  static const _methodLabels = <String, String>{
    'cash': 'Cash',
    'card': 'Card',
    'transfer': 'Transfer',
    'cheque': 'Cheque',
  };

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  String _daysBadge(DateTime dueDate) {
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(widget.todayDate).inDays;
    if (diff == 0) return '';
    if (diff < 0) return '${diff.abs()}d overdue';
    if (diff == 1) return 'Tomorrow';
    return 'In ${diff}d';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = widget.item.subscription;
    final inst = widget.item.instalment;
    final member = widget.member;
    final memberName = (member?.displayName.isNotEmpty == true)
        ? member!.displayName
        : sub.userId;
    final planName = widget.planName ?? sub.planId;
    final idx = sub.instalmentSchedule.indexOf(inst);
    final fmt = DateFormat('d MMM yyyy');
    final methodIcon = _methodIcons[inst.method] ?? Icons.payments_outlined;
    final methodLabel = _methodLabels[inst.method] ?? inst.method;
    final daysBadge = _daysBadge(inst.dueDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: widget.statusColor.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: cs.shadow.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Coloured top accent strip
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: widget.statusColor.withValues(alpha: 0.7),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Member row ─────────────────────────────────────────
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.statusColor.withValues(alpha: 0.1),
                        border: Border.all(
                            color: widget.statusColor.withValues(alpha: 0.35),
                            width: 2),
                      ),
                      child: Center(
                        child: Text(
                          _initials(memberName),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: widget.statusColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Name + plan
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memberName,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (planName.isNotEmpty)
                            Text(
                              planName,
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    // View profile
                    if (member != null)
                      Tooltip(
                        message: context.l10n.tr('View Profile'),
                        child: InkWell(
                          onTap: () => widget.onViewProfile(member),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color:
                                  cs.primaryContainer.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_outline,
                                    size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text(context.l10n.tr('Profile'),
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: cs.primary)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Amount + instalment progress ───────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: widget.statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                widget.statusColor.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        '${inst.amount} ${sub.currency}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: widget.statusColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${context.l10n.tr('Inst.')} ${idx >= 0 ? idx + 1 : '?'} / ${sub.instalmentSchedule.length}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant),
                      ),
                    ),
                    const Spacer(),
                    // Method
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(methodIcon,
                            size: 12, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(context.l10n.tr(methodLabel),
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // ── Due date + days badge + action ─────────────────────
                Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(fmt.format(inst.dueDate),
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                    if (daysBadge.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              widget.statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(daysBadge,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: widget.statusColor)),
                      ),
                    ],
                    const Spacer(),
                    if (_loading)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.statusColor),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Edit button
                          Tooltip(
                            message: context.l10n.tr('Edit instalment'),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                side: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline
                                        .withValues(alpha: 0.5)),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                              onPressed: () =>
                                  widget.onEditInstalment(widget.item),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.edit_outlined,
                                      size: 13),
                                  const SizedBox(width: 4),
                                  Text(context.l10n.tr('Edit'),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Mark Paid button
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.statusColor
                                  .withValues(alpha: 0.12),
                              foregroundColor: widget.statusColor,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(8)),
                            ),
                            onPressed: _confirmAndPay,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_outline,
                                    size: 14),
                                const SizedBox(width: 5),
                                Text(context.l10n.tr('Mark Paid'),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndPay() async {
    final sub = widget.item.subscription;
    final inst = widget.item.instalment;
    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: widget.statusColor),
            const SizedBox(width: 8),
            Text(context.l10n.tr('Mark as Paid')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfirmRow(
              label: context.l10n.tr('Member'),
              value: widget.member?.displayName ?? sub.userId,
            ),
            _ConfirmRow(
              label: context.l10n.tr('Amount'),
              value: '${inst.amount} ${sub.currency}',
              bold: true,
            ),
            _ConfirmRow(
              label: context.l10n.tr('Method'),
              value: _methodLabels[inst.method] ?? inst.method,
            ),
            _ConfirmRow(
              label: context.l10n.tr('Due date'),
              value: DateFormat('d MMM yyyy').format(inst.dueDate),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: widget.statusColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Confirm')),
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
        messenger.showSnackBar(SnackBar(
          content: Text('$e'),
          backgroundColor: cs.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EditInstalmentSheet — bottom sheet to edit amount / date / method / notes
// ─────────────────────────────────────────────────────────────────────────────

class _EditInstalmentSheet extends StatefulWidget {
  const _EditInstalmentSheet({required this.item, required this.onSave});

  final InstalmentWithSubscription item;
  final Future<void> Function(
      int? amount, DateTime? dueDate, String? method, String? notes) onSave;

  @override
  State<_EditInstalmentSheet> createState() => _EditInstalmentSheetState();
}

class _EditInstalmentSheetState extends State<_EditInstalmentSheet> {
  static const _methods = ['cash', 'card', 'transfer', 'cheque'];
  static const _methodLabels = {
    'cash': 'Cash',
    'card': 'Card',
    'transfer': 'Transfer',
    'cheque': 'Cheque',
  };
  static const _methodIcons = {
    'cash': Icons.payments_outlined,
    'card': Icons.credit_card_outlined,
    'transfer': Icons.account_balance_outlined,
    'cheque': Icons.receipt_outlined,
  };

  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _dueDate;
  late String _method;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final inst = widget.item.instalment;
    _amountCtrl =
        TextEditingController(text: inst.amount > 0 ? '${inst.amount}' : '');
    _notesCtrl = TextEditingController(text: inst.notes);
    _dueDate = inst.dueDate;
    _method = inst.method;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amountText = _amountCtrl.text.trim();
    final int? amount =
        amountText.isNotEmpty ? int.tryParse(amountText) : null;

    if (amountText.isNotEmpty && amount == null) {
      setState(() => _error = 'Please enter a valid amount.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSave(
        amount,
        _dueDate,
        _method,
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: Text('Instalment updated successfully.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inst = widget.item.instalment;
    final sub = widget.item.subscription;
    final fmt = DateFormat('d MMM yyyy');

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Title
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.edit_outlined,
                        size: 20, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.tr('Edit Instalment'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        Text(
                          '${inst.amount} ${sub.currency}  ·  ${fmt.format(inst.dueDate)}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Amount field
              Text(context.l10n.tr('Amount'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '${inst.amount}',
                  suffix: Text(sub.currency,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  filled: true,
                  fillColor: cs.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: cs.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Due Date picker
              Text(context.l10n.tr('Due Date'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined,
                          size: 18, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          fmt.format(_dueDate),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 18, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Payment method
              Text(context.l10n.tr('Payment Method'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _methods.map((m) {
                  final selected = m == _method;
                  return GestureDetector(
                    onTap: () => setState(() => _method = m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primaryContainer
                            : cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? cs.primary
                              : cs.outline.withValues(alpha: 0.3),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_methodIcons[m]!,
                              size: 14,
                              color: selected
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            context.l10n.tr(_methodLabels[m]!),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? cs.onPrimaryContainer
                                    : cs.onSurface),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Notes field
              Text(context.l10n.tr('Notes'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: context.l10n.tr('Optional notes…'),
                  filled: true,
                  fillColor: cs.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: cs.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 14, color: cs.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onErrorContainer))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(context.l10n.tr('Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(context.l10n.tr('Save Changes'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / Error states
// ─────────────────────────────────────────────────────────────────────────────

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: cs.surfaceContainerLow, shape: BoxShape.circle),
            child: Icon(Icons.search_off_outlined,
                size: 36, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Text(context.l10n.tr('No results found'),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            '"$query"',
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Icon(Icons.check_circle_outline,
                size: 40, color: Colors.green.shade500),
          ),
          const SizedBox(height: 20),
          Text(context.l10n.tr('All caught up!'),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            context.l10n.tr('No pending instalments at this time.'),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: cs.error),
          const SizedBox(height: 12),
          Text(context.l10n.tr('Something went wrong'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(error,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
