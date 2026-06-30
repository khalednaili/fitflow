import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/membership_plan.dart';
import '../../models/user_subscription.dart';
import '../../services/subscription_service.dart';
import '../../utils/currency.dart';

class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.initialSubscriptionId,
    this.gymId = '',
  });

  final String userId;
  final String userName;
  final String? initialSubscriptionId;
  final String gymId;

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);
  bool _isProcessing = false;
  String _selectedMethod = 'cash';
  String? _selectedSubscriptionId;

  @override
  void initState() {
    super.initState();
    _selectedSubscriptionId = widget.initialSubscriptionId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _enteredAmount => int.tryParse(_amountController.text.trim()) ?? 0;

  Future<void> _recordPayment() async {
    final l10n = context.l10n;
    final subscriptionId = _selectedSubscriptionId;
    final amount = _enteredAmount;

    if (subscriptionId == null || subscriptionId.isEmpty) {
      _showError(l10n.tr('Please select member and offer.'));
      return;
    }
    if (amount <= 0) {
      _showError(l10n.tr('Please enter a valid amount'));
      return;
    }

    final subscriptions =
        await _subscriptionService.streamUserSubscriptions(widget.userId).first;
    UserSubscription? subscription;
    for (final item in subscriptions) {
      if (item.id == subscriptionId) {
        subscription = item;
        break;
      }
    }

    if (!mounted) return;

    if (subscription == null) {
      _showError(l10n.tr('No payment tracking found for this member.'));
      return;
    }

    setState(() => _isProcessing = true);
    try {
      await _subscriptionService.recordPayment(
        subscriptionId: subscriptionId,
        amount: amount,
        method: _selectedMethod,
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      _showSuccess(l10n.tr('Payment recorded successfully'));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _showError('${l10n.tr('Error')}: $error');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(msg),
      ]),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLowest,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 4,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _initials(widget.userName),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.tr('Record Payment'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                Text(widget.userName,
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w400)),
              ],
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<UserSubscription>>(
        stream: _subscriptionService.streamUserSubscriptions(widget.userId),
        builder: (context, subSnap) {
          final subscriptions = subSnap.data ?? <UserSubscription>[];
          final loading =
              subSnap.connectionState == ConnectionState.waiting;

          if (_selectedSubscriptionId == null &&
              subscriptions.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() =>
                    _selectedSubscriptionId = subscriptions.first.id);
              }
            });
          }

          UserSubscription? subscription;
          for (final item in subscriptions) {
            if (item.id == _selectedSubscriptionId) {
              subscription = item;
              break;
            }
          }

          return StreamBuilder<List<MembershipPlan>>(
            stream: _subscriptionService.streamAllOffers(),
            builder: (context, plansSnap) {
              final plansById = <String, MembershipPlan>{
                for (final p in plansSnap.data ?? <MembershipPlan>[])
                  p.id: p,
              };

              if (loading) {
                return const Center(child: CircularProgressIndicator());
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;
                  final sub = subscription;

                  // ── Shared: offer selector ─────────────────────────
                  final offerWidget = subscriptions.isEmpty
                      ? _EmptyOffersCard(l10n: l10n)
                      : _OfferSelector(
                          subscriptions: subscriptions,
                          plansById: plansById,
                          selectedId: _selectedSubscriptionId,
                          onChanged: (v) => setState(
                              () => _selectedSubscriptionId = v),
                        );

                  // ── Shared: instalment card ────────────────────────
                  final instalmentWidget =
                      (sub != null && sub.hasPaymentPlan)
                          ? _InstalmentScheduleCard(
                              subscription: sub,
                              onMarkPaid: (id) async {
                                final sid = sub.id;
                                await SubscriptionService(
                                        gymId: widget.gymId)
                                    .markInstalmentPaid(
                                        subscriptionId: sid,
                                        instalmentId: id);
                              },
                            )
                          : null;

                  // ── Shared: payment form widgets (no history) ──────
                  final formWidgets = sub == null
                      ? null
                      : <Widget>[
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _amountController,
                            builder: (ctx, val, _) {
                              final entered =
                                  int.tryParse(val.text.trim()) ?? 0;
                              return _AmountInput(
                                controller: _amountController,
                                subscription: sub,
                                enteredAmount: entered,
                                onFillRemaining: () =>
                                    _amountController.text =
                                        '${sub.remainingAmount}',
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          _MethodSelector(
                            selected: _selectedMethod,
                            onChanged: (v) =>
                                setState(() => _selectedMethod = v),
                          ),
                          const SizedBox(height: 14),
                          _NotesField(controller: _notesController),
                          const SizedBox(height: 22),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _amountController,
                            builder: (ctx, val, _) {
                              final entered =
                                  int.tryParse(val.text.trim()) ?? 0;
                              return _SubmitButton(
                                isProcessing: _isProcessing,
                                canSubmit: entered > 0,
                                onPressed: _recordPayment,
                                amount: entered,
                                currency: sub.currency,
                              );
                            },
                          ),
                        ];

                  // ── Wide 2-column layout (≥760px) ──────────────────
                  if (isWide) {
                    return SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(24, 20, 24, 48),
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 1060),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              // ── Left: context ──────────────
                              SizedBox(
                                width: 360,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    offerWidget,
                                    if (sub != null) ...[
                                      const SizedBox(height: 16),
                                      _BalanceCard(subscription: sub),
                                      if (instalmentWidget != null) ...[
                                        const SizedBox(height: 16),
                                        instalmentWidget,
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              // ── Right: action ──────────────
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: formWidgets != null
                                      ? [
                                          ...formWidgets,
                                          if (sub!.paymentHistory
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 24),
                                            _PaymentHistory(
                                                subscription: sub),
                                          ],
                                        ]
                                      : [
                                          _NoSelectionHint(
                                              hasOffers: subscriptions
                                                  .isNotEmpty),
                                        ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  // ── Narrow single-column layout (<760px) ───────────
                  return SingleChildScrollView(
                    padding:
                        const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 620),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            offerWidget,
                            if (sub != null) ...[
                              const SizedBox(height: 16),
                              _BalanceCard(subscription: sub),
                              const SizedBox(height: 16),
                              ...?formWidgets,
                              if (instalmentWidget != null) ...[
                                const SizedBox(height: 24),
                                instalmentWidget,
                              ],
                              if (sub.paymentHistory.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                _PaymentHistory(subscription: sub),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyOffersCard extends StatelessWidget {
  const _EmptyOffersCard({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 40, color: cs.error.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            l10n.tr('No assigned offers found for this member.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: cs.error, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.tr('Assign an offer first before recording a payment.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── No selection hint (wide layout, right col) ────────────────────────────────

class _NoSelectionHint extends StatelessWidget {
  const _NoSelectionHint({required this.hasOffers});
  final bool hasOffers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.4),
            style: BorderStyle.solid),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back_outlined,
              size: 32, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            hasOffers
                ? context.l10n.tr('Select an offer on the left to record a payment')
                : context.l10n.tr('Assign an offer to this member first'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ── Offer selector ────────────────────────────────────────────────────────────

class _OfferSelector extends StatelessWidget {
  const _OfferSelector({
    required this.subscriptions,
    required this.plansById,
    required this.selectedId,
    required this.onChanged,
  });
  final List<UserSubscription> subscriptions;
  final Map<String, MembershipPlan> plansById;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _SectionCard(
      title: context.l10n.tr('Select Offer'),
      icon: Icons.local_offer_outlined,
      child: Column(
        children: subscriptions.map((sub) {
          final plan = plansById[sub.planId];
          final name = plan?.name ?? sub.planId;
          final isSelected = sub.id == selectedId;
          final isPaid = sub.remainingAmount <= 0;

          return InkWell(
            onTap: () => onChanged(sub.id),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? cs.primaryContainer.withValues(alpha: 0.5)
                    : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? cs.primary.withValues(alpha: 0.5)
                      : cs.outlineVariant.withValues(alpha: 0.4),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? cs.primary : cs.onSurface)),
                        const SizedBox(height: 2),
                        Text(
                          isPaid
                              ? context.l10n.tr('Fully paid')
                              : '${context.l10n.tr('Remaining')}: ${Currency.format(sub.remainingAmount, sub.currency)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isPaid
                                ? Colors.green.shade600
                                : Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(sub.status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      sub.status.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _statusColor(sub.status)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
        return Colors.green.shade600;
      case 'cancelled':
        return Colors.red.shade600;
      default:
        return Colors.orange.shade600;
    }
  }
}

// ── Balance card ──────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.subscription});
  final UserSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = subscription.paymentPercentage.clamp(0.0, 1.0);
    final isPaid = subscription.remainingAmount <= 0;
    final pctLabel = '${(pct * 100).toStringAsFixed(0)}%';
    final progressColor =
        isPaid ? Colors.green.shade500 : Colors.orange.shade600;

    return _SectionCard(
      title: context.l10n.tr('Current Balance'),
      icon: Icons.account_balance_wallet_outlined,
      trailing: Text(
        pctLabel,
        style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: progressColor,
            letterSpacing: -0.5),
      ),
      child: Column(
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 12,
              backgroundColor: cs.outlineVariant.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 14),
          // Three stats
          Row(
            children: [
              _BalanceStat(
                label: context.l10n.tr('Total'),
                value: Currency.format(subscription.totalAmount, subscription.currency),
                color: cs.onSurface,
                icon: Icons.receipt_outlined,
              ),
              const SizedBox(width: 8),
              _BalanceStat(
                label: context.l10n.tr('Paid'),
                value: Currency.format(subscription.amountPaid, subscription.currency),
                color: Colors.green.shade600,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 8),
              _BalanceStat(
                label: context.l10n.tr('Remaining'),
                value:
                    Currency.format(subscription.remainingAmount, subscription.currency),
                color: isPaid ? Colors.green.shade600 : Colors.orange.shade700,
                icon: isPaid ? Icons.verified_outlined : Icons.pending_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  const _BalanceStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Amount input ──────────────────────────────────────────────────────────────

class _AmountInput extends StatelessWidget {
  const _AmountInput({
    required this.controller,
    required this.subscription,
    required this.enteredAmount,
    required this.onFillRemaining,
  });
  final TextEditingController controller;
  final UserSubscription subscription;
  final int enteredAmount;
  final VoidCallback onFillRemaining;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining = subscription.remainingAmount;
    final afterPayment = remaining > 0
        ? (remaining - enteredAmount).clamp(0, remaining)
        : 0;
    final isOverpay = enteredAmount > remaining && remaining > 0;
    final isValid = enteredAmount > 0;

    return _SectionCard(
      title: context.l10n.tr('Payment Amount'),
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Big amount input
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              prefixText: '${Currency.normalize(subscription.currency)}  ',
              prefixStyle: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant),
              hintText: '0',
              hintStyle: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
              filled: true,
              fillColor: isValid
                  ? Colors.green.withValues(alpha: 0.05)
                  : cs.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: isValid
                        ? Colors.green.shade300
                        : cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: remaining > 0
                  ? Tooltip(
                      message: context.l10n.tr('Fill remaining balance'),
                      child: IconButton(
                        icon:
                            const Icon(Icons.auto_fix_high_outlined, size: 18),
                        onPressed: onFillRemaining,
                        color: cs.primary,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),

          // After-payment preview
          if (isValid)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isOverpay
                    ? Colors.orange.withValues(alpha: 0.08)
                    : Colors.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isOverpay
                      ? Colors.orange.shade200
                      : Colors.green.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isOverpay ? Icons.info_outline : Icons.check_circle_outline,
                    size: 16,
                    color: isOverpay
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOverpay
                          ? '${context.l10n.tr('Amount exceeds remaining balance of')} ${Currency.format(remaining, subscription.currency)}'
                          : afterPayment == 0
                              ? context.l10n
                                  .tr('Fully paid after this payment 🎉')
                              : '${context.l10n.tr('Remaining after payment')}: ${Currency.format(afterPayment, subscription.currency)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isOverpay
                            ? Colors.orange.shade800
                            : Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Quick-fill chips
          if (remaining > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (remaining > 0)
                  _QuickChip(
                    label:
                        '${context.l10n.tr('Pay all')}  ${Currency.format(remaining, subscription.currency)}',
                    onTap: onFillRemaining,
                  ),
                if (remaining > 1)
                  _QuickChip(
                    label:
                        '${context.l10n.tr('Half')}  ${Currency.format((remaining / 2).round(), subscription.currency)}',
                    onTap: () {
                      controller.text = '${(remaining / 2).round()}';
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      labelStyle: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
      side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Payment method ────────────────────────────────────────────────────────────

class _MethodSelector extends StatelessWidget {
  const _MethodSelector({
    required this.selected,
    required this.onChanged,
  });
  final String selected;
  final ValueChanged<String> onChanged;

  static const _methods = [
    ('cash', 'Cash', Icons.payments_outlined),
    ('card', 'Card', Icons.credit_card_outlined),
    ('transfer', 'Transfer', Icons.account_balance_outlined),
    ('cheque', 'Cheque', Icons.receipt_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _SectionCard(
      title: context.l10n.tr('Payment Method'),
      icon: Icons.wallet_outlined,
      child: Row(
        children: _methods.map((m) {
          final isSelected = selected == m.$1;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                onTap: () => onChanged(m.$1),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primaryContainer.withValues(alpha: 0.6)
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? cs.primary.withValues(alpha: 0.5)
                          : cs.outlineVariant.withValues(alpha: 0.4),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        m.$3,
                        size: 20,
                        color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.tr(m.$2),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
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

// ── Notes ─────────────────────────────────────────────────────────────────────

class _NotesField extends StatelessWidget {
  const _NotesField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SectionCard(
      title: context.l10n.tr('Notes'),
      icon: Icons.notes_outlined,
      child: TextField(
        controller: controller,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: context.l10n.tr('Optional notes about this payment…'),
          hintStyle: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 13),
          filled: true,
          fillColor: cs.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }
}

// ── Submit button ─────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.isProcessing,
    required this.canSubmit,
    required this.onPressed,
    required this.amount,
    required this.currency,
  });
  final bool isProcessing;
  final bool canSubmit;
  final VoidCallback onPressed;
  final int amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: isProcessing || !canSubmit ? null : onPressed,
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Colors.green.shade600,
          disabledBackgroundColor: Colors.grey.shade200,
        ),
        child: isProcessing
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    canSubmit
                        ? '${context.l10n.tr('Record Payment')}  •  ${Currency.format(amount, currency)}'
                        : context.l10n.tr('Enter an amount to continue'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Instalment schedule card ──────────────────────────────────────────────────

class _InstalmentScheduleCard extends StatefulWidget {
  const _InstalmentScheduleCard({
    required this.subscription,
    required this.onMarkPaid,
  });
  final UserSubscription subscription;
  final Future<void> Function(String instalmentId) onMarkPaid;

  @override
  State<_InstalmentScheduleCard> createState() =>
      _InstalmentScheduleCardState();
}

class _InstalmentScheduleCardState extends State<_InstalmentScheduleCard> {
  final Set<String> _loadingIds = {};

  static const _methodIcons = {
    'cash': Icons.payments_outlined,
    'card': Icons.credit_card_outlined,
    'transfer': Icons.account_balance_outlined,
    'cheque': Icons.receipt_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final schedule = widget.subscription.instalmentSchedule;
    final paid = schedule.where((i) => i.paid).length;
    final fmt = DateFormat('d MMM yyyy');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        color: cs.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.calendar_month_outlined,
                  size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                context.l10n.tr('Payment Plan'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: cs.primaryContainer,
                ),
                child: Text(
                  '$paid / ${schedule.length} ${context.l10n.tr('paid')}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Rows ───────────────────────────────────────────────────────
          ...schedule.asMap().entries.map((entry) {
            final idx = entry.key;
            final inst = entry.value;
            final isOverdue = inst.isOverdue;
            final isLoading = _loadingIds.contains(inst.id);

            Color statusColor;
            IconData statusIcon;
            String statusLabel;
            if (inst.paid) {
              statusColor = Colors.green.shade600;
              statusIcon = Icons.check_circle_outline;
              statusLabel = context.l10n.tr('Paid');
            } else if (isOverdue) {
              statusColor = cs.error;
              statusIcon = Icons.warning_amber_outlined;
              statusLabel = context.l10n.tr('Overdue');
            } else {
              statusColor = Colors.orange;
              statusIcon = Icons.schedule_outlined;
              statusLabel = context.l10n.tr('Upcoming');
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: inst.paid
                      ? Colors.green.withValues(alpha: 0.3)
                      : isOverdue
                          ? cs.error.withValues(alpha: 0.4)
                          : cs.outlineVariant,
                ),
                color: inst.paid
                    ? Colors.green.withValues(alpha: 0.05)
                    : isOverdue
                        ? cs.error.withValues(alpha: 0.05)
                        : null,
              ),
              child: Row(
                children: [
                  // Index badge
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    child: Center(
                      child: Text('${idx + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: statusColor)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _methodIcons[inst.method] ??
                                  Icons.payments_outlined,
                              size: 13,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              Currency.format(inst.amount, widget.subscription.currency),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          inst.paid && inst.paidAt != null
                              ? '${context.l10n.tr('Paid on')} ${fmt.format(inst.paidAt!)}'
                              : '${context.l10n.tr('Due')} ${fmt.format(inst.dueDate)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: statusColor.withValues(alpha: 0.12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(statusLabel,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor)),
                      ],
                    ),
                  ),
                  // Mark as Paid button
                  if (!inst.paid) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 32,
                      child: isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: cs.primary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                        context.l10n.tr('Mark as Paid')),
                                    content: Text(
                                      '${context.l10n.tr('Confirm payment of')} ${Currency.format(inst.amount, widget.subscription.currency)} ${context.l10n.tr('for instalment')} ${idx + 1}?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(
                                            context.l10n.tr('Cancel')),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(
                                            context.l10n.tr('Confirm')),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                setState(
                                    () => _loadingIds.add(inst.id));
                                try {
                                  await widget.onMarkPaid(inst.id);
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(SnackBar(
                                        content: Text('$e'),
                                        backgroundColor: cs.error));
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() =>
                                        _loadingIds.remove(inst.id));
                                  }
                                }
                              },
                              child: Text(
                                  context.l10n.tr('Mark as Paid'),
                                  style: const TextStyle(fontSize: 12)),
                            ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Payment history ───────────────────────────────────────────────────────────

class _PaymentHistory extends StatelessWidget {
  const _PaymentHistory({required this.subscription});
  final UserSubscription subscription;

  static const _methodIcons = {
    'cash': Icons.payments_outlined,
    'card': Icons.credit_card_outlined,
    'transfer': Icons.account_balance_outlined,
    'cheque': Icons.receipt_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final history = subscription.paymentHistory.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final fmt = DateFormat('d MMM yyyy');
    final timeFmt = DateFormat('HH:mm');

    return _SectionCard(
      title: '${context.l10n.tr('Payment History')} (${history.length})',
      icon: Icons.history_outlined,
      child: Column(
        children: history.asMap().entries.map((entry) {
          final idx = entry.key;
          final p = entry.value;
          final isLast = idx == history.length - 1;
          final methodIcon =
              _methodIcons[p.method] ?? Icons.payments_outlined;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Timeline track ─────────────────────────────────
                SizedBox(
                  width: 32,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.green.shade400, width: 1.5),
                        ),
                        child: Icon(methodIcon,
                            size: 13, color: Colors.green.shade700),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // ── Content ────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fmt.format(p.date),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 1),
                              Row(
                                children: [
                                  Text(
                                    timeFmt.format(p.date),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHigh,
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      p.method.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                              if (p.notes.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  p.notes,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.7)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Amount badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    Colors.green.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            '+${Currency.format(p.amount, subscription.currency)}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.green.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Shared section card ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                        letterSpacing: 0.2),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}
