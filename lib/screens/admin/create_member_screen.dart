import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/membership_plan.dart';
import '../../services/member_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/role_widgets.dart';

class CreateMemberScreen extends StatefulWidget {
  const CreateMemberScreen({super.key, required this.gymId});

  final String gymId;

  @override
  State<CreateMemberScreen> createState() => _CreateMemberScreenState();
}

class _CreateMemberScreenState extends State<CreateMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _memberService = MemberService(gymId: widget.gymId);
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _healthNotesController = TextEditingController();

  final Set<String> _selectedRoles = {'member'};
  String _fitnessLevel = '';
  String _gender = '';
  DateTime? _dateOfBirth;
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // ── Offer assignment (optional) ──────────────────────────────────────────
  bool _assignOffer = false;
  MembershipPlan? _selectedPlan;
  DateTime _offerStart = DateTime.now();
  DateTime _offerEnd = DateTime.now().add(const Duration(days: 30));
  final _initialPaidCtrl = TextEditingController(text: '0');

  String get _avatarInitials {
    final name = _nameController.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }

  String _passwordStrengthLabel(BuildContext context, int strength) {
    switch (strength) {
      case 1:
        return context.l10n.tr('Weak');
      case 2:
        return context.l10n.tr('Fair');
      case 3:
        return context.l10n.tr('Good');
      case 4:
        return context.l10n.tr('Strong');
      default:
        return '';
    }
  }

  int get _passwordStrength {
    final p = _passwordController.text;
    if (p.isEmpty) return 0;
    int score = 0;
    if (p.length >= 8) score++;
    if (p.contains(RegExp(r'[A-Z]'))) score++;
    if (p.contains(RegExp(r'[0-9]'))) score++;
    if (p.contains(RegExp(r'[!@#\$&*~%^()_\-+=]'))) score++;
    return score;
  }

  static const _strengthColors = [
    Colors.transparent,
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFEAB308),
    Color(0xFF22C55E),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _healthNotesController.dispose();
    _initialPaidCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(1930),
      lastDate: DateTime(now.year - 5),
      helpText: context.l10n.tr('Date of Birth'),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final uid = await _memberService.createMemberWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
        roles: _selectedRoles.toList(),
        phoneNumber: _phoneController.text.trim(),
        gender: _gender,
        dateOfBirth: _dateOfBirth,
        fitnessLevel: _fitnessLevel,
        emergencyContactName: _emergencyNameController.text.trim(),
        emergencyContactPhone: _emergencyPhoneController.text.trim(),
        healthNotes: _healthNotesController.text.trim(),
      );

      // Assign offer if the admin selected one
      if (_assignOffer && _selectedPlan != null) {
        final plan = _selectedPlan!;
        final initialPaid =
            int.tryParse(_initialPaidCtrl.text.trim()) ?? 0;
        await _subscriptionService.assignOfferAtomic(
          userId: uid,
          planId: plan.id,
          totalAmount: plan.price,
          currency: plan.currency,
          startDate: _offerStart,
          endDate: _offerEnd,
          initialAmountPaid: initialPaid.clamp(0, plan.price),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(cs),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 32 : 16,
                    vertical: 20,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAvatarCard(cs),
                        const SizedBox(height: 20),
                        if (isWide) _buildWideBody() else _buildNarrowBody(),
                        const SizedBox(height: 16),
                        _buildOfferSection(),
                        const SizedBox(height: 28),
                        _buildSubmitButton(),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            context.l10n.tr('Creates a Firebase Auth account and member profile.'),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Two-column layout (≥800 px) ───────────────────────────────────────────

  Widget _buildWideBody() => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(children: [
                _buildAccountInfoSection(),
                const SizedBox(height: 16),
                _buildPasswordSection(),
                const SizedBox(height: 16),
                _buildEmergencySection(),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(children: [
                _buildPersonalDetailsSection(),
                const SizedBox(height: 16),
                _buildFitnessSection(),
                const SizedBox(height: 16),
                _buildRolesSection(),
              ]),
            ),
          ],
        ),
      );

  // ── Single-column layout (mobile) ─────────────────────────────────────────

  Widget _buildNarrowBody() => Column(children: [
        _buildAccountInfoSection(),
        const SizedBox(height: 16),
        _buildPasswordSection(),
        const SizedBox(height: 16),
        _buildPersonalDetailsSection(),
        const SizedBox(height: 16),
        _buildFitnessSection(),
        const SizedBox(height: 16),
        _buildEmergencySection(),
        const SizedBox(height: 16),
        _buildRolesSection(),
      ]);

  // ── Gradient app bar ──────────────────────────────────────────────────────

  Widget _buildAppBar(ColorScheme cs) => SliverAppBar(
        pinned: true,
        expandedHeight: 100,
        backgroundColor: cs.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: FlexibleSpaceBar(
          background: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withValues(alpha: 0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(64, 0, 20, 14),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_add,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.tr('Add Member'),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800),
                          ),
                          Text(
                            context.l10n.tr('Create a new gym account'),
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  // ── Live avatar preview card ──────────────────────────────────────────────

  Widget _buildAvatarCard(ColorScheme cs) {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final isEmpty = name.isEmpty && email.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Text(
                _avatarInitials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEmpty ? context.l10n.tr('New Member') : (name.isEmpty ? '—' : name),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  email.isEmpty ? 'email@example.com' : email,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _selectedRoles
                      .map((r) => _MiniRoleBadge(role: r))
                      .toList(),
                ),
              ],
            ),
          ),
          Icon(Icons.preview_outlined,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5), size: 18),
          const SizedBox(width: 4),
          Text(
            context.l10n.tr('Preview'),
            style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  // ── Account Info ──────────────────────────────────────────────────────────

  Widget _buildAccountInfoSection() => _FormCard(
        title: context.l10n.tr('Account Info'),
        icon: Icons.account_circle_outlined,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: context.l10n.tr('Full name *'),
              prefixIcon: const Icon(Icons.person_outline),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? context.l10n.tr('Full name is required')
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: context.l10n.tr('Email *'),
              prefixIcon: const Icon(Icons.email_outlined),
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final e = v?.trim() ?? '';
              if (e.isEmpty) return context.l10n.tr('Email is required');
              if (!e.contains('@') || !e.contains('.')) {
                return context.l10n.tr('Enter a valid email (e.g. name@gym.com)');
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]'))
            ],
            decoration: InputDecoration(
              labelText: context.l10n.tr('Phone number'),
              prefixIcon: const Icon(Icons.phone_outlined),
              hintText: context.l10n.tr('+1 555 000 0000'),
            ),
          ),
        ],
      );

  // ── Password ──────────────────────────────────────────────────────────────

  Widget _buildPasswordSection() {
    final cs = Theme.of(context).colorScheme;
    final strength = _passwordStrength;
    final strengthColor = _strengthColors[strength];

    return _FormCard(
      title: context.l10n.tr('Temporary Password'),
      icon: Icons.lock_outlined,
      children: [
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: context.l10n.tr('Password *'),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(_obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
            ),
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.isEmpty) return context.l10n.tr('Password is required');
            if (v.length < 6) return context.l10n.tr('Minimum 6 characters');
            return null;
          },
        ),
        if (_passwordController.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: strength / 4.0,
                    minHeight: 5,
                    backgroundColor: cs.outline.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _passwordStrengthLabel(context, strength),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: strengthColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.tr('Use 8+ chars with uppercase, numbers & symbols.'),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 14),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: context.l10n.tr('Confirm password *'),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              icon: Icon(_obscureConfirm
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
            ),
          ),
          validator: (v) => (v ?? '') != _passwordController.text
              ? context.l10n.tr('Passwords do not match')
              : null,
        ),
      ],
    );
  }

  // ── Personal Details ──────────────────────────────────────────────────────

  Widget _buildPersonalDetailsSection() {
    final cs = Theme.of(context).colorScheme;
    return _FormCard(
      title: context.l10n.tr('Personal Details'),
      icon: Icons.badge_outlined,
      children: [
        Text(context.l10n.tr('Gender'),
            style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: 'male',
                label: Text(context.l10n.tr('Male')),
                icon: Icon(Icons.male, size: 16)),
            ButtonSegment(
                value: 'female',
                label: Text(context.l10n.tr('Female')),
                icon: Icon(Icons.female, size: 16)),
            ButtonSegment(
                value: 'other',
                label: Text(context.l10n.tr('Other')),
                icon: Icon(Icons.transgender, size: 16)),
          ],
          selected: _gender.isEmpty ? <String>{} : {_gender},
          emptySelectionAllowed: true,
          onSelectionChanged: (s) =>
              setState(() => _gender = s.isEmpty ? '' : s.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickDateOfBirth,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: context.l10n.tr('Date of Birth'),
              prefixIcon: const Icon(Icons.cake_outlined),
              suffixIcon: const Icon(Icons.calendar_month_outlined, size: 18),
            ),
            child: Text(
              _dateOfBirth == null
                  ? context.l10n.tr('Tap to select')
                  : '${_dateOfBirth!.day.toString().padLeft(2, '0')}/'
                      '${_dateOfBirth!.month.toString().padLeft(2, '0')}/'
                      '${_dateOfBirth!.year}',
              style: TextStyle(
                color: _dateOfBirth == null
                    ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                    : cs.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Fitness Profile ───────────────────────────────────────────────────────

  Widget _buildFitnessSection() => _FormCard(
        title: context.l10n.tr('Fitness Profile'),
        icon: Icons.fitness_center_outlined,
        children: [
          DropdownButtonFormField<String>(
            value: _fitnessLevel.isEmpty ? null : _fitnessLevel,
            decoration: InputDecoration(
              labelText: context.l10n.tr('Fitness level'),
              prefixIcon: const Icon(Icons.military_tech_outlined),
            ),
            items: [
              DropdownMenuItem(
                value: 'beginner',
                child: Row(children: [
                  Icon(Icons.looks_one_outlined, size: 16),
                  SizedBox(width: 8),
                  Text(context.l10n.tr('Beginner')),
                ]),
              ),
              DropdownMenuItem(
                value: 'intermediate',
                child: Row(children: [
                  Icon(Icons.looks_two_outlined, size: 16),
                  SizedBox(width: 8),
                  Text(context.l10n.tr('Intermediate')),
                ]),
              ),
              DropdownMenuItem(
                value: 'rx',
                child: Row(children: [
                  Icon(Icons.emoji_events_outlined, size: 16),
                  SizedBox(width: 8),
                  Text(context.l10n.tr('RX')),
                ]),
              ),
            ],
            onChanged: (v) => setState(() => _fitnessLevel = v ?? ''),
          ),
        ],
      );

  // ── Emergency Contact ─────────────────────────────────────────────────────

  Widget _buildEmergencySection() => _FormCard(
        title: context.l10n.tr('Emergency Contact'),
        icon: Icons.emergency_outlined,
        subtitle: context.l10n.tr('Optional — visible to admin and coaches'),
        children: [
          TextFormField(
            controller: _emergencyNameController,
            decoration: InputDecoration(
              labelText: context.l10n.tr('Contact name'),
              prefixIcon: const Icon(Icons.person_outlined),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _emergencyPhoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: context.l10n.tr('Contact phone'),
              prefixIcon: const Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _healthNotesController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: context.l10n.tr('Health notes'),
              prefixIcon: const Icon(Icons.medical_information_outlined),
              hintText: context.l10n.tr('Allergies, injuries, conditions…'),
              alignLabelWithHint: true,
            ),
          ),
        ],
      );

  // ── Roles & Permissions ───────────────────────────────────────────────────

  Widget _buildRolesSection() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Icon(Icons.manage_accounts_outlined,
                    size: 17, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.tr('Roles & Permissions'),
                  style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedRoles.length} ${context.l10n.tr('selected')}',
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Text(
              context.l10n.tr('A member can hold multiple roles simultaneously.'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: kAllRoles.map((role) {
                final isSelected = _selectedRoles.contains(role.id);
                final isMember = role.id == 'member';
                return RoleToggleCard(
                  role: role,
                  isSelected: isSelected,
                  isLocked: isMember,
                  onToggle: isMember
                      ? null
                      : () {
                          final next = Set<String>.from(_selectedRoles);
                          if (isSelected) {
                            next.remove(role.id);
                          } else {
                            next.add(role.id);
                          }
                          next.add('member');
                          setState(() {
                            _selectedRoles
                              ..clear()
                              ..addAll(next);
                          });
                        },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────

  // ── Offer Assignment Section ──────────────────────────────────────────────

  DateTime _addPlanDuration(DateTime from, MembershipPlan plan) {
    if (plan.durationValue <= 0) return from.add(const Duration(days: 30));
    final d = DateTime(from.year, from.month, from.day);
    return switch (plan.durationUnit) {
      'day' => d.add(Duration(days: plan.durationValue)),
      'week' => d.add(Duration(days: 7 * plan.durationValue)),
      'month' => DateTime(d.year, d.month + plan.durationValue, d.day),
      'year' => DateTime(d.year + plan.durationValue, d.month, d.day),
      _ => d.add(Duration(days: plan.durationValue)),
    };
  }

  void _onPlanSelected(MembershipPlan plan) {
    setState(() {
      _selectedPlan = plan;
      _offerEnd = _addPlanDuration(_offerStart, plan);
      _initialPaidCtrl.text = '0';
    });
  }

  Future<void> _pickOfferStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _offerStart,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _offerStart = DateTime(picked.year, picked.month, picked.day);
        if (_selectedPlan != null) {
          _offerEnd = _addPlanDuration(_offerStart, _selectedPlan!);
        } else if (_offerEnd.isBefore(_offerStart)) {
          _offerEnd = _offerStart.add(const Duration(days: 30));
        }
      });
    }
  }

  Future<void> _pickOfferEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _offerEnd,
      firstDate: _offerStart,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _offerEnd = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Widget _buildOfferSection() {
    final cs = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('d MMM yyyy');

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _assignOffer
              ? const Color(0xFF0F766E).withValues(alpha: 0.4)
              : cs.outline.withValues(alpha: 0.25),
          width: _assignOffer ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header toggle row ────────────────────────────────────────
          InkWell(
            onTap: () => setState(() {
              _assignOffer = !_assignOffer;
              if (!_assignOffer) _selectedPlan = null;
            }),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _assignOffer
                          ? const Color(0xFF0F766E).withValues(alpha: 0.12)
                          : cs.outline.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.card_membership_rounded,
                      size: 18,
                      color: _assignOffer
                          ? const Color(0xFF0F766E)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.tr('Assign Membership Offer'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _assignOffer
                                ? const Color(0xFF0F766E)
                                : cs.onSurface,
                          ),
                        ),
                        Text(
                          _assignOffer && _selectedPlan != null
                              ? '${_selectedPlan!.name}  ·  ${_selectedPlan!.price} ${_selectedPlan!.currency}'
                              : context.l10n.tr('Optional — enroll member in a plan right away'),
                          style: TextStyle(
                            fontSize: 11,
                            color: _assignOffer && _selectedPlan != null
                                ? const Color(0xFF0F766E)
                                : cs.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _assignOffer,
                    activeColor: const Color(0xFF0F766E),
                    onChanged: (v) => setState(() {
                      _assignOffer = v;
                      if (!v) _selectedPlan = null;
                    }),
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable body ──────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: _assignOffer
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      // Offer plan grid
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Text(
                          context.l10n.tr('Select a plan *'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _OfferPlanGrid(
                        gymId: widget.gymId,
                        selected: _selectedPlan,
                        onSelect: _onPlanSelected,
                      ),
                      // Date & payment config (only visible when plan selected)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: _selectedPlan == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Date range ─────────────────────────
                                    Text(
                                      context.l10n.tr('Subscription period'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF374151),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _DatePickerTile(
                                            label: context.l10n.tr('Start'),
                                            date: _offerStart,
                                            icon: Icons.play_arrow_rounded,
                                            color: const Color(0xFF059669),
                                            onTap: _pickOfferStartDate,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          child: Icon(Icons.arrow_forward_rounded,
                                              size: 16,
                                              color: cs.onSurfaceVariant),
                                        ),
                                        Expanded(
                                          child: _DatePickerTile(
                                            label: context.l10n.tr('End'),
                                            date: _offerEnd,
                                            icon: Icons.stop_rounded,
                                            color: const Color(0xFFF97316),
                                            onTap: _pickOfferEndDate,
                                            subtitle: context.l10n.tr('Auto from plan'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // ── Initial payment ────────────────────
                                    Text(
                                      context.l10n.tr('Initial payment'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF374151),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _initialPaidCtrl,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.digitsOnly
                                            ],
                                            decoration: InputDecoration(
                                              labelText:
                                                  context.l10n.tr('Amount paid now'),
                                              prefixIcon: const Icon(
                                                  Icons.payments_outlined),
                                              suffixText:
                                                  _selectedPlan?.currency ?? '',
                                              helperText:
                                                  '${context.l10n.tr('Total')}: ${_selectedPlan?.price ?? 0} ${_selectedPlan?.currency ?? ''}',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        // Quick-fill buttons
                                        Column(
                                          children: [
                                            _QuickFillBtn(
                                              label: context.l10n.tr('Full'),
                                              onTap: () => setState(() =>
                                                  _initialPaidCtrl.text =
                                                      '${_selectedPlan?.price ?? 0}'),
                                            ),
                                            const SizedBox(height: 6),
                                            _QuickFillBtn(
                                              label: context.l10n.tr('Free'),
                                              onTap: () => setState(
                                                  () => _initialPaidCtrl.text = '0'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                      ),

                      // ── Summary strip ────────────────────────────────────
                      if (_selectedPlan != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF0F766E)
                                    .withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline_rounded,
                                  color: Color(0xFF059669), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${_nameController.text.trim().isEmpty ? context.l10n.tr('Member') : _nameController.text.trim().split(' ').first} '
                                  '${context.l10n.tr('will be enrolled in')} '
                                  '${_selectedPlan!.name} '
                                  '${context.l10n.tr('from')} ${dateFmt.format(_offerStart)} '
                                  '${context.l10n.tr('to')} ${dateFmt.format(_offerEnd)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF065F46)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else
                        const SizedBox(height: 16),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────

  Widget _buildSubmitButton() => FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.person_add_outlined),
        label: Text(
          _saving ? context.l10n.tr('Creating account…') : context.l10n.tr('Create Member'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini role badge (avatar preview)
// ─────────────────────────────────────────────────────────────────────────────

class _MiniRoleBadge extends StatelessWidget {
  const _MiniRoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final color = roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        context.l10n.tr(role[0].toUpperCase() + role.substring(1)),
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable form card container
// ─────────────────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final headerBottomPad = subtitle != null ? 2.0 : 10.0;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, headerBottomPad),
            child: Row(
              children: [
                Icon(icon, size: 17, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.tr(title),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                context.l10n.tr(subtitle!),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offer Plan Grid (streams plans, shows selectable cards)
// ─────────────────────────────────────────────────────────────────────────────

class _OfferPlanGrid extends StatelessWidget {
  const _OfferPlanGrid({
    required this.gymId,
    required this.selected,
    required this.onSelect,
  });

  final String gymId;
  final MembershipPlan? selected;
  final ValueChanged<MembershipPlan> onSelect;

  static const _typeColors = <String, Color>{
    'limited_sessions': Color(0xFF0F766E),
    'pack': Color(0xFF0F766E),
    'weekly_recurring': Color(0xFF7C3AED),
    'weekly': Color(0xFF7C3AED),
    'monthly_recurring': Color(0xFFF97316),
  };

  static const _typeIcons = <String, IconData>{
    'limited_sessions': Icons.confirmation_number_outlined,
    'pack': Icons.confirmation_number_outlined,
    'weekly_recurring': Icons.repeat_one_outlined,
    'weekly': Icons.repeat_one_outlined,
    'monthly_recurring': Icons.autorenew_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final subs = SubscriptionService(gymId: gymId);
    return StreamBuilder<List<MembershipPlan>>(
      stream: subs.streamPlans(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final plans = snap.data ?? [];
        if (plans.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              context.l10n.tr('No active plans found. Create one in Offers first.'),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 600 ? 3 : 2;
              final cardWidth =
                  (constraints.maxWidth - (cols - 1) * 10) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: plans
                    .map((plan) => SizedBox(
                          width: cardWidth,
                          child: _PlanCard(
                            plan: plan,
                            isSelected: selected?.id == plan.id,
                            onTap: () => onSelect(plan),
                            color: _typeColors[plan.offerType] ??
                                const Color(0xFF0F766E),
                            icon: _typeIcons[plan.offerType] ??
                                Icons.card_membership_outlined,
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.onTap,
    required this.color,
    required this.icon,
  });

  final MembershipPlan plan;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: color.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: color, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              plan.name,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isSelected ? color : Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${plan.price} ${plan.currency}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isSelected ? color : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              plan.durationLabel,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 2),
            Text(
              plan.checkinSummary,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date picker tile
// ─────────────────────────────────────────────────────────────────────────────

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.icon,
    required this.color,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final DateTime date;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
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
                          color: color)),
                  Text(fmt.format(date),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 9, color: Colors.grey.shade400)),
                ],
              ),
            ),
            Icon(Icons.edit_calendar_outlined,
                size: 14, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick-fill button
// ─────────────────────────────────────────────────────────────────────────────

class _QuickFillBtn extends StatelessWidget {
  const _QuickFillBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: Colors.grey.shade300),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
