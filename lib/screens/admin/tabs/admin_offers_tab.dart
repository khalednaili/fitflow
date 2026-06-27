import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../models/membership_plan.dart';
import '../../../services/subscription_service.dart';

class _OfferTypeChoice {
  const _OfferTypeChoice({
    required this.value,
    required this.label,
    required this.hint,
  });

  final String value;
  final String label;
  final String hint;
}

class _DurationUnitChoice {
  const _DurationUnitChoice({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

class _DurationPreset {
  const _DurationPreset({
    required this.value,
    required this.unit,
    required this.label,
  });

  final int value;
  final String unit;
  final String label;
}

List<_OfferTypeChoice> _offerTypeChoices(AppLocalizations l10n) =>
    <_OfferTypeChoice>[
      _OfferTypeChoice(
        value: 'limited_sessions',
        label: l10n.tr('Limited: single sessions'),
        hint: l10n.tr('Fixed check-in pack used one session at a time.'),
      ),
      _OfferTypeChoice(
        value: 'weekly_recurring',
        label: l10n.tr('Weekly recurrence'),
        hint: l10n.tr('Number of check-ins allowed each week.'),
      ),
      _OfferTypeChoice(
        value: 'monthly_recurring',
        label: l10n.tr('Monthly recurrence'),
        hint: l10n.tr('Number of check-ins allowed each month.'),
      ),
    ];

List<_DurationUnitChoice> _durationUnitChoices(AppLocalizations l10n) =>
    <_DurationUnitChoice>[
      _DurationUnitChoice(value: 'day', label: l10n.tr('Days')),
      _DurationUnitChoice(value: 'week', label: l10n.tr('Weeks')),
      _DurationUnitChoice(value: 'month', label: l10n.tr('Months')),
      _DurationUnitChoice(value: 'year', label: l10n.tr('Years')),
    ];

List<_DurationPreset> _durationPresets(AppLocalizations l10n) =>
    <_DurationPreset>[
      _DurationPreset(value: 3, unit: 'month', label: l10n.tr('3 months')),
      _DurationPreset(value: 5, unit: 'month', label: l10n.tr('5 months')),
      _DurationPreset(value: 6, unit: 'month', label: l10n.tr('6 months')),
      _DurationPreset(value: 1, unit: 'year', label: l10n.tr('1 year')),
      _DurationPreset(value: 3, unit: 'year', label: l10n.tr('3 years')),
    ];

class AdminOffersTab extends StatefulWidget {
  const AdminOffersTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminOffersTab> createState() => _AdminOffersTabState();
}

class _AdminOffersTabState extends State<AdminOffersTab> {
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);
  String _search = '';
  String _filter = 'all'; // 'all' | 'active' | 'inactive'

  void _openEditor({MembershipPlan? offer}) {
    showDialog<void>(
      context: context,
      builder: (_) => _OfferEditorDialog(offer: offer, gymId: widget.gymId),
    );
  }

  Future<void> _confirmDelete(MembershipPlan offer) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.tr('Delete offer?')),
        content: Text(
            '${l10n.tr('Are you sure you want to permanently delete')} "${offer.name}"? ${l10n.tr('This cannot be undone.')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _subscriptionService.deleteOffer(planId: offer.id);
    }
  }

