import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../../models/app_user.dart';
import '../../models/membership_plan.dart';
import '../../models/user_subscription.dart';
import '../../services/subscription_service.dart';
import 'assign_offer_screen.dart';
import 'record_payment_screen.dart';
import 'widgets/set_user_password_dialog.dart';
import '../../l10n/app_localizations.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

Color _statusColor(String status) {
  switch (status) {
    case 'active':
      return const Color(0xFF0F766E);
    case 'paused':
      return Colors.orange.shade600;
    case 'cancelled':
      return Colors.red.shade600;
    default:
      return Colors.blueGrey.shade400;
  }
}

String _statusLabel(BuildContext context, String status) {
  switch (status) {
    case 'active':
      return context.l10n.tr('Active');
    case 'paused':
      return context.l10n.tr('Paused');
    case 'cancelled':
      return context.l10n.tr('Cancelled');
    default:
      return context.l10n.tr(status[0].toUpperCase() + status.substring(1));
  }
}

IconData _offerTypeIcon(String? offerType) {
  switch (offerType) {
    case 'weekly_recurring':
      return Icons.repeat_on_outlined;
    case 'monthly_recurring':
      return Icons.calendar_month_outlined;
    case 'limited_sessions':
    case 'pack':
      return Icons.confirmation_number_outlined;
    default:
      return Icons.card_membership_outlined;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MemberAssignedOffersScreen extends StatelessWidget {
  const MemberAssignedOffersScreen({super.key, required this.member});

  final AppUser member;

  @override
  Widget build(BuildContext context) {
    final subscriptionService = SubscriptionService(gymId: member.gymId);
    final memberName =
        member.displayName.isNotEmpty ? member.displayName : member.email;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.tr('Assigned Offers'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(memberName,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.tr('Set password'),
            onPressed: () =>
                showSetUserPasswordDialog(context: context, member: member),
            icon: const Icon(Icons.lock_reset_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final assigned = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => AssignOfferScreen(
                  initialMemberId: member.id, gymId: member.gymId),
            ),
          );
          if (assigned == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(context.l10n.tr('Offer assigned successfully.')),
                ]),
                backgroundColor: const Color(0xFF0F766E),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        },
        icon: const Icon(Icons.add),
        label: Text(context.l10n.tr('Assign Offer')),
      ),
      body: StreamBuilder<List<UserSubscription>>(
        stream: subscriptionService.streamUserSubscriptions(member.id),
        builder: (context, subSnap) {
          if (subSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (subSnap.hasError) {
            return Center(
                child: Text('${context.l10n.tr('Error')}: ${subSnap.error}',
                    style: TextStyle(color: cs.error)));
          }

          final subscriptions = subSnap.data ?? <UserSubscription>[];

          if (subscriptions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.card_membership_outlined,
                          size: 48, color: cs.primary),
                    ),
                    const SizedBox(height: 18),
                    Text(context.l10n.tr('No assigned offers yet'),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                        context.l10n
                            .tr('Tap the button below to assign an offer.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            );
          }

          return StreamBuilder<List<MembershipPlan>>(
            stream: subscriptionService.streamAllOffers(),
            builder: (context, planSnap) {
              final planById = <String, MembershipPlan>{
                for (final p in planSnap.data ?? <MembershipPlan>[]) p.id: p,
              };

              // Stats
              final activeCount = subscriptions
                  .where((s) => s.status == 'active' || s.status == 'paused')
                  .length;
              final totalOwed = subscriptions.fold<int>(
                  0, (sum, s) => sum + s.remainingAmount);

              return CustomScrollView(
                slivers: [
                  // Summary bar
                  SliverToBoxAdapter(
                    child: _SummaryBar(
                      activeCount: activeCount,
                      totalOwed: totalOwed,
                      currency: subscriptions.isNotEmpty
                          ? subscriptions.first.currency
                          : '',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final sub = subscriptions[index];
                          final plan = planById[sub.planId];
                          return _AssignedOfferCard(
                            subscription: sub,
                            plan: plan,
                            member: member,
                          );
                        },
                        childCount: subscriptions.length,
                      ),
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

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.activeCount,
    required this.totalOwed,
    required this.currency,
  });

  final int activeCount;
  final int totalOwed;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          _Pill(
            label: context.l10n.tr('Active'),
            value: '$activeCount',
            color: const Color(0xFF0F766E),
          ),
          const SizedBox(width: 10),
          if (totalOwed > 0)
            _Pill(
              label: context.l10n.tr('Balance due'),
              value: '$totalOwed $currency',
              color: Colors.orange.shade600,
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: color)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: color.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Assigned offer card ───────────────────────────────────────────────────────

class _AssignedOfferCard extends StatefulWidget {
  const _AssignedOfferCard({
    required this.subscription,
    required this.plan,
    required this.member,
  });

  final UserSubscription subscription;
  final MembershipPlan? plan;
  final AppUser member;

  @override
  State<_AssignedOfferCard> createState() => _AssignedOfferCardState();
}

class _AssignedOfferCardState extends State<_AssignedOfferCard> {
  bool _historyExpanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = widget.subscription;
    final plan = widget.plan;
    final localeCode = Localizations.localeOf(context).languageCode;
    final dateFormat = DateFormat('d MMM yyyy', localeCode);
    final statusColor = _statusColor(sub.status);
    final typeIcon = _offerTypeIcon(plan?.offerType);
    final planName = plan?.name ?? sub.planId;
    final daysLeft = sub.endDate != null
        ? sub.endDate!.difference(DateTime.now()).inDays
        : -1;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: sub.status == 'active'
              ? statusColor.withValues(alpha: 0.3)
              : cs.outline.withValues(alpha: 0.18),
          width: sub.status == 'active' ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Card header ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(typeIcon, size: 20, color: statusColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(planName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (plan?.checkinSummary.isNotEmpty == true)
                            Text(plan!.checkinSummary,
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(_statusLabel(context, sub.status),
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11)),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── Dates ─────────────────────────────────────────
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Text(
                      '${sub.startDate != null ? dateFormat.format(sub.startDate!) : '—'} → ${sub.endDate != null ? dateFormat.format(sub.endDate!) : '—'}',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const Spacer(),
                    if (daysLeft >= 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: daysLeft <= 7
                              ? Colors.orange.shade50
                              : cs.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          daysLeft == 0
                              ? context.l10n.tr('Expired today')
                              : '$daysLeft ${context.l10n.tr('days left')}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: daysLeft <= 7
                                  ? Colors.orange.shade700
                                  : cs.primary),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Payment progress ───────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${sub.amountPaid} ${sub.currency} ${context.l10n.tr('paid')}',
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                              Text('${sub.totalAmount} ${sub.currency}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: sub.paymentPercentage,
                              minHeight: 6,
                              backgroundColor: cs.surfaceContainerHigh,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                sub.remainingAmount == 0
                                    ? Colors.green.shade500
                                    : cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (sub.remainingAmount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          '${sub.remainingAmount}\n${sub.currency} ${context.l10n.tr('due')}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade700),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 13, color: Colors.green.shade600),
                            const SizedBox(width: 4),
                            Text(context.l10n.tr('Paid'),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green.shade700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Divider + actions ─────────────────────────────────────
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                // Record payment button
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => RecordPaymentScreen(
                        gymId: widget.member.gymId,
                        userId: widget.member.id,
                        userName: widget.member.displayName.isEmpty
                            ? widget.member.email
                            : widget.member.displayName,
                        initialSubscriptionId: sub.id,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add_card_outlined, size: 16),
                  label: Text(context.l10n.tr('Record Payment'),
                      style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                // History toggle
                if (sub.paymentHistory.isNotEmpty)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _historyExpanded = !_historyExpanded),
                    icon: Icon(
                      _historyExpanded
                          ? Icons.expand_less
                          : Icons.history_outlined,
                      size: 16,
                    ),
                    label: Text(
                      _historyExpanded
                          ? context.l10n.tr('Hide')
                          : '${context.l10n.tr('History')} (${sub.paymentHistory.length})',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                // Actions menu
                _OfferActionsMenu(
                  subscription: sub,
                  plan: plan,
                  member: widget.member,
                ),
              ],
            ),
          ),

          // ── Expandable payment history ────────────────────────────
          if (_historyExpanded && sub.paymentHistory.isNotEmpty) ...[
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sub.paymentHistory.asMap().entries.map((entry) {
                  final p = entry.value;
                  final isLast = entry.key == sub.paymentHistory.length - 1;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Icon(Icons.check_rounded,
                                size: 14, color: Colors.green.shade600),
                          ),
                          if (!isLast)
                            Container(
                                width: 1.5,
                                height: 32,
                                color: cs.outlineVariant),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${p.amount} ${sub.currency}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14),
                                    ),
                                    Text(
                                      DateFormat('d MMM yyyy', localeCode)
                                          .format(p.date),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant),
                                    ),
                                    if (p.notes.isNotEmpty)
                                      Text(p.notes,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: cs.onSurfaceVariant,
                                              fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(p.method,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: cs.onSurfaceVariant,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Offer actions popup menu ───────────────────────────────────────────────────

class _OfferActionsMenu extends StatefulWidget {
  const _OfferActionsMenu({
    required this.subscription,
    required this.plan,
    required this.member,
  });

  final UserSubscription subscription;
  final MembershipPlan? plan;
  final AppUser member;

  @override
  State<_OfferActionsMenu> createState() => _OfferActionsMenuState();
}

class _OfferActionsMenuState extends State<_OfferActionsMenu> {
  late final _svc = SubscriptionService(gymId: widget.member.gymId);
  bool _loading = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(context.l10n.tr('Done')),
            ]),
            backgroundColor: const Color(0xFF0F766E),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'memberOfferAction');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate() => _run(() => _svc.updateSubscriptionStatus(
      subscriptionId: widget.subscription.id, status: 'active'));

  Future<void> _pause() => _run(() => _svc.updateSubscriptionStatus(
      subscriptionId: widget.subscription.id, status: 'paused'));

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Cancel Offer')),
        content: Text(context.l10n.tr(
            'Are you sure you want to cancel this offer? The member will lose access.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.tr('Keep'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Cancel Offer')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => _svc.updateSubscriptionStatus(
        subscriptionId: widget.subscription.id, status: 'cancelled'));
  }

  Future<void> _extend() async {
    final now = DateTime.now();
    final initial = widget.subscription.endDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? initial : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: context.l10n.tr('Set new end date'),
    );
    if (picked == null) return;
    await _run(() => _svc.extendOffer(
        subscriptionId: widget.subscription.id, newEndDate: picked));
  }

  Future<void> _changeStartDate() async {
    final now = DateTime.now();
    final initial = widget.subscription.startDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365 * 3)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: context.l10n.tr('Set new start date'),
    );
    if (picked == null) return;
    await _run(() => _svc.changeStartDate(
        subscriptionId: widget.subscription.id, newStartDate: picked));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Delete Offer')),
        content: Text(context.l10n.tr(
            'This will permanently remove the offer and all its payment history. This cannot be undone.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => _svc.unassignOffer(
        subscriptionId: widget.subscription.id, userId: widget.member.id));
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subscription;
    final isActive = sub.status == 'active';
    final isCancelled = sub.status == 'cancelled';

    if (_loading) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(6),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: context.l10n.tr('Actions'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        // ── Status actions ───────────────────────────────────────────────────
        if (!isActive)
          PopupMenuItem(
            value: 'activate',
            child: ListTile(
              dense: true,
              leading:
                  Icon(Icons.play_circle_outline, color: Color(0xFF0F766E)),
              title: Text(context.l10n.tr('Activate')),
            ),
          ),
        if (isActive)
          PopupMenuItem(
            value: 'pause',
            child: ListTile(
              dense: true,
              leading:
                  Icon(Icons.pause_circle_outline, color: Color(0xFFF97316)),
              title: Text(context.l10n.tr('Pause')),
            ),
          ),
        if (!isCancelled)
          PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.block_outlined, color: Color(0xFFDC2626)),
              title: Text(context.l10n.tr('Cancel'),
                  style: TextStyle(color: Color(0xFFDC2626))),
            ),
          ),
        const PopupMenuDivider(),
        // ── Date actions ─────────────────────────────────────────────────────
        PopupMenuItem(
          value: 'extend',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.date_range_outlined),
            title: Text(context.l10n.tr('Extend / Change End Date')),
          ),
        ),
        PopupMenuItem(
          value: 'start_date',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.event_available_outlined),
            title: Text(context.l10n.tr('Change Start Date')),
          ),
        ),
        const PopupMenuDivider(),
        // ── Destructive ──────────────────────────────────────────────────────
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading:
                Icon(Icons.delete_forever_outlined, color: Color(0xFFDC2626)),
            title: Text(context.l10n.tr('Delete Offer'),
                style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'activate':
            _activate();
          case 'pause':
            _pause();
          case 'cancel':
            _cancel();
          case 'extend':
            _extend();
          case 'start_date':
            _changeStartDate();
          case 'delete':
            _delete();
        }
      },
    );
  }
}
