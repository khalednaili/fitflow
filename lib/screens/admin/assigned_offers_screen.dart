import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/membership_plan.dart';
import '../../models/user_subscription.dart';
import '../../services/member_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/user_avatar.dart';
import 'member_detail_screen.dart';
import 'record_payment_screen.dart';
import '../../l10n/app_localizations.dart';

// ── Helper ────────────────────────────────────────────────────────────────────

Color _roleColor(String role) {
  switch (role) {
    case 'admin':
    case 'owner':
      return const Color(0xFF7C3AED);
    case 'coach':
    case 'staff':
      return const Color(0xFF0F766E);
    default:
      return const Color(0xFF2563EB);
  }
}

/// Flat record joining a member + one subscription for table rows.
class _Row {
  const _Row({
    required this.member,
    required this.subscription,
    required this.plan,
  });
  final AppUser member;
  final UserSubscription subscription;
  final MembershipPlan? plan;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AssignedOffersScreen extends StatefulWidget {
  const AssignedOffersScreen({super.key, this.gymId = ''});

  final String gymId;

  @override
  State<AssignedOffersScreen> createState() => _AssignedOffersScreenState();
}

class _AssignedOffersScreenState extends State<AssignedOffersScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _filter = 'all'; // all | active | expiring | unpaid | no_plan

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filter & search ─────────────────────────────────────────────────────────

  List<_Row> _applyFilters(List<_Row> rows) {
    final q = _search.toLowerCase().trim();
    return rows.where((r) {
      // text search
      if (q.isNotEmpty) {
        final name = r.member.displayName.toLowerCase();
        final email = r.member.email.toLowerCase();
        final plan = (r.plan?.name ?? r.subscription.planId).toLowerCase();
        if (!name.contains(q) && !email.contains(q) && !plan.contains(q)) {
          return false;
        }
      }
      // status filter
      switch (_filter) {
        case 'active':
          return r.subscription.status == 'active';
        case 'expiring':
          final end = r.subscription.endDate;
          if (end == null) return false;
          final diff = end.difference(DateTime.now()).inDays;
          return diff >= 0 && diff <= 14;
        case 'unpaid':
          return r.subscription.remainingAmount > 0;
        case 'no_plan':
          return false; // handled separately
        default:
          return true;
      }
    }).toList();
  }

  // ── Stats ────────────────────────────────────────────────────────────────────

