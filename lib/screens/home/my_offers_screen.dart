import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/membership_plan.dart';
import '../../models/user_subscription.dart';
import '../../services/subscription_service.dart';
import '../../utils/currency.dart';
import 'offer_details_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _statusColor(String status) {
  switch (status) {
    case 'active':
      return Color(0xFF0F766E);
    case 'paused':
      return Colors.orange.shade600;
    case 'cancelled':
      return Colors.red.shade600;
    default:
      return Colors.blueGrey.shade400;
  }
}

String _statusLabel(String status, AppLocalizations l10n) {
  switch (status) {
    case 'active':
      return l10n.tr('Active');
    case 'paused':
      return l10n.tr('Paused');
    case 'cancelled':
      return l10n.tr('Cancelled');
    default:
      return status[0].toUpperCase() + status.substring(1);
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

class MyOffersScreen extends StatefulWidget {
  const MyOffersScreen({super.key, this.gymId = ''});

  final String gymId;

  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen> {
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);

  late final Stream<List<UserSubscription>> _subscriptionsStream;
  late final Stream<List<MembershipPlan>> _plansStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _subscriptionsStream = user != null
        ? _subscriptionService.streamUserSubscriptions(user.uid)
        : Stream.empty();
    _plansStream = _subscriptionService.streamPlans();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.tr('My Offers'))),
        body: Center(child: Text(l10n.tr('Please sign in.'))),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.tr('My Offers')),
        centerTitle: false,
        titleTextStyle: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      body: StreamBuilder<List<UserSubscription>>(
        stream: _subscriptionsStream,
        builder: (context, subSnap) {
          if (subSnap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          final subscriptions = subSnap.data ?? <UserSubscription>[];

          if (subscriptions.isEmpty) {
            return _EmptyState(l10n: l10n);
          }

          return StreamBuilder<List<MembershipPlan>>(
            stream: _plansStream,
            builder: (context, planSnap) {
              final planMap = <String, MembershipPlan>{
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
                  // ── Summary header ──────────────────────────────────
                  SliverToBoxAdapter(
                    child: Builder(builder: (ctx) {
                      final isWide = MediaQuery.sizeOf(ctx).width >= 700;
                      return Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: isWide ? 760 : double.infinity),
                          child: _SummaryHeader(
                            activeCount: activeCount,
                            totalOwed: totalOwed,
                            currency: subscriptions.isNotEmpty
                                ? subscriptions.first.currency
                                : '',
                          ),
                        ),
                      );
                    }),
                  ),
                  // ── Offer cards ─────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Builder(builder: (context) {
                      final isWide = MediaQuery.sizeOf(context).width >= 700;
                      return Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: isWide ? 760 : double.infinity),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                                16, 8, 16, isWide ? 24 : 100),
                            child: Column(
                              children: subscriptions.asMap().entries.map((e) {
                                final sub = e.value;
                                final plan = planMap[sub.planId];
                                return _OfferCard(
                                  subscription: sub,
                                  plan: plan,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => OfferDetailsScreen(
                                          subscription: sub,
                                          plan: plan,
                                          gymId: widget.gymId),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      );
                    }),
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

// ── Summary header ────────────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.activeCount,
    required this.totalOwed,
    required this.currency,
  });

  final int activeCount;
  final int totalOwed;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr('My Memberships'),
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 4),
                Text(
                  '$activeCount ${context.l10n.tr(activeCount == 1 ? 'active plan' : 'active plans')}',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5),
                ),
              ],
            ),
          ),
          if (totalOwed > 0)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    context.l10n.tr('Balance due'),
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 2),
                  Text(
                    Currency.format(totalOwed, currency),
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Offer card ────────────────────────────────────────────────────────────────

class _OfferCard extends StatefulWidget {
  const _OfferCard({
    required this.subscription,
    required this.plan,
    required this.onTap,
  });

  final UserSubscription subscription;
  final MembershipPlan? plan;
  final VoidCallback onTap;

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  bool _hovered = false;

  int get _daysLeft {
    if (widget.subscription.endDate == null) return -1;
    return widget.subscription.endDate!.difference(DateTime.now()).inDays;
  }

  String _dateRange(String localeCode) {
    final fmt = DateFormat('d MMM yyyy', localeCode);
    final start = widget.subscription.startDate != null
        ? fmt.format(widget.subscription.startDate!)
        : '—';
    final end = widget.subscription.endDate != null
        ? fmt.format(widget.subscription.endDate!)
        : '—';
    return '$start → $end';
  }

  @override
  Widget build(BuildContext context) {
    final subscription = widget.subscription;
    final plan = widget.plan;
    final cs = Theme.of(context).colorScheme;
    final localeCode = Localizations.localeOf(context).languageCode;
    final planName = plan?.name ?? subscription.planId;
    final statusColor = _statusColor(subscription.status);
    final typeIcon = _offerTypeIcon(plan?.offerType);
    final daysLeft = _daysLeft;
    final isActive = subscription.status == 'active';
    final isExpired = daysLeft >= 0 && daysLeft <= 0 && isActive;
    final isSoon = daysLeft > 0 && daysLeft <= 7 && isActive;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        margin: EdgeInsets.only(bottom: 14),
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? statusColor.withValues(alpha: _hovered ? 0.55 : 0.35)
                : cs.outline.withValues(alpha: _hovered ? 0.35 : 0.2),
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? 0.09 : 0.04),
              blurRadius: _hovered ? 16 : 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header row ──────────────────────────────────────
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(typeIcon, size: 22, color: statusColor),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              planName,
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (plan?.checkinSummary.isNotEmpty == true)
                              Text(
                                plan!.checkinSummary,
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      // Status badge
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          _statusLabel(subscription.status, context.l10n),
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 16),

                  // ── Date range + days left ──────────────────────────
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 14, color: cs.onSurfaceVariant),
                      SizedBox(width: 5),
                      Text(
                        _dateRange(localeCode),
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      Spacer(),
                      if (daysLeft >= 0) ...[
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isExpired
                                ? Colors.red.shade50
                                : isSoon
                                    ? Colors.orange.shade50
                                    : cs.primaryContainer
                                        .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isExpired
                                ? context.l10n.tr('Expired')
                                : isSoon
                                    ? '$daysLeft ${context.l10n.tr('days left')}'
                                    : '$daysLeft ${context.l10n.tr('days left')}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isExpired
                                    ? Colors.red.shade700
                                    : isSoon
                                        ? Colors.orange.shade700
                                        : cs.primary),
                          ),
                        ),
                      ],
                    ],
                  ),

                  SizedBox(height: 14),

                  // ── Payment progress ────────────────────────────────
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
                                  '${Currency.format(subscription.amountPaid, subscription.currency)} ${context.l10n.tr('paid')}',
                                  style: TextStyle(
                                      fontSize: 12, color: cs.onSurfaceVariant),
                                ),
                                Text(
                                  Currency.format(subscription.totalAmount, subscription.currency),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: subscription.paymentPercentage,
                                minHeight: 6,
                                backgroundColor: cs.surfaceContainerHigh,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  subscription.remainingAmount == 0
                                      ? Colors.green.shade500
                                      : cs.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 14),
                      // Circular progress
                      _PaymentRing(
                        percentage: subscription.paymentPercentage,
                        statusColor: subscription.remainingAmount == 0
                            ? Colors.green.shade500
                            : statusColor,
                      ),
                    ],
                  ),

                  if (subscription.remainingAmount > 0) ...[
                    SizedBox(height: 10),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pending_outlined,
                              size: 14, color: Colors.orange.shade700),
                          SizedBox(width: 6),
                          Text(
                            '${Currency.format(subscription.remainingAmount, subscription.currency)} ${context.l10n.tr('remaining')}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Circular payment ring ─────────────────────────────────────────────────────

class _PaymentRing extends StatelessWidget {
  const _PaymentRing({required this.percentage, required this.statusColor});

  final double percentage;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(48, 48),
            painter: _RingPainter(
              percentage: percentage,
              trackColor: cs.surfaceContainerHigh,
              fillColor: statusColor,
            ),
          ),
          Text(
            '${(percentage * 100).round()}%',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: statusColor),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.percentage,
    required this.trackColor,
    required this.fillColor,
  });

  final double percentage;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 5.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * percentage.clamp(0.0, 1.0),
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percentage != percentage ||
      old.fillColor != fillColor ||
      old.trackColor != trackColor;
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.card_membership_outlined,
                  size: 52, color: cs.primary),
            ),
            SizedBox(height: 20),
            Text(
              l10n.tr('No assigned offers yet'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              l10n.tr(
                  'Your membership offers will appear here once assigned by the gym.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
