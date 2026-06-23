import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/membership_plan.dart';
import '../../models/user_subscription.dart';
import '../../services/member_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/user_avatar.dart';
import 'record_payment_screen.dart';
import '../../l10n/app_localizations.dart';

// ── Offer-type visual config ──────────────────────────────────────────────────
const Map<String, IconData> _typeIcons = {
  'limited_sessions': Icons.confirmation_number_outlined,
  'pack': Icons.confirmation_number_outlined,
  'weekly_recurring': Icons.repeat_one_outlined,
  'weekly': Icons.repeat_one_outlined,
  'monthly_recurring': Icons.autorenew_outlined,
};

const Map<String, Color> _typeColors = {
  'limited_sessions': Color(0xFF0F766E),
  'pack': Color(0xFF0F766E),
  'weekly_recurring': Color(0xFF7C3AED),
  'weekly': Color(0xFF7C3AED),
  'monthly_recurring': Color(0xFFF97316),
};

// ── Screen ────────────────────────────────────────────────────────────────────

class AssignOfferScreen extends StatefulWidget {
  const AssignOfferScreen({super.key, this.initialMemberId, this.gymId = ''});
  final String? initialMemberId;
  final String gymId;

  @override
  State<AssignOfferScreen> createState() => _AssignOfferScreenState();
}

