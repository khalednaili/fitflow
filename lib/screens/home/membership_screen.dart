import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/membership_plan.dart';
import '../../services/subscription_service.dart';
import '../../utils/currency.dart';

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key, this.gymId = ''});

  final String gymId;

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);
  bool _isWorking = false;

  Future<void> _subscribe(MembershipPlan plan) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() {
      _isWorking = true;
    });

    try {
      // Create user subscription for payment tracking
      await _subscriptionService.createUserSubscription(
        userId: user.uid,
        planId: plan.id,
        totalAmount: plan.price,
        currency: plan.currency,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr('Payment Information'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10n.tr('Error')}: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Future<void> _cancel() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() {
      _isWorking = true;
    });

    try {
      await _subscriptionService.cancelStripeSubscription(userId: user.uid);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('Cancellation requested.'))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${context.l10n.tr('Cancellation failed')}: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(child: Text(l10n.tr('Please sign in first.'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('Membership Plans'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 760),
          child: Column(
            children: <Widget>[
              StreamBuilder<Map<String, dynamic>?>(
                stream:
                    _subscriptionService.streamCurrentSubscription(user.uid),
                builder: (context, snapshot) {
                  final subscription = snapshot.data;
                  final status = (subscription?['status'] ?? 'none') as String;
                  final planName = (subscription?['planName'] ??
                      l10n.tr('No active plan')) as String;
                  final cs = Theme.of(context).colorScheme;
                  final statusColor = status == 'active'
                      ? Colors.green.shade600
                      : status == 'none'
                          ? cs.onSurfaceVariant
                          : Colors.orange.shade600;

                  return Container(
                    margin: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: cs.outline.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.workspace_premium,
                            color: cs.primary, size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(planName,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              Text('${l10n.tr('Status')}: ${l10n.tr(status)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: statusColor,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _isWorking ? null : _cancel,
                          child: Text(l10n.tr('Cancel')),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<MembershipPlan>>(
                  stream: _subscriptionService.streamPlans(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }

                    final plans = snapshot.data ?? <MembershipPlan>[];
                    if (plans.isEmpty) {
                      return Center(
                        child:
                            Text(l10n.tr('No membership plans available yet.')),
                      );
                    }

                    return Builder(builder: (context) {
                      final isWide = MediaQuery.sizeOf(context).width >= 700;
                      return SingleChildScrollView(
                        padding:
                            EdgeInsets.fromLTRB(16, 12, 16, isWide ? 24 : 32),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: plans
                              .map((plan) => _PlanCard(
                                    plan: plan,
                                    isWide: isWide,
                                    isWorking: _isWorking,
                                    onSubscribe: () => _subscribe(plan),
                                    l10n: l10n,
                                  ))
                              .toList(),
                        ),
                      );
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatefulWidget {
  const _PlanCard({
    required this.plan,
    required this.isWide,
    required this.isWorking,
    required this.onSubscribe,
    required this.l10n,
  });

  final MembershipPlan plan;
  final bool isWide;
  final bool isWorking;
  final VoidCallback onSubscribe;
  final AppLocalizations l10n;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plan = widget.plan;
    final billingSuffix =
        plan.billingCycle == 'recurrent' ? '/${widget.l10n.tr('mo')}' : '';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = widget.isWide
        ? ((screenWidth.clamp(0, 760) - 16 * 2 - 12) / 2).clamp(200.0, 380.0)
        : double.infinity;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        width: cardWidth,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.primary.withValues(alpha: _hovered ? 0.5 : 0.2),
            width: _hovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? 0.08 : 0.03),
              blurRadius: _hovered ? 16 : 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.card_membership_outlined,
                        size: 20, color: cs.primary),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      plan.name,
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${plan.priceMonthly}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: cs.primary,
                    ),
                  ),
                  SizedBox(width: 4),
                  Text(
                    '${Currency.normalize(plan.currency)}$billingSuffix',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              if (plan.checkinSummary.isNotEmpty) ...[
                _PlanFeatureRow(
                    icon: Icons.confirmation_number_outlined,
                    label: plan.checkinSummary),
                SizedBox(height: 6),
              ],
              _PlanFeatureRow(
                  icon: Icons.schedule_outlined, label: plan.durationLabel),
              if (plan.description.trim().isNotEmpty) ...[
                SizedBox(height: 6),
                _PlanFeatureRow(
                    icon: Icons.info_outline, label: plan.description.trim()),
              ],
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.isWorking ? null : widget.onSubscribe,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: widget.isWorking
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          widget.l10n.tr('Select Plan'),
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanFeatureRow extends StatelessWidget {
  const _PlanFeatureRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 15, color: cs.primary.withValues(alpha: 0.7)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