  Map<String, int> _computeStats(List<AppUser> members, List<_Row> allRows) {
    final memberIdsWithSub = allRows.map((r) => r.member.id).toSet();
    final active =
        allRows.where((r) => r.subscription.status == 'active').length;
    final unpaid =
        allRows.where((r) => r.subscription.remainingAmount > 0).length;
    final expiring = allRows.where((r) {
      final end = r.subscription.endDate;
      if (end == null) return false;
      final diff = end.difference(DateTime.now()).inDays;
      return diff >= 0 && diff <= 14;
    }).length;
    return {
      'total': members.length,
      'with_plan': memberIdsWithSub.length,
      'active': active,
      'unpaid': unpaid,
      'expiring': expiring,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 860;
    final memberSvc = MemberService(gymId: widget.gymId);
    final subSvc = SubscriptionService(gymId: widget.gymId);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLowest,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Row(
          children: [
            Icon(Icons.receipt_long_outlined, size: 20, color: cs.primary),
            const SizedBox(width: 10),
            Text(context.l10n.tr('Assigned Offers'),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ],
        ),
        actions: [
          if (isWide)
            SizedBox(
              width: 280,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: context.l10n.tr('Search member or plan…'),
                  prefixIcon:
                      Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: memberSvc.streamMembers(),
        builder: (context, membersSnap) {
          final members = membersSnap.data ?? <AppUser>[];
          final membersLoading =
              membersSnap.connectionState == ConnectionState.waiting;

          return StreamBuilder<List<UserSubscription>>(
            stream: subSvc.streamAllUserSubscriptions(),
            builder: (context, subsSnap) {
              final subs = subsSnap.data ?? <UserSubscription>[];
              final subsLoading =
                  subsSnap.connectionState == ConnectionState.waiting;

              return StreamBuilder<List<MembershipPlan>>(
                stream: subSvc.streamAllOffers(),
                builder: (context, plansSnap) {
                  if (membersLoading || subsLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final planById = <String, MembershipPlan>{
                    for (final p in plansSnap.data ?? <MembershipPlan>[])
                      p.id: p,
                  };

                  // Build flat rows (member × subscription)
                  final memberById = <String, AppUser>{
                    for (final m in members) m.id: m,
                  };
                  final allRows = subs
                      .where((s) => memberById.containsKey(s.userId))
                      .map((s) => _Row(
                            member: memberById[s.userId]!,
                            subscription: s,
                            plan: planById[s.planId],
                          ))
                      .toList()
                    ..sort((a, b) {
                      final aEnd = a.subscription.endDate ?? DateTime(2100);
                      final bEnd = b.subscription.endDate ?? DateTime(2100);
                      return aEnd.compareTo(bEnd);
                    });

                  final stats = _computeStats(members, allRows);
                  final filtered = _applyFilters(allRows);

                  return Column(
                    children: [
                      // ── Search bar (narrow) ──────────────────────────────
                      if (!isWide)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText:
                                  context.l10n.tr('Search member or plan…'),
                              prefixIcon: const Icon(Icons.search, size: 18),
                              suffixIcon: _search.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () => _searchCtrl.clear(),
                                    )
                                  : null,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              filled: true,
                              fillColor: cs.surfaceContainerHigh,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),

                      // ── Stats row ────────────────────────────────────────
                      _StatsRow(stats: stats, isWide: isWide),

                      // ── Filter chips ─────────────────────────────────────
                      _FilterBar(
                        selected: _filter,
                        stats: stats,
                        onChanged: (v) => setState(() => _filter = v),
                      ),

                      // ── Content ──────────────────────────────────────────
                      Expanded(
                        child: filtered.isEmpty
                            ? _EmptyState(filter: _filter, search: _search)
                            : isWide
                                ? _WideTable(
                                    rows: filtered,
                                    gymId: widget.gymId,
                                    memberById: memberById,
                                  )
                                : _NarrowList(
                                    rows: filtered,
                                    gymId: widget.gymId,
                                  ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats, required this.isWide});
  final Map<String, int> stats;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 16 : 12, 10, isWide ? 16 : 12, 4),
      child: Row(
        children: [
          _StatChip(
            label: 'Members',
            value: stats['total']!,
            icon: Icons.group_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'With plan',
            value: stats['with_plan']!,
            icon: Icons.card_membership_outlined,
            color: Colors.blue.shade600,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Active',
            value: stats['active']!,
            icon: Icons.check_circle_outline,
            color: Colors.green.shade600,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Unpaid',
            value: stats['unpaid']!,
            icon: Icons.warning_amber_outlined,
            color: Colors.orange.shade700,
          ),
          if (isWide) ...[
            const SizedBox(width: 8),
            _StatChip(
              label: 'Expiring ≤14d',
              value: stats['expiring']!,
              icon: Icons.schedule_outlined,
              color: Colors.red.shade600,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1.1),
                  ),
                  Text(
                    context.l10n.tr(label),
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: color.withValues(alpha: 0.8)),
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

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.stats,
    required this.onChanged,
  });
  final String selected;
  final Map<String, int> stats;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = [
      ('all', 'All', null),
      ('active', 'Active', Colors.green.shade600),
      ('expiring', 'Expiring soon', Colors.orange.shade600),
      ('unpaid', 'Unpaid balance', Colors.red.shade600),
    ];

    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: chips.map((c) {
          final isSelected = selected == c.$1;
          final color = c.$3 ?? cs.primary;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(context.l10n.tr(c.$2)),
              selected: isSelected,
              onSelected: (_) => onChanged(c.$1),
              selectedColor: color.withValues(alpha: 0.14),
              checkmarkColor: color,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : cs.onSurfaceVariant,
              ),
              side: BorderSide(
                color: isSelected
                    ? color.withValues(alpha: 0.5)
                    : cs.outlineVariant.withValues(alpha: 0.6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Wide table layout ─────────────────────────────────────────────────────────

class _WideTable extends StatelessWidget {
  const _WideTable({
    required this.rows,
    required this.gymId,
    required this.memberById,
  });
  final List<_Row> rows;
  final String gymId;
  final Map<String, AppUser> memberById;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1300),
        child: Column(
          children: [
            // Table header
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                border:
                    Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 36), // avatar
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 190,
                    child: _HeaderCell('Member'),
                  ),
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 170,
                    child: _HeaderCell('Plan'),
                  ),
                  const SizedBox(width: 12),
                  const SizedBox(width: 90, child: _HeaderCell('Status')),
                  const SizedBox(width: 12),
                  const Expanded(child: _HeaderCell('Payment')),
                  const SizedBox(width: 12),
                  const SizedBox(width: 110, child: _HeaderCell('Expires')),
                  const SizedBox(width: 12),
                  const SizedBox(width: 56, child: _HeaderCell('')),
                ],
              ),
            ),

            // Table rows
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: rows.length,
                itemBuilder: (context, i) => _WideRow(
                  row: rows[i],
                  gymId: gymId,
                  isEven: i.isEven,
                  isLast: i == rows.length - 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.tr(text).toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _WideRow extends StatelessWidget {
  const _WideRow({
    required this.row,
    required this.gymId,
    required this.isEven,
    required this.isLast,
  });
  final _Row row;
  final String gymId;
  final bool isEven;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = row.subscription;
    final member = row.member;
    final plan = row.plan;
    final displayName =
        member.displayName.isEmpty ? member.email : member.displayName;
    final endDate = sub.endDate;
    final daysLeft = endDate?.difference(DateTime.now()).inDays;
    final isExpired = daysLeft != null && daysLeft < 0;
    final pct = sub.paymentPercentage;

    final radius = BorderRadius.vertical(
      bottom: isLast ? const Radius.circular(14) : Radius.zero,
    );

    return InkWell(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MemberDetailScreen(member: member),
        ),
      ),
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isEven
              ? cs.surfaceContainerLowest
              : cs.surfaceContainerLowest.withValues(alpha: 0.6),
          borderRadius: radius,
          border: Border(
            left: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar
            UserAvatar(
              photoUrl: member.photoUrl,
              initials: displayName[0].toUpperCase(),
              color: _roleColor(member.role),
              radius: 18,
            ),
            const SizedBox(width: 10),

            // Member name + email
            SizedBox(
              width: 190,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    member.email,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Plan name
            SizedBox(
              width: 170,
              child: Text(
                plan?.name ?? sub.planId,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            const SizedBox(width: 12),

            // Status badge
            SizedBox(
              width: 90,
              child: _SubStatusBadge(status: sub.status),
            ),
            const SizedBox(width: 12),

            // Payment progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${sub.amountPaid} ${sub.currency}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade700),
                      ),
                      Text(
                        ' / ${sub.totalAmount} ${sub.currency}',
                        style:
                            TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      if (sub.remainingAmount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Text(
                            '-${sub.remainingAmount}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        pct >= 1.0
                            ? Colors.green.shade500
                            : Colors.orange.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Expiry
            SizedBox(
              width: 110,
              child: endDate == null
                  ? Text('—', style: TextStyle(color: cs.onSurfaceVariant))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('d MMM yyyy').format(endDate),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                isExpired ? Colors.red.shade600 : cs.onSurface,
                          ),
                        ),
                        if (daysLeft != null) _DaysLeftChip(daysLeft: daysLeft),
                      ],
                    ),
            ),
            const SizedBox(width: 12),

            // Record payment action
            SizedBox(
              width: 56,
              child: Tooltip(
                message: context.l10n.tr('Record payment'),
                child: IconButton(
                  icon: Icon(
                    Icons.payments_outlined,
                    size: 18,
                    color: Colors.green.shade600,
                  ),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => RecordPaymentScreen(
                        gymId: gymId,
                        userId: member.id,
                        userName: displayName,
                        initialSubscriptionId: sub.id,
                      ),
                    ),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(32, 32),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Narrow card list ──────────────────────────────────────────────────────────

class _NarrowList extends StatelessWidget {
  const _NarrowList({required this.rows, required this.gymId});
  final List<_Row> rows;
  final String gymId;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: rows.length,
      itemBuilder: (context, i) => _NarrowCard(row: rows[i], gymId: gymId),
    );
  }
}

class _NarrowCard extends StatelessWidget {
  const _NarrowCard({required this.row, required this.gymId});
  final _Row row;
  final String gymId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = row.subscription;
    final member = row.member;
    final plan = row.plan;
    final displayName =
        member.displayName.isEmpty ? member.email : member.displayName;
    final endDate = sub.endDate;
    final daysLeft = endDate?.difference(DateTime.now()).inDays;
    final pct = sub.paymentPercentage;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      color: cs.surfaceContainerLowest,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => MemberDetailScreen(member: member),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Member row
              Row(
                children: [
                  UserAvatar(
                    photoUrl: member.photoUrl,
                    initials: displayName[0].toUpperCase(),
                    color: _roleColor(member.role),
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                        Text(member.email,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  _SubStatusBadge(status: sub.status),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Plan + expiry
              Row(
                children: [
                  Icon(Icons.local_offer_outlined, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      plan?.name ?? sub.planId,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (endDate != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('d MMM yyyy').format(endDate),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: daysLeft != null && daysLeft < 0
                                ? Colors.red.shade600
                                : cs.onSurface,
                          ),
                        ),
                        if (daysLeft != null) _DaysLeftChip(daysLeft: daysLeft),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Payment progress
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${context.l10n.tr('Paid')}: ${sub.amountPaid} ${sub.currency}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green.shade700),
                            ),
                            if (sub.remainingAmount > 0) ...[
                              const SizedBox(width: 6),
                              Text(
                                '${context.l10n.tr('Due')}: ${sub.remainingAmount} ${sub.currency}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.orange.shade700),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct.clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor:
                                cs.outlineVariant.withValues(alpha: 0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              pct >= 1.0
                                  ? Colors.green.shade500
                                  : Colors.orange.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Record payment
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => RecordPaymentScreen(
                          gymId: gymId,
                          userId: member.id,
                          userName: displayName,
                          initialSubscriptionId: sub.id,
                        ),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    child: Text(context.l10n.tr('Pay')),
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

// ── Days-left chip ────────────────────────────────────────────────────────────

class _DaysLeftChip extends StatelessWidget {
  const _DaysLeftChip({required this.daysLeft});
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    if (daysLeft < 0) {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
      label = context.l10n.tr('Expired');
    } else if (daysLeft == 0) {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
      label = context.l10n.tr('Today');
    } else if (daysLeft <= 7) {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
      label = '$daysLeft${context.l10n.tr('d left')}';
    } else if (daysLeft <= 14) {
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade700;
      label = '$daysLeft${context.l10n.tr('d left')}';
    } else {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
      label = '$daysLeft${context.l10n.tr('d left')}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        context.l10n.tr(label),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

// ── Subscription status badge ─────────────────────────────────────────────────

class _SubStatusBadge extends StatelessWidget {
  const _SubStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    switch (status) {
      case 'active':
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        icon = Icons.check_circle_outline;
      case 'cancelled':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        icon = Icons.cancel_outlined;
      default:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade700;
        icon = Icons.hourglass_top_outlined;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            status == 'pending'
                ? context.l10n.tr('Pending')
                : context.l10n
                    .tr(status[0].toUpperCase() + status.substring(1))
                    .toUpperCase(),
            style:
                TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.search});
  final String filter;
  final String search;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasSearch = search.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch ? Icons.search_off_outlined : Icons.receipt_long_outlined,
            size: 56,
            color: cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch
                ? '${context.l10n.tr('No results for')} "$search"'
                : filter == 'active'
                    ? context.l10n.tr('No active subscriptions')
                    : filter == 'expiring'
                        ? context.l10n.tr('No subscriptions expiring soon')
                        : filter == 'unpaid'
                            ? context.l10n.tr('No unpaid balances — great!')
                            : context.l10n.tr('No assigned offers yet'),
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant),
          ),
          if (hasSearch) ...[
            const SizedBox(height: 6),
            Text(
              context.l10n.tr('Try a different name, email or plan.'),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