class _AssignOfferScreenState extends State<AssignOfferScreen> {
  late final _memberService = MemberService(gymId: widget.gymId);
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);
  final _initialPaidController = TextEditingController(text: '0');

  String? _selectedUserId;
  MembershipPlan? _selectedPlan;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  String _paymentMethod = 'cash';
  DateTime _paymentDate = DateTime.now();
  bool _saving = false;

  // validation
  String? _memberError;
  String? _planError;
  String? _paymentError;

  @override
  void initState() {
    super.initState();
    _selectedUserId = widget.initialMemberId;
  }

  @override
  void dispose() {
    _initialPaidController.dispose();
    super.dispose();
  }

  DateTime _addDuration(
      {required DateTime from, required int value, required String unit}) {
    final d = DateTime(from.year, from.month, from.day);
    if (value <= 0) return d;
    switch (unit) {
      case 'day':
        return d.add(Duration(days: value));
      case 'week':
        return d.add(Duration(days: 7 * value));
      case 'month':
        return DateTime(d.year, d.month + value, d.day);
      case 'year':
        return DateTime(d.year + value, d.month, d.day);
      default:
        return d.add(Duration(days: value));
    }
  }

  void _selectPlan(MembershipPlan plan) {
    final end = _addDuration(
        from: _startDate, value: plan.durationValue, unit: plan.durationUnit);
    setState(() {
      _selectedPlan = plan;
      _endDate = DateTime(end.year, end.month, end.day);
      _planError = null;
    });
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _paymentDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
      // Recompute end date from plan if one is selected
      if (_selectedPlan != null) {
        final end = _addDuration(
            from: _startDate,
            value: _selectedPlan!.durationValue,
            unit: _selectedPlan!.durationUnit);
        _endDate = DateTime(end.year, end.month, end.day);
      } else if (_endDate.isBefore(_startDate)) {
        _endDate = _startDate.add(const Duration(days: 30));
      }
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    setState(() => _endDate = DateTime(picked.year, picked.month, picked.day));
  }

  bool _validate() {
    setState(() {
      _memberError = (_selectedUserId == null || _selectedUserId!.isEmpty)
          ? context.l10n.tr('Please select a member')
          : null;
      _planError = _selectedPlan == null
          ? context.l10n.tr('Please select an offer')
          : null;
      final paid = int.tryParse(_initialPaidController.text.trim());
      _paymentError = (paid == null || paid < 0)
          ? context.l10n.tr('Enter a valid amount')
          : null;
    });
    return _memberError == null && _planError == null && _paymentError == null;
  }

  Future<void> _assign() async {
    if (!_validate()) return;

    final userId = _selectedUserId!;
    final plan = _selectedPlan!;
    final initialAmountPaid = int.tryParse(_initialPaidController.text.trim())!;

    if (initialAmountPaid > plan.price) {
      setState(() => _paymentError =
          '${context.l10n.tr('Amount cannot exceed total price')} (${plan.price} ${plan.currency})');
      return;
    }
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(context.l10n.tr('End date must be after start date.'))),
      );
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _subscriptionService.assignOfferAtomic(
        userId: userId,
        planId: plan.id,
        totalAmount: plan.price,
        currency: plan.currency,
        startDate: _startDate,
        endDate: _endDate,
        initialAmountPaid: initialAmountPaid,
        initialPaymentMethod: _paymentMethod,
        initialPaymentDate: _paymentDate,
      );

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content:
            Text('${plan.name} ${context.l10n.tr('assigned successfully!')}'),
        backgroundColor: Colors.green.shade600,
      ));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('${context.l10n.tr('Assign failed')}: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildMemberSelector(BuildContext context, ColorScheme cs) {
    return StreamBuilder<List<AppUser>>(
      stream: _memberService.streamMembers(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final members = snap.data ?? <AppUser>[];
        if (members.isEmpty) {
          return _EmptyBanner(
              message: context.l10n
                  .tr('No members found. Create a member first.'));
        }
        final validId = members.any((m) => m.id == _selectedUserId)
            ? _selectedUserId
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _memberError != null
                      ? cs.error
                      : validId != null
                          ? cs.primary.withValues(alpha: 0.5)
                          : cs.outlineVariant,
                  width: validId != null ? 1.5 : 1,
                ),
                color: validId != null
                    ? cs.primary.withValues(alpha: 0.04)
                    : cs.surfaceContainerLow,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: validId,
                  hint: Text(context.l10n.tr('Choose a member…'),
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down,
                      color:
                          validId != null ? cs.primary : cs.onSurfaceVariant),
                  items: members.map((m) {
                    final name =
                        m.displayName.isEmpty ? m.email : m.displayName;
                    return DropdownMenuItem<String>(
                      value: m.id,
                      child: Row(
                        children: [
                          UserAvatar(
                            photoUrl: m.photoUrl,
                            initials: name[0].toUpperCase(),
                            color: cs.primary,
                            radius: 14,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              m.displayName.isEmpty
                                  ? m.email
                                  : '${m.displayName}  ·  ${m.email}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedUserId = v;
                      _memberError = null;
                    });
                  },
                ),
              ),
            ),
            if (_memberError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(_memberError!,
                    style: TextStyle(fontSize: 12, color: cs.error)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildOffersSelector(BuildContext context, ColorScheme cs) {
    return StreamBuilder<List<MembershipPlan>>(
      stream: _subscriptionService.streamPlans(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _EmptyBanner(
              message:
                  '${context.l10n.tr('Could not load offers')}: ${snap.error}');
        }
        final plans = (snap.data ?? <MembershipPlan>[])
            .where((p) => p.active)
            .toList();
        if (plans.isEmpty) {
          return _EmptyBanner(
              message: context.l10n
                  .tr('No active offers. Create one in the Offers tab.'));
        }

        if (_selectedPlan == null && plans.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _selectPlan(plans.first);
          });
        }

        return Column(
          children: plans.map((plan) {
            final selected = _selectedPlan?.id == plan.id;
            final color = _typeColors[plan.offerType] ?? cs.primary;
            final icon =
                _typeIcons[plan.offerType] ?? Icons.local_offer_outlined;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _selectPlan(plan),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: selected
                          ? color.withValues(alpha: 0.07)
                          : cs.surfaceContainerLow,
                      border: Border.all(
                        color: selected ? color : cs.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: color.withValues(
                                alpha: selected ? 0.15 : 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, size: 20, color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(plan.name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color:
                                          selected ? color : cs.onSurface)),
                              const SizedBox(height: 3),
                              Text(
                                '${plan.checkinSummary}  ·  ${plan.durationLabel}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${plan.price} ${plan.currency}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: selected ? color : cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: selected
                                  ? Icon(Icons.check_circle,
                                      key: const ValueKey('on'),
                                      color: color,
                                      size: 20)
                                  : Icon(Icons.radio_button_unchecked,
                                      key: const ValueKey('off'),
                                      color: cs.outlineVariant,
                                      size: 20),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accentColor = _selectedPlan != null
        ? (_typeColors[_selectedPlan!.offerType] ?? cs.primary)
        : cs.primary;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 800;

    // ── Left column: member + offers ─────────────────────────────────────────
    Widget leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: context.l10n.tr('MEMBER'),
          step: 1,
          accentColor: accentColor,
          child: _buildMemberSelector(context, cs),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: context.l10n.tr('CHOOSE OFFER'),
          step: 2,
          accentColor: accentColor,
          errorText: _planError,
          child: _buildOffersSelector(context, cs),
        ),
      ],
    );

    // ── Right column: period + payment + button + history ────────────────────
    Widget rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: context.l10n.tr('SUBSCRIPTION PERIOD'),
          step: 3,
          accentColor: accentColor,
          child: _DateRangeCard(
            startDate: _startDate,
            endDate: _endDate,
            plan: _selectedPlan,
            onPickStart: _pickStartDate,
            onPickEnd: _pickEndDate,
            accentColor: accentColor,
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: context.l10n.tr('INITIAL PAYMENT'),
          step: 4,
          accentColor: accentColor,
          child: _selectedPlan != null
              ? _PaymentSection(
                  plan: _selectedPlan!,
                  controller: _initialPaidController,
                  errorText: _paymentError,
                  onChanged: (_) => setState(() => _paymentError = null),
                  accentColor: accentColor,
                  paymentMethod: _paymentMethod,
                  onPaymentMethodChanged: (v) =>
                      setState(() => _paymentMethod = v),
                  paymentDate: _paymentDate,
                  onPickPaymentDate: _pickPaymentDate,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(context.l10n.tr('Select an offer first'),
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
        ),
        const SizedBox(height: 20),
        // ── Assign Button ───────────────────────────────────────────────────
        MouseRegion(
          cursor: _saving
              ? SystemMouseCursors.wait
              : SystemMouseCursors.click,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _saving ? null : _assign,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.assignment_turned_in_outlined, size: 20),
            label: Text(
              _saving
                  ? context.l10n.tr('Assigning…')
                  : context.l10n.tr('Assign Offer'),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (_selectedUserId != null) ...[
          const SizedBox(height: 24),
          _ExistingSubscriptions(
            userId: _selectedUserId!,
            subscriptionService: _subscriptionService,
            gymId: widget.gymId,
          ),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLowest,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.assignment_turned_in_outlined,
                  color: accentColor, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.tr('Assign Offer'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                if (_selectedPlan != null)
                  Text(
                    '${_selectedPlan!.name} · ${_selectedPlan!.durationLabel}',
                    style: TextStyle(
                        fontSize: 11,
                        color: accentColor,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                isWide ? 24 : 16, 20, isWide ? 24 : 16, 40),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: leftColumn),
                      const SizedBox(width: 20),
                      Expanded(flex: 4, child: rightColumn),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      leftColumn,
                      const SizedBox(height: 16),
                      rightColumn,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.step,
    this.accentColor,
    this.errorText,
  });

  final String title;
  final Widget child;
  final int? step;
  final Color? accentColor;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accentColor ?? cs.primary;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                  bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4))),
            ),
            child: Row(
              children: [
                if (step != null) ...[
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('$step',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(context.l10n.tr(title),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.6)),
                if (errorText != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.error_outline, size: 13, color: cs.error),
                  const SizedBox(width: 4),
                  Text(errorText!,
                      style: TextStyle(fontSize: 11, color: cs.error)),
                ],
              ],
            ),
          ),
          // Card body
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ── Date range card ───────────────────────────────────────────────────────────

class _DateRangeCard extends StatelessWidget {
  const _DateRangeCard({
    required this.startDate,
    required this.endDate,
    required this.plan,
    required this.onPickStart,
    required this.onPickEnd,
    required this.accentColor,
  });

  final DateTime startDate;
  final DateTime endDate;
  final MembershipPlan? plan;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('EEE, d MMM yyyy');
    final totalDays = endDate.difference(startDate).inDays;
    final durationText = totalDays == 0
        ? context.l10n.tr('Same day')
        : totalDays == 1
            ? '1 ${context.l10n.tr('day')}'
            : '$totalDays ${context.l10n.tr('days')}';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
        color: accentColor.withValues(alpha: 0.04),
      ),
      child: Column(
        children: [
          // Duration banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_bottom_outlined,
                    size: 14, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  plan != null
                      ? '${plan!.durationLabel}  ·  $durationText'
                      : durationText,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accentColor),
                ),
                if (plan != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      context.l10n.tr('auto-filled'),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: accentColor),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Start date
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                    onTap: onPickStart,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.play_circle_outline,
                                  size: 13, color: Colors.green.shade600),
                              const SizedBox(width: 5),
                              Text(context.l10n.tr('START'),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.green.shade600,
                                      letterSpacing: 0.5)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            fmt.format(startDate),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.edit_outlined, size: 10, color: cs.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Text(context.l10n.tr('Edit'),
                                style: TextStyle(
                                    fontSize: 10, color: cs.onSurfaceVariant)),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  ),
                ),
                // Arrow
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    children: [
                      Icon(Icons.arrow_forward, color: accentColor, size: 20),
                    ],
                  ),
                ),
                // End date
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                    onTap: onPickEnd,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: accentColor.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.stop_circle_outlined,
                                  size: 13, color: accentColor),
                              const SizedBox(width: 5),
                              Text(context.l10n.tr('END'),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: accentColor,
                                      letterSpacing: 0.5)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            fmt.format(endDate),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: accentColor),
                          ),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.edit_outlined, size: 10, color: cs.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Text(context.l10n.tr('Override'),
                                style: TextStyle(
                                    fontSize: 10, color: cs.onSurfaceVariant)),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Payment section ───────────────────────────────────────────────────────────

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.plan,
    required this.controller,
    required this.onChanged,
    required this.accentColor,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    required this.paymentDate,
    required this.onPickPaymentDate,
    this.errorText,
  });

  final MembershipPlan plan;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final Color accentColor;
  final String paymentMethod;
  final ValueChanged<String> onPaymentMethodChanged;
  final DateTime paymentDate;
  final VoidCallback onPickPaymentDate;

  static const _methods = [
    ('cash', 'Cash', Icons.payments_outlined),
    ('card', 'Card', Icons.credit_card_outlined),
    ('transfer', 'Transfer', Icons.account_balance_outlined),
    ('cheque', 'Cheque', Icons.receipt_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final paid = int.tryParse(controller.text.trim()) ?? 0;
    final total = plan.price;
    final remaining = (total - paid).clamp(0, total);
    final progress = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
    final isFullyPaid = remaining == 0 && total > 0;
    final fmt = DateFormat('EEE, d MMM yyyy');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: accentColor.withValues(alpha: 0.25), width: 1.5),
        color: accentColor.withValues(alpha: 0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total price header
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 16, color: accentColor),
              const SizedBox(width: 8),
              Text(
                '${context.l10n.tr('Total')}: ${plan.price} ${plan.currency}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: accentColor),
              ),
              const Spacer(),
              if (isFullyPaid)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Text(context.l10n.tr('Fully Paid'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade700)),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Amount paid field
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: context.l10n.tr('Initial payment amount'),
              hintText: '0',
              prefixIcon: const Icon(Icons.attach_money_outlined),
              suffixText: plan.currency,
              errorText: errorText,
              helperText:
                  context.l10n.tr('Enter 0 if collecting payment later'),
            ),
          ),
          const SizedBox(height: 16),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                  isFullyPaid ? Colors.green.shade600 : accentColor),
            ),
          ),
          const SizedBox(height: 10),

          // Paid / remaining row
          Row(
            children: [
              _PayRow(
                  label: 'Paid',
                  value: '${paid.clamp(0, total)} ${plan.currency}',
                  color: Colors.green.shade600),
              const Spacer(),
              _PayRow(
                  label: 'Remaining',
                  value: '$remaining ${plan.currency}',
                  color: remaining > 0
                      ? Colors.orange.shade700
                      : Colors.green.shade600),
            ],
          ),

          const SizedBox(height: 20),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 14),

          // Payment method selector
          Text(context.l10n.tr('Payment Method'),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4)),
          const SizedBox(height: 10),
          Row(
            children: _methods.map((m) {
              final isSelected = paymentMethod == m.$1;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => onPaymentMethodChanged(m.$1),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accentColor.withValues(alpha: 0.1)
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? accentColor.withValues(alpha: 0.5)
                              : cs.outlineVariant.withValues(alpha: 0.4),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(m.$3,
                              size: 20,
                              color: isSelected
                                  ? accentColor
                                  : cs.onSurfaceVariant),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.tr(m.$2),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? accentColor
                                  : cs.onSurfaceVariant,
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

          const SizedBox(height: 16),

          // Payment date picker
          Text(context.l10n.tr('Payment Date'),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4)),
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
            onTap: onPickPaymentDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: accentColor),
                  const SizedBox(width: 10),
                  Text(
                    fmt.format(paymentDate),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Icon(Icons.edit_outlined, size: 14, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.tr(label),
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// ── Existing subscriptions ────────────────────────────────────────────────────

class _ExistingSubscriptions extends StatelessWidget {
  const _ExistingSubscriptions({
    required this.userId,
    required this.subscriptionService,
    required this.gymId,
  });

  final String userId;
  final SubscriptionService subscriptionService;
  final String gymId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('d MMM yyyy');

    return StreamBuilder<List<MembershipPlan>>(
      stream: subscriptionService.streamAllOffers(),
      builder: (context, planSnap) {
        final plans = planSnap.data ?? <MembershipPlan>[];
        final planById = {for (final p in plans) p.id: p};

        return StreamBuilder<List<UserSubscription>>(
          stream: subscriptionService.streamUserSubscriptions(userId),
          builder: (context, subSnap) {
            final subs = subSnap.data ?? <UserSubscription>[];
            if (subs.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StepLabel(step: null, label: context.l10n.tr('EXISTING SUBSCRIPTIONS')),
                const SizedBox(height: 10),
                ...subs.map((sub) {
                  final plan = planById[sub.planId];
                  final name = plan?.name ?? sub.planId;
                  final color = plan != null
                      ? (_typeColors[plan.offerType] ?? cs.primary)
                      : cs.primary;
                  final icon = plan != null
                      ? (_typeIcons[plan.offerType] ??
                          Icons.local_offer_outlined)
                      : Icons.local_offer_outlined;
                  final isActive = sub.status == 'active';
                  final progress = sub.totalAmount > 0
                      ? (sub.amountPaid / sub.totalAmount).clamp(0.0, 1.0)
                      : 1.0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                          color: isActive
                              ? color.withValues(alpha: 0.4)
                              : cs.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(icon, size: 16, color: color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? Colors.green.shade50
                                      : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  isActive
                                      ? '● ${context.l10n.tr('Active')}'
                                      : context.l10n.tr(
                                          sub.status[0].toUpperCase() +
                                              sub.status.substring(1)),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isActive
                                          ? Colors.green.shade700
                                          : cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (sub.startDate != null && sub.endDate != null)
                            Text(
                              '${dateFormat.format(sub.startDate!)}  →  ${dateFormat.format(sub.endDate!)}',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(999),
                            backgroundColor:
                                cs.outlineVariant.withValues(alpha: 0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                progress >= 1.0
                                    ? Colors.green.shade600
                                    : Colors.orange.shade700),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${context.l10n.tr('Paid')}: ${sub.amountPaid} / ${sub.totalAmount} ${sub.currency}',
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                              TextButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => RecordPaymentScreen(
                                      gymId: gymId,
                                      userId: userId,
                                      userName: name,
                                      initialSubscriptionId: sub.id,
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.payments_outlined,
                                    size: 15),
                                label: Text(context.l10n.tr('Record Payment'),
                                    style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.step, required this.label});
  final int? step;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (step != null) ...[
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$step',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(context.l10n.tr(label),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.primary,
                letterSpacing: 0.8)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: cs.outlineVariant)),
      ],
    );
  }
}

class _EmptyBanner extends StatelessWidget {
  const _EmptyBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(message,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
    );
  }
}
