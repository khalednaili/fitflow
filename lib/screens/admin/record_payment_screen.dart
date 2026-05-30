import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/membership_plan.dart';
import '../../models/user_subscription.dart';
import '../../services/subscription_service.dart';

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
    _amountController.addListener(() => setState(() {}));
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tr('Record Payment'),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(
              widget.userName,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<UserSubscription>>(
        stream: _subscriptionService.streamUserSubscriptions(widget.userId),
        builder: (context, subSnap) {
          final subscriptions = subSnap.data ?? <UserSubscription>[];
          final loading = subSnap.connectionState == ConnectionState.waiting;

          if (_selectedSubscriptionId == null && subscriptions.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(
                    () => _selectedSubscriptionId = subscriptions.first.id);
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
                for (final p in plansSnap.data ?? <MembershipPlan>[]) p.id: p,
              };

              if (loading) {
                return const Center(child: CircularProgressIndicator());
              }

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Offer selector ──────────────────────────
                        if (subscriptions.isEmpty)
                          _EmptyOffersCard(l10n: l10n)
                        else
                          _OfferSelector(
                            subscriptions: subscriptions,
                            plansById: plansById,
                            selectedId: _selectedSubscriptionId,
                            onChanged: (v) =>
                                setState(() => _selectedSubscriptionId = v),
                          ),

                        if (subscription != null) ...[
                          const SizedBox(height: 16),

                          // ── Balance overview ─────────────────────
                          _BalanceCard(subscription: subscription),
                          const SizedBox(height: 16),

                          // ── Amount input ─────────────────────────
                          _AmountInput(
                            controller: _amountController,
                            subscription: subscription,
                            enteredAmount: _enteredAmount,
                            onFillRemaining: () {
                              _amountController.text =
                                  '${subscription!.remainingAmount}';
                            },
                          ),
                          const SizedBox(height: 16),

                          // ── Payment method ───────────────────────
                          _MethodSelector(
                            selected: _selectedMethod,
                            onChanged: (v) =>
                                setState(() => _selectedMethod = v),
                          ),
                          const SizedBox(height: 16),

                          // ── Notes ────────────────────────────────
                          _NotesField(controller: _notesController),
                          const SizedBox(height: 24),

                          // ── Submit ───────────────────────────────
                          _SubmitButton(
                            isProcessing: _isProcessing,
                            canSubmit: _enteredAmount > 0,
                            onPressed: _recordPayment,
                            amount: _enteredAmount,
                            currency: subscription.currency,
                          ),

                          // ── Payment history ───────────────────────
                          if (subscription.paymentHistory.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _PaymentHistory(subscription: subscription),
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
                              : '${context.l10n.tr('Remaining')}: ${sub.remainingAmount} ${sub.currency}',
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

    return _SectionCard(
      title: context.l10n.tr('Current Balance'),
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        children: [
          // Progress bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 10,
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isPaid ? Colors.green.shade500 : Colors.orange.shade600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isPaid
                        ? Colors.green.shade600
                        : Colors.orange.shade700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Three stats
          Row(
            children: [
              _BalanceStat(
                label: context.l10n.tr('Total'),
                value: '${subscription.totalAmount} ${subscription.currency}',
                color: cs.onSurface,
                icon: Icons.receipt_outlined,
              ),
              const SizedBox(width: 8),
              _BalanceStat(
                label: context.l10n.tr('Paid'),
                value: '${subscription.amountPaid} ${subscription.currency}',
                color: Colors.green.shade600,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 8),
              _BalanceStat(
                label: context.l10n.tr('Remaining'),
                value:
                    '${subscription.remainingAmount} ${subscription.currency}',
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
              prefixText: '${subscription.currency}  ',
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
                          ? '${context.l10n.tr('Amount exceeds remaining balance of')} $remaining ${subscription.currency}'
                          : afterPayment == 0
                              ? context.l10n
                                  .tr('Fully paid after this payment 🎉')
                              : '${context.l10n.tr('Remaining after payment')}: $afterPayment ${subscription.currency}',
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
                        '${context.l10n.tr('Pay all')}  $remaining ${subscription.currency}',
                    onTap: onFillRemaining,
                  ),
                if (remaining > 1)
                  _QuickChip(
                    label:
                        '${context.l10n.tr('Half')}  ${(remaining / 2).round()} ${subscription.currency}',
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
                        ? '${context.l10n.tr('Record Payment')}  •  $amount $currency'
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

// ── Payment history ───────────────────────────────────────────────────────────

class _PaymentHistory extends StatelessWidget {
  const _PaymentHistory({required this.subscription});
  final UserSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final history = subscription.paymentHistory.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return _SectionCard(
      title: '${context.l10n.tr('Payment History')} (${history.length})',
      icon: Icons.history_outlined,
      child: Column(
        children: history.map((p) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.payments_outlined,
                      size: 16, color: Colors.green.shade700),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('d MMM yyyy • HH:mm').format(p.date),
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      if (p.notes.isNotEmpty)
                        Text(
                          p.notes,
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  cs.onSurfaceVariant.withValues(alpha: 0.8)),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '+${p.amount} ${subscription.currency}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade700),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(5),
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
  });
  final String title;
  final IconData icon;
  final Widget child;

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
                Text(
                  title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: 0.2),
                ),
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
