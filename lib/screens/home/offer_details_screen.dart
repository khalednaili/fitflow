import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/membership_plan.dart';
import '../../models/user_subscription.dart';
import '../../services/booking_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/currency.dart';

// ── helpers (same as my_offers_screen) ───────────────────────────────────────

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

class OfferDetailsScreen extends StatelessWidget {
  const OfferDetailsScreen({
    super.key,
    required this.subscription,
    this.plan,
    this.gymId = '',
  });

  final UserSubscription subscription;
  final MembershipPlan? plan;
  final String gymId;

  Color get _accent => _statusColor(subscription.status);

  @override
  Widget build(BuildContext context) {
    final planName = plan?.name ?? subscription.planId;
    final localeCode = Localizations.localeOf(context).languageCode;
    final cs = Theme.of(context).colorScheme;
    final daysLeft = subscription.endDate != null
        ? subscription.endDate!.difference(DateTime.now()).inDays
        : -1;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── Hero app bar ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: _accent,
            iconTheme: IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _HeroHeader(
                planName: planName,
                subscription: subscription,
                plan: plan,
                accent: _accent,
                daysLeft: daysLeft,
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Plan details chips ──────────────────────────
                  if (plan != null) ...[
                    _SectionLabel(label: context.l10n.tr('Plan Details')),
                    SizedBox(height: 10),
                    _PlanDetailsCard(plan: plan!, localeCode: localeCode),
                    SizedBox(height: 20),
                  ],

                  // ── Subscription dates ──────────────────────────
                  _SectionLabel(label: context.l10n.tr('Subscription Period')),
                  SizedBox(height: 10),
                  _DatesCard(
                      subscription: subscription,
                      localeCode: localeCode,
                      daysLeft: daysLeft),
                  SizedBox(height: 20),

                  // ── Payment summary ─────────────────────────────
                  _SectionLabel(label: context.l10n.tr('Payment')),
                  SizedBox(height: 10),
                  _PaymentCard(subscription: subscription, accent: _accent),
                  SizedBox(height: 20),

                  // ── Payment history ─────────────────────────────
                  _SectionLabel(
                    label:
                        '${context.l10n.tr('Payment History')} (${subscription.paymentHistory.length})',
                  ),
                  SizedBox(height: 10),
                  if (subscription.paymentHistory.isEmpty)
                    _EmptyPaymentHistory(cs: cs)
                  else
                    _PaymentTimeline(
                        subscription: subscription, localeCode: localeCode),

                  // ── Late cancellations ──────────────────────────
                  SizedBox(height: 20),
                  _LateCancellationsSection(
                    userId: subscription.userId,
                    gymId: gymId,
                    subscriptionStart: subscription.startDate,
                    subscriptionEnd: subscription.endDate,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero header ───────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.planName,
    required this.subscription,
    required this.plan,
    required this.accent,
    required this.daysLeft,
  });

  final String planName;
  final UserSubscription subscription;
  final MembershipPlan? plan;
  final Color accent;
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final statusLabel = _statusLabel(subscription.status, context.l10n);
    final typeIcon = _offerTypeIcon(plan?.offerType);
    final typeLabel = plan?.offerTypeLabel ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.78)],
        ),
      ),
      child: Stack(
        children: [
          // Decorative
          Positioned(
            right: -50,
            top: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 56, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Type + status badges
                  Row(
                    children: [
                      _Badge(
                        icon: typeIcon,
                        label: typeLabel.isNotEmpty ? typeLabel : context.l10n.tr('Offer'),
                        bg: Colors.white.withValues(alpha: 0.2),
                      ),
                      SizedBox(width: 8),
                      _Badge(
                        icon: Icons.check_circle_outline,
                        label: statusLabel,
                        bg: _statusColor(subscription.status)
                            .withValues(alpha: 0.85),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    planName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (plan?.checkinSummary.isNotEmpty == true) ...[
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.fitness_center_outlined,
                            size: 14, color: Colors.white70),
                        SizedBox(width: 5),
                        Text(
                          plan!.checkinSummary,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                  if (daysLeft >= 0) ...[
                    SizedBox(height: 10),
                    _Badge(
                      icon: daysLeft <= 7
                          ? Icons.warning_amber_outlined
                          : Icons.schedule_outlined,
                      label: daysLeft == 0
                          ? context.l10n.tr('Expired today')
                          : daysLeft < 0
                              ? context.l10n.tr('Expired')
                              : '$daysLeft ${context.l10n.tr('days remaining')}',
                      bg: daysLeft <= 7
                          ? Colors.orange.shade600
                          : Colors.white.withValues(alpha: 0.2),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.bg});

  final IconData icon;
  final String label;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Plan details ──────────────────────────────────────────────────────────────

class _PlanDetailsCard extends StatelessWidget {
  const _PlanDetailsCard({required this.plan, required this.localeCode});

  final MembershipPlan plan;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PlanChip(
                  icon: Icons.category_outlined, label: plan.offerTypeLabel),
              _PlanChip(
                  icon: Icons.sync_alt_outlined, label: plan.billingCycleLabel),
              _PlanChip(
                  icon: Icons.timelapse_outlined, label: plan.durationLabel),
              _PlanChip(
                  icon: Icons.fitness_center_outlined,
                  label: plan.checkinSummary),
            ],
          ),
          if (plan.description.trim().isNotEmpty) ...[
            SizedBox(height: 12),
            Text(
              plan.description,
              style: TextStyle(
                  fontSize: 14, color: cs.onSurfaceVariant, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Dates card ────────────────────────────────────────────────────────────────

class _DatesCard extends StatelessWidget {
  const _DatesCard({
    required this.subscription,
    required this.localeCode,
    required this.daysLeft,
  });

  final UserSubscription subscription;
  final String localeCode;
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM yyyy', localeCode);

    return Container(
      padding: EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Row(
        children: [
          Expanded(
            child: _DateBlock(
              icon: Icons.play_circle_outline,
              label: context.l10n.tr('Start date'),
              value: subscription.startDate != null
                  ? fmt.format(subscription.startDate!)
                  : '—',
              color: cs.primary,
            ),
          ),
          Container(width: 1, height: 48, color: cs.outlineVariant),
          Expanded(
            child: _DateBlock(
              icon: Icons.stop_circle_outlined,
              label: context.l10n.tr('End date'),
              value: subscription.endDate != null
                  ? fmt.format(subscription.endDate!)
                  : '—',
              color: daysLeft >= 0 && daysLeft <= 7
                  ? Colors.orange.shade600
                  : cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          SizedBox(height: 6),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Payment card ──────────────────────────────────────────────────────────────

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.subscription, required this.accent});

  final UserSubscription subscription;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = subscription.paymentPercentage;
    final pctLabel = '${(pct * 100).toStringAsFixed(0)}%';

    return Container(
      padding: EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Row(
        children: [
          // Circular ring
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size(80, 80),
                  painter: _RingPainter(
                    percentage: pct,
                    trackColor: cs.surfaceContainerHigh,
                    fillColor: subscription.remainingAmount == 0
                        ? Colors.green.shade500
                        : accent,
                    strokeWidth: 7,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(pctLabel,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: subscription.remainingAmount == 0
                                ? Colors.green.shade600
                                : accent)),
                    Text(context.l10n.tr('paid'),
                        style: TextStyle(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PaymentRow(
                  label: context.l10n.tr('Total'),
                  amount: subscription.totalAmount,
                  currency: subscription.currency,
                  bold: true,
                ),
                SizedBox(height: 8),
                _PaymentRow(
                  label: context.l10n.tr('Paid'),
                  amount: subscription.amountPaid,
                  currency: subscription.currency,
                  color: Colors.green.shade600,
                ),
                SizedBox(height: 8),
                _PaymentRow(
                  label: context.l10n.tr('Remaining'),
                  amount: subscription.remainingAmount,
                  currency: subscription.currency,
                  color: subscription.remainingAmount > 0
                      ? Colors.orange.shade700
                      : Colors.green.shade600,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.color,
    this.bold = false,
  });

  final String label;
  final int amount;
  final String currency;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        Text(
          Currency.format(amount, currency),
          style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color),
        ),
      ],
    );
  }
}

// ── Payment timeline ──────────────────────────────────────────────────────────

class _PaymentTimeline extends StatelessWidget {
  const _PaymentTimeline({required this.subscription, required this.localeCode});

  final UserSubscription subscription;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM yyyy • HH:mm', localeCode);
    final payments = subscription.paymentHistory;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _cardDecoration(cs),
      child: Column(
        children: payments.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final isLast = i == payments.length - 1;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline indicator
              Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.green.shade300, width: 1.5),
                    ),
                    child: Icon(Icons.check_rounded,
                        size: 18, color: Colors.green.shade600),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 40,
                      color: cs.outlineVariant,
                    ),
                ],
              ),
              SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            Currency.format(p.amount, subscription.currency),
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              p.method,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 3),
                      Text(
                        fmt.format(p.date),
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      if (p.notes.isNotEmpty) ...[
                        SizedBox(height: 3),
                        Text(
                          p.notes,
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Empty payment history ─────────────────────────────────────────────────────

class _EmptyPaymentHistory extends StatelessWidget {
  const _EmptyPaymentHistory({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: _cardDecoration(cs),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, size: 22, color: cs.outlineVariant),
          SizedBox(width: 12),
          Text(context.l10n.tr('No payments recorded yet.'),
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

BoxDecoration _cardDecoration(ColorScheme cs) => BoxDecoration(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    );

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.percentage,
    required this.trackColor,
    required this.fillColor,
    this.strokeWidth = 5.0,
  });

  final double percentage;
  final Color trackColor;
  final Color fillColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

// ── Late cancellations section ────────────────────────────────────────────────

class _LateCancellationsSection extends StatefulWidget {
  const _LateCancellationsSection({
    required this.userId,
    this.gymId = '',
    this.subscriptionStart,
    this.subscriptionEnd,
  });

  final String userId;
  final String gymId;
  final DateTime? subscriptionStart;
  final DateTime? subscriptionEnd;

  @override
  State<_LateCancellationsSection> createState() =>
      _LateCancellationsSectionState();
}

class _LateCancellationsSectionState extends State<_LateCancellationsSection> {
  late final _bookingService = BookingService(gymId: widget.gymId);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _bookingService.streamLateCancellationsForUser(widget.userId),
      builder: (context, snap) {
        // Filter to records within this subscription's date range
        final all = snap.data ?? <Map<String, dynamic>>[];
        final records = all.where((r) {
          final classStart = (r['classStartTime'] as Timestamp?)?.toDate();
          if (classStart == null) return true;
          if (widget.subscriptionStart != null &&
              classStart.isBefore(widget.subscriptionStart!)) {
            return false;
          }
          if (widget.subscriptionEnd != null &&
              classStart.isAfter(widget.subscriptionEnd!)) {
            return false;
          }
          return true;
        }).toList();

        if (snap.connectionState == ConnectionState.waiting) {
          return SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SectionLabel(
                    label:
                        '${context.l10n.tr('Late Cancellations')} (${records.length})'),
                SizedBox(width: 6),
                if (records.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${records.length} ${context.l10n.tr(records.length == 1 ? 'session deducted' : 'sessions deducted')}',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 10),
            if (records.isEmpty)
              Container(
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                decoration: _cardDecoration(cs),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 20, color: Colors.green.shade500),
                    SizedBox(width: 10),
                    Text(context.l10n.tr('No late cancellations.'),
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              )
            else
              Container(
                decoration: _cardDecoration(cs),
                child: Column(
                  children: records.asMap().entries.map((e) {
                    final isLast = e.key == records.length - 1;
                    final r = e.value;
                    final cancelledAt =
                        (r['cancelledAt'] as Timestamp?)?.toDate();
                    final classTitle = (r['classTitle'] ?? context.l10n.tr('Class')) as String;
                    final mins = (r['minutesBeforeClass'] ?? 0) as int;
                    final fmt = DateFormat('EEE d MMM, HH:mm');

                    return Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.timer_off_outlined,
                                    size: 16, color: Colors.orange),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(classTitle,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    SizedBox(height: 3),
                                    Text(
                                      cancelledAt != null
                                          ? '${context.l10n.tr('Cancelled')} ${fmt.format(cancelledAt)}'
                                          : context.l10n.tr('Cancelled'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$mins${context.l10n.tr('min')} ${context.l10n.tr('before')}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Divider(
                              height: 1,
                              color: cs.outlineVariant.withValues(alpha: 0.4)),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}