  Future<void> _duplicate(MembershipPlan offer) async {
    final l10n = context.l10n;
    await _subscriptionService.duplicateOffer(source: offer);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '"${offer.name}" ${l10n.tr('duplicated as inactive copy.')}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: cs.surface,
      body: StreamBuilder<List<MembershipPlan>>(
        stream: _subscriptionService.streamAllOffers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final allOffers = snapshot.data ?? <MembershipPlan>[];

          // Apply search + filter
          final filtered = allOffers.where((o) {
            final matchesFilter = _filter == 'all' ||
                (_filter == 'active' && o.active) ||
                (_filter == 'inactive' && !o.active);
            final matchesSearch = _search.isEmpty ||
                o.name.toLowerCase().contains(_search.toLowerCase()) ||
                o.description.toLowerCase().contains(_search.toLowerCase());
            return matchesFilter && matchesSearch;
          }).toList();

          final activeCount = allOffers.where((o) => o.active).length;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── TOP BAR ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: isWide
                        ? Row(
                            children: [
                              _StatPill(
                                  label: l10n.tr('Total'),
                                  value: '${allOffers.length}',
                                  color: cs.primary),
                              const SizedBox(width: 10),
                              _StatPill(
                                  label: l10n.tr('Active'),
                                  value: '$activeCount',
                                  color: Colors.green.shade600),
                              const SizedBox(width: 10),
                              _StatPill(
                                  label: l10n.tr('Inactive'),
                                  value: '${allOffers.length - activeCount}',
                                  color: Colors.grey.shade500),
                              const Spacer(),
                              SizedBox(
                                width: 240,
                                child: TextField(
                                  onChanged: (v) => setState(() => _search = v),
                                  decoration: InputDecoration(
                                    hintText: l10n.tr('Search offers…'),
                                    prefixIcon:
                                        const Icon(Icons.search, size: 18),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SegmentedButton<String>(
                                segments: [
                                  ButtonSegment(
                                    value: 'all',
                                    label: Text(l10n.tr('All')),
                                  ),
                                  ButtonSegment(
                                    value: 'active',
                                    icon: const Icon(Icons.check_circle_outline,
                                        size: 14),
                                    label: Text(l10n.tr('Active')),
                                  ),
                                  ButtonSegment(
                                    value: 'inactive',
                                    icon: const Icon(Icons.circle_outlined,
                                        size: 14),
                                    label: Text(l10n.tr('Inactive')),
                                  ),
                                ],
                                selected: {_filter},
                                onSelectionChanged: (s) =>
                                    setState(() => _filter = s.first),
                                style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                onPressed: _openEditor,
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(l10n.tr('New Offer')),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _StatPill(
                                      label: l10n.tr('Total'),
                                      value: '${allOffers.length}',
                                      color: cs.primary),
                                  const SizedBox(width: 8),
                                  _StatPill(
                                      label: l10n.tr('Active'),
                                      value: '$activeCount',
                                      color: Colors.green.shade600),
                                  const SizedBox(width: 8),
                                  _StatPill(
                                      label: l10n.tr('Inactive'),
                                      value:
                                          '${allOffers.length - activeCount}',
                                      color: Colors.grey.shade500),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                onChanged: (v) => setState(() => _search = v),
                                decoration: InputDecoration(
                                  hintText: l10n.tr('Search offers…'),
                                  prefixIcon:
                                      const Icon(Icons.search, size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    FilterChip(
                                        label: Text(l10n.tr('All')),
                                        selected: _filter == 'all',
                                        onSelected: (_) =>
                                            setState(() => _filter = 'all'),
                                        showCheckmark: false),
                                    const SizedBox(width: 8),
                                    FilterChip(
                                        label: Text(l10n.tr('Active')),
                                        selected: _filter == 'active',
                                        onSelected: (_) =>
                                            setState(() => _filter = 'active'),
                                        showCheckmark: false),
                                    const SizedBox(width: 8),
                                    FilterChip(
                                        label: Text(l10n.tr('Inactive')),
                                        selected: _filter == 'inactive',
                                        onSelected: (_) => setState(
                                            () => _filter = 'inactive'),
                                        showCheckmark: false),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),

                  // ── EMPTY STATE ──────────────────────────────────────────
                  if (filtered.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                  color: cs.primaryContainer
                                      .withValues(alpha: 0.4),
                                  shape: BoxShape.circle),
                              child: Icon(Icons.local_offer_outlined,
                                  size: 48, color: cs.primary),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              allOffers.isEmpty
                                  ? l10n.tr('No offers yet')
                                  : l10n.tr('No results found'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              allOffers.isEmpty
                                  ? l10n.tr(
                                      'Create your first membership offer to get started.')
                                  : l10n.tr(
                                      'Try adjusting your search or filter.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )

                  // ── GRID / LIST ──────────────────────────────────────────
                  else
                    Expanded(
                      child: isWide
                          ? LayoutBuilder(builder: (ctx, constraints) {
                              final cols = constraints.maxWidth >= 900 ? 3 : 2;
                              return GridView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 32),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cols,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  childAspectRatio: 1.5,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (ctx, i) => _OfferPlanCard(
                                  offer: filtered[i],
                                  subscriptionService: _subscriptionService,
                                  onEdit: () => _openEditor(offer: filtered[i]),
                                  onDelete: () => _confirmDelete(filtered[i]),
                                  onDuplicate: () => _duplicate(filtered[i]),
                                ),
                              );
                            })
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 100),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _OfferPlanCard(
                                  offer: filtered[i],
                                  subscriptionService: _subscriptionService,
                                  onEdit: () => _openEditor(offer: filtered[i]),
                                  onDelete: () => _confirmDelete(filtered[i]),
                                  onDuplicate: () => _duplicate(filtered[i]),
                                ),
                              ),
                            ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: MediaQuery.of(context).size.width < 800
          ? FloatingActionButton.extended(
              onPressed: _openEditor,
              icon: const Icon(Icons.add),
              label: Text(l10n.tr('New Offer')),
            )
          : null,
    );
  }
}

// ── Stat pill ─────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  const _StatPill(
      {required this.label, required this.value, required this.color});

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
                  fontWeight: FontWeight.w800, fontSize: 16, color: color)),
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

// ── Offer plan card ───────────────────────────────────────────────────────────

class _OfferPlanCard extends StatelessWidget {
  const _OfferPlanCard({
    required this.offer,
    required this.subscriptionService,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
  });

  final MembershipPlan offer;
  final SubscriptionService subscriptionService;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  IconData get _typeIcon {
    switch (offer.offerType) {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final activeColor = Colors.green.shade600;
    final inactiveColor = Colors.grey.shade500;
    final accentColor = offer.active ? activeColor : inactiveColor;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: offer.active
                ? activeColor.withValues(alpha: 0.3)
                : cs.outline.withValues(alpha: 0.18),
            width: offer.active ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_typeIcon, size: 22, color: accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offer.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          offer.offerTypeLabel,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  // Price
                  Text(
                    '${offer.price} ${offer.currency}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: cs.primary),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Info chips
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _InfoChip(
                      icon: Icons.timelapse_outlined,
                      label: offer.durationLabel),
                  _InfoChip(
                      icon: Icons.fitness_center_outlined,
                      label: offer.checkinSummary),
                  _InfoChip(
                      icon: Icons.sync_alt_outlined,
                      label: offer.billingCycleLabel),
                ],
              ),

              if (offer.description.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  offer.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant, height: 1.4),
                ),
              ],

              const SizedBox(height: 10),

              // Action bar
              Row(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: 0.75,
                        alignment: Alignment.centerLeft,
                        child: Switch(
                          value: offer.active,
                          activeColor: activeColor,
                          onChanged: (val) => subscriptionService
                              .setOfferActive(planId: offer.id, active: val),
                        ),
                      ),
                      Text(
                        offer.active ? l10n.tr('Active') : l10n.tr('Inactive'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accentColor),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _ActionIconButton(
                      icon: Icons.edit_outlined,
                      color: cs.primary,
                      tooltip: l10n.tr('Edit offer'),
                      onTap: onEdit),
                  const SizedBox(width: 4),
                  _ActionIconButton(
                      icon: Icons.copy_outlined,
                      color: Colors.orange.shade600,
                      tooltip: l10n.tr('Duplicate offer'),
                      onTap: onDuplicate),
                  const SizedBox(width: 4),
                  _ActionIconButton(
                      icon: Icons.delete_outline,
                      color: Colors.red.shade600,
                      tooltip: l10n.tr('Delete offer'),
                      onTap: onDelete),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: cs.primary),
            const SizedBox(width: 4),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ── Offer type metadata (icon + colors) ─────────────────────────────────────
const Map<String, IconData> _offerTypeIcons = {
  'limited_sessions': Icons.confirmation_number_outlined,
  'weekly_recurring': Icons.repeat_one_outlined,
  'monthly_recurring': Icons.autorenew_outlined,
};

const Map<String, Color> _offerTypeColors = {
  'limited_sessions': Color(0xFF0F766E), // teal
  'weekly_recurring': Color(0xFF7C3AED), // violet
  'monthly_recurring': Color(0xFFF97316), // orange
};

// ── Dialog ───────────────────────────────────────────────────────────────────
class _OfferEditorDialog extends StatefulWidget {
  const _OfferEditorDialog({this.offer, this.gymId = ''});

  final MembershipPlan? offer;
  final String gymId;

  @override
  State<_OfferEditorDialog> createState() => _OfferEditorDialogState();
}

class _OfferEditorDialogState extends State<_OfferEditorDialog> {
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _checkinsController;
  late TextEditingController _durationValueController;
  late TextEditingController _priceController;

  late String _offerType;
  late String _durationUnit;
  bool _saving = false;

  // validation
  String? _nameError;
  String? _checkinsError;
  String? _durationError;
  String? _priceError;

  @override
  void initState() {
    super.initState();
    final o = widget.offer;
    _nameController = TextEditingController(text: o?.name ?? '');
    _descriptionController = TextEditingController(text: o?.description ?? '');
    _checkinsController = TextEditingController(
        text: o != null
            ? (o.offerType == 'weekly_recurring'
                ? '${o.checkinsPerWeek}'
                : o.offerType == 'monthly_recurring'
                    ? '${o.checkinsPerMonth}'
                    : '${o.totalCheckins}')
            : '1');
    _durationValueController =
        TextEditingController(text: '${o?.durationValue ?? 1}');
    _priceController = TextEditingController(text: '${o?.price ?? 0}');
    _offerType = o?.offerType ?? 'limited_sessions';
    _durationUnit = o?.durationUnit ?? 'month';
  }

  void _applyDurationPreset(_DurationPreset preset) {
    setState(() {
      _durationValueController.text = preset.value.toString();
      _durationUnit = preset.unit;
      _durationError = null;
    });
  }

  void _stepCheckins(int delta) {
    final current = int.tryParse(_checkinsController.text) ?? 1;
    final next = (current + delta).clamp(1, 999);
    setState(() {
      _checkinsController.text = next.toString();
      _checkinsError = null;
    });
  }

  void _stepDuration(int delta) {
    final current = int.tryParse(_durationValueController.text) ?? 1;
    final next = (current + delta).clamp(1, 999);
    setState(() {
      _durationValueController.text = next.toString();
      _durationError = null;
    });
  }

  bool _validate() {
    bool ok = true;
    setState(() {
      _nameError = _nameController.text.trim().isEmpty
          ? context.l10n.tr('Offer name is required')
          : null;
      final c = int.tryParse(_checkinsController.text.trim());
      _checkinsError = (c == null || c <= 0)
          ? context.l10n.tr('Enter a positive number of sessions')
          : null;
      final d = int.tryParse(_durationValueController.text.trim());
      _durationError = (d == null || d <= 0)
          ? context.l10n.tr('Duration must be a positive number of days')
          : null;
      final p = int.tryParse(_priceController.text.trim());
      _priceError = (p == null || p < 0)
          ? context.l10n.tr('Enter a valid price (e.g. 29.99)')
          : null;
      if (_nameError != null ||
          _checkinsError != null ||
          _durationError != null ||
          _priceError != null) {
        ok = false;
      }
    });
    return ok;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _checkinsController.dispose();
    _durationValueController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_validate()) return;

    final name = _nameController.text.trim();
    final checkins = int.tryParse(_checkinsController.text.trim())!;
    final durationValue = int.tryParse(_durationValueController.text.trim())!;
    final price = int.tryParse(_priceController.text.trim())!;
    final isWeeklyType = _offerType == 'weekly_recurring';
    final isMonthlyType = _offerType == 'monthly_recurring';
    final billingCycle =
        (isWeeklyType || isMonthlyType) ? 'recurrent' : 'one_time';

    setState(() => _saving = true);

    try {
      if (widget.offer != null) {
        await _subscriptionService.updateOffer(
          planId: widget.offer!.id,
          name: name,
          description: _descriptionController.text.trim(),
          offerType: _offerType,
          checkinsPerWeek: isWeeklyType ? checkins : 0,
          checkinsPerMonth: isMonthlyType ? checkins : 0,
          totalCheckins: (!isWeeklyType && !isMonthlyType) ? checkins : 0,
          billingCycle: billingCycle,
          durationValue: durationValue,
          durationUnit: _durationUnit,
          price: price,
          currency: 'TND',
        );
      } else {
        await _subscriptionService.createCheckinOffer(
          name: name,
          description: _descriptionController.text.trim(),
          offerType: _offerType,
          checkinsPerWeek: isWeeklyType ? checkins : 0,
          checkinsPerMonth: isMonthlyType ? checkins : 0,
          totalCheckins: (!isWeeklyType && !isMonthlyType) ? checkins : 0,
          billingCycle: billingCycle,
          durationValue: durationValue,
          durationUnit: _durationUnit,
          price: price,
          currency: 'TND',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10n.tr('Error')}: $error'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isWeeklyType = _offerType == 'weekly_recurring';
    final isMonthlyType = _offerType == 'monthly_recurring';
    final checkinsLabel = isWeeklyType
        ? l10n.tr('Check-ins / week')
        : (isMonthlyType
            ? l10n.tr('Check-ins / month')
            : l10n.tr('Total check-ins'));
    final billingCycleLabel = (isWeeklyType || isMonthlyType)
        ? l10n.tr('Recurrent billing')
        : l10n.tr('One-time payment');
    final typeColor = _offerTypeColors[_offerType] ?? cs.primary;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Gradient header ──────────────────────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [typeColor, typeColor.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _offerTypeIcons[_offerType] ?? Icons.local_offer_outlined,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.offer != null
                              ? l10n.tr('Edit Offer')
                              : l10n.tr('New Membership Offer'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.tr('Configure type, sessions & pricing'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // ── Scrollable body ──────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Section: Offer Type ──────────────────────────────
                    _SectionLabel(
                        icon: Icons.category_outlined,
                        label: l10n.tr('Offer Type')),
                    const SizedBox(height: 10),
                    ...(_offerTypeChoices(l10n).map((choice) {
                      final selected = _offerType == choice.value;
                      final color =
                          _offerTypeColors[choice.value] ?? cs.primary;
                      final icon =
                          _offerTypeIcons[choice.value] ?? Icons.label_outlined;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            _offerType = choice.value;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? color.withValues(alpha: 0.08)
                                  : cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected ? color : cs.outlineVariant,
                                width: selected ? 1.8 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: color.withValues(
                                        alpha: selected ? 0.15 : 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(icon, size: 18, color: color),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        choice.label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color:
                                              selected ? color : cs.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        choice.hint,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  Icon(Icons.check_circle,
                                      color: color, size: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    })),

                    const SizedBox(height: 6),

                    // ── Section: Basic Info ──────────────────────────────
                    _SectionLabel(
                        icon: Icons.info_outline, label: l10n.tr('Basic Info')),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameController,
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: l10n.tr('Offer name *'),
                        hintText: l10n.tr('e.g. Monthly Unlimited'),
                        prefixIcon: const Icon(Icons.sell_outlined),
                        errorText: _nameError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: l10n.tr('Description (optional)'),
                        hintText:
                            l10n.tr('Short description shown to members…'),
                        prefixIcon: const Icon(Icons.notes_outlined),
                        alignLabelWithHint: true,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Section: Sessions ────────────────────────────────
                    _SectionLabel(
                        icon: Icons.fitness_center_outlined,
                        label: l10n.tr('Sessions')),
                    const SizedBox(height: 10),
                    _StepperField(
                      controller: _checkinsController,
                      label: checkinsLabel,
                      icon: Icons.confirmation_number_outlined,
                      errorText: _checkinsError,
                      onDecrement: () => _stepCheckins(-1),
                      onIncrement: () => _stepCheckins(1),
                      onChanged: (_) {
                        if (_checkinsError != null) {
                          setState(() => _checkinsError = null);
                        }
                      },
                    ),

                    const SizedBox(height: 16),

                    // ── Section: Duration ────────────────────────────────
                    _SectionLabel(
                        icon: Icons.hourglass_bottom_outlined,
                        label: l10n.tr('Duration')),
                    const SizedBox(height: 10),

                    // Quick presets
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _durationPresets(l10n).map((preset) {
                        final active = _durationValueController.text ==
                                preset.value.toString() &&
                            _durationUnit == preset.unit;
                        return FilterChip(
                          label: Text(preset.label,
                              style: const TextStyle(fontSize: 12)),
                          selected: active,
                          onSelected: (_) => _applyDurationPreset(preset),
                          showCheckmark: false,
                          avatar: Icon(Icons.bolt,
                              size: 14,
                              color: active ? cs.onPrimary : cs.primary),
                          selectedColor: typeColor,
                          labelStyle:
                              TextStyle(color: active ? Colors.white : null),
                          side: BorderSide(
                              color: active ? typeColor : cs.outlineVariant),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),

                    // Custom value + unit
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _StepperField(
                            controller: _durationValueController,
                            label: l10n.tr('Custom value'),
                            icon: Icons.timelapse_outlined,
                            errorText: _durationError,
                            onDecrement: () => _stepDuration(-1),
                            onIncrement: () => _stepDuration(1),
                            onChanged: (_) {
                              if (_durationError != null) {
                                setState(() => _durationError = null);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<String>(
                            value: _durationUnit,
                            decoration: InputDecoration(
                              labelText: l10n.tr('Unit'),
                              prefixIcon: const Icon(Icons.schedule_outlined),
                            ),
                            items: _durationUnitChoices(l10n)
                                .map(
                                  (c) => DropdownMenuItem<String>(
                                    value: c.value,
                                    child: Text(c.label),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _durationUnit = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Section: Pricing ─────────────────────────────────
                    _SectionLabel(
                        icon: Icons.payments_outlined,
                        label: l10n.tr('Pricing')),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      onChanged: (_) {
                        if (_priceError != null) {
                          setState(() => _priceError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: l10n.tr('Price *'),
                        hintText: '0',
                        prefixIcon: const Icon(Icons.attach_money_outlined),
                        suffixText: 'TND',
                        errorText: _priceError,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Billing cycle indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: typeColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.sync_alt_outlined,
                              size: 16, color: typeColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                    fontSize: 13, color: cs.onSurface),
                                children: [
                                  TextSpan(text: l10n.tr('Billing: ')),
                                  TextSpan(
                                    text: billingCycleLabel,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: typeColor),
                                  ),
                                  TextSpan(
                                    text: l10n
                                        .tr('  ·  auto-set from offer type'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Live preview card ────────────────────────────────
                    _LivePreviewCard(
                      name: _nameController.text.trim(),
                      offerType: _offerType,
                      checkinsLabel: checkinsLabel,
                      checkinsValue: _checkinsController.text,
                      durationValue: _durationValueController.text,
                      durationUnit: _durationUnit,
                      price: _priceController.text,
                      typeColor: typeColor,
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Sticky footer ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: Text(l10n.tr('Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: typeColor,
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_saving
                          ? (widget.offer != null
                              ? l10n.tr('Saving…')
                              : l10n.tr('Creating…'))
                          : (widget.offer != null
                              ? l10n.tr('Save Changes')
                              : l10n.tr('Create Offer'))),
                    ),
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

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: cs.primary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
      ],
    );
  }
}

class _StepperField extends StatelessWidget {
  const _StepperField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onDecrement,
    required this.onIncrement,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                onChanged: onChanged,
                decoration: InputDecoration(
                  labelText: label,
                  prefixIcon: Icon(icon),
                  errorText: errorText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _StepButton(
              icon: Icons.remove,
              color: cs.primary,
              onTap: onDecrement,
            ),
            const SizedBox(width: 6),
            _StepButton(
              icon: Icons.add,
              color: cs.primary,
              onTap: onIncrement,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _LivePreviewCard extends StatelessWidget {
  const _LivePreviewCard({
    required this.name,
    required this.offerType,
    required this.checkinsLabel,
    required this.checkinsValue,
    required this.durationValue,
    required this.durationUnit,
    required this.price,
    required this.typeColor,
  });

  final String name;
  final String offerType;
  final String checkinsLabel;
  final String checkinsValue;
  final String durationValue;
  final String durationUnit;
  final String price;
  final Color typeColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final displayName = name.isEmpty ? l10n.tr('Offer name…') : name;
    final displayPrice = price.isEmpty ? '0' : price;
    final icon = _offerTypeIcons[offerType] ?? Icons.local_offer_outlined;
    final unitLabel = _durationUnitChoices(l10n)
        .firstWhere((u) => u.value == durationUnit,
            orElse: () => _durationUnitChoices(l10n).first)
        .label
        .toLowerCase();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            typeColor.withValues(alpha: 0.05),
            typeColor.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: typeColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.preview_outlined, size: 13, color: typeColor),
              const SizedBox(width: 5),
              Text(
                l10n.tr('PREVIEW'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: typeColor,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: typeColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color:
                            name.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                        fontStyle:
                            name.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$checkinsValue × $checkinsLabel  ·  $durationValue $unitLabel',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$$displayPrice',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: typeColor,
                    ),
                  ),
                  Text(
                    'TND',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Action icon button ────────────────────────────────────────────────────────

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}
