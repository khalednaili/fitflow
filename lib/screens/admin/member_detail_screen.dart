import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../../models/app_user.dart';
import '../../models/booking.dart';
import '../../models/invoice.dart';
import '../../models/membership_plan.dart';
import '../../models/user_subscription.dart';
import '../../services/billing_service.dart';
import '../../services/booking_service.dart';
import '../../services/member_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/role_widgets.dart';
import '../../widgets/user_avatar.dart';
import 'assign_offer_screen.dart';
import 'invoice_detail_screen.dart';
import 'member_assigned_offers_screen.dart';
import 'record_payment_screen.dart';
import 'tabs/admin_billing_tab.dart' show CreateInvoiceSheet;
import 'widgets/set_user_password_dialog.dart';
import '../../l10n/app_localizations.dart';

String _memberForLabel(DateTime joinDate) {
  final now = DateTime.now();
  final months = (now.year - joinDate.year) * 12 + (now.month - joinDate.month);
  if (months < 1) return '< 1m';
  if (months < 12) return '${months}m';
  final y = months ~/ 12;
  final m = months % 12;
  return m == 0 ? '${y}y' : '${y}y ${m}m';
}

class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({
    super.key,
    required this.member,
    this.asDialog = false,
  });

  final AppUser member;
  /// When true the screen is rendered inside a Dialog overlay.
  /// The wide-layout AppBar will show a close button instead of a back arrow.
  final bool asDialog;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: MemberService(gymId: member.gymId).streamUser(member.id),
      builder: (context, snap) {
        final user = snap.data ?? member;
        return _MemberDetailView(member: user, asDialog: asDialog);
      },
    );
  }
}

class _MemberDetailView extends StatefulWidget {
  const _MemberDetailView({required this.member, this.asDialog = false});

  final AppUser member;
  final bool asDialog;

  @override
  State<_MemberDetailView> createState() => _MemberDetailViewState();
}

class _MemberDetailViewState extends State<_MemberDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  AppUser get member => widget.member;

  Future<void> _generateInvoice(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => CreateInvoiceSheet(
        gymId: member.gymId,
        memberService: MemberService(gymId: member.gymId),
        subscriptionService: SubscriptionService(gymId: member.gymId),
        billingService: BillingService(gymId: member.gymId),
        preselectedMember: member,
        onCreated: (invoice) {
          Navigator.of(sheetCtx).pop();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '${context.l10n.tr('Invoice')} ${invoice.invoiceNumber} ${context.l10n.tr('generated.')}'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 900
        ? _buildWideLayout(context)
        : _buildNarrowLayout(context);
  }

  Widget _buildNarrowLayout(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── Hero App Bar ───────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: cs.surfaceContainerLowest,
            flexibleSpace: FlexibleSpaceBar(
              background: _MemberHeroHeader(member: member),
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) async {
                  if (v == 'set_password') {
                    await showSetUserPasswordDialog(
                        context: context, member: member);
                  } else if (v == 'change_role') {
                    await _showChangeRoleDialog(context);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'set_password',
                    child: ListTile(
                      leading: Icon(Icons.lock_reset_outlined),
                      title: Text(context.l10n.tr('Set password')),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'change_role',
                    child: ListTile(
                      leading: Icon(Icons.manage_accounts_outlined),
                      title: Text(context.l10n.tr('Change role')),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Stats Row ────────────────────────────────────
                  _MemberStatsRow(member: member),
                  const SizedBox(height: 16),

                  // ── Quick Actions ────────────────────────────────
                  _QuickActionsRow(member: member),
                  const SizedBox(height: 20),

                  // ── Personal Info ────────────────────────────────
                  _SectionCard(
                    title: context.l10n.tr('Personal Info'),
                    icon: Icons.person_outline,
                    children: [
                      _DetailRow(
                        icon: Icons.person_outline,
                        label: 'Name',
                        value: member.displayName.isEmpty
                            ? '—'
                            : member.displayName,
                      ),
                      _DetailRow(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: member.email,
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: member.email));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text(context.l10n.tr('Email copied')),
                                  duration: Duration(seconds: 1)),
                            );
                          },
                        ),
                      ),
                      if (member.phoneNumber.isNotEmpty)
                        _DetailRow(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          value: member.phoneNumber,
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: member.phoneNumber));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text(context.l10n.tr('Phone copied')),
                                    duration: Duration(seconds: 1)),
                              );
                            },
                          ),
                        ),
                      if (member.cinNumber.isNotEmpty)
                        _DetailRow(
                          icon: Icons.badge_outlined,
                          label: 'CIN / Passport',
                          value: member.cinNumber,
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: member.cinNumber));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        context.l10n.tr('ID number copied')),
                                    duration: Duration(seconds: 1)),
                              );
                            },
                          ),
                        ),
                      if (member.address.isNotEmpty)
                        _DetailRow(
                          icon: Icons.location_on_outlined,
                          label: 'Address',
                          value: member.address,
                        ),
                      if (member.dateOfBirth != null)
                        _DetailRow(
                          icon: Icons.cake_outlined,
                          label: 'Date of birth',
                          value: '',
                          valueWidget: Row(
                            children: [
                              Text(
                                DateFormat('d MMM yyyy')
                                    .format(member.dateOfBirth!),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (member.age != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${member.age} yrs',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green.shade700),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (member.gender.isNotEmpty)
                        _DetailRow(
                          icon: Icons.wc_outlined,
                          label: 'Gender',
                          value: _genderLabel(member.gender),
                        ),
                      if (member.joinDate != null)
                        _DetailRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Member since',
                          value:
                              '${DateFormat('MMM yyyy').format(member.joinDate!)}  •  ${_memberForLabel(member.joinDate!)}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Fitness Profile ──────────────────────────────
                  if (member.fitnessLevel.isNotEmpty ||
                      member.healthNotes.isNotEmpty)
                    _SectionCard(
                      title: context.l10n.tr('Fitness Profile'),
                      icon: Icons.fitness_center_outlined,
                      children: [
                        if (member.fitnessLevel.isNotEmpty)
                          _DetailRow(
                            icon: Icons.military_tech_outlined,
                            label: 'Fitness level',
                            value: member.fitnessLevel.toUpperCase(),
                            valueWidget:
                                _FitnessLevelBadge(level: member.fitnessLevel),
                          ),
                        if (member.healthNotes.isNotEmpty)
                          _DetailRow(
                            icon: Icons.medical_information_outlined,
                            label: 'Health notes',
                            value: member.healthNotes,
                          ),
                      ],
                    ),
                  if (member.fitnessLevel.isNotEmpty ||
                      member.healthNotes.isNotEmpty)
                    const SizedBox(height: 14),

                  // ── Emergency Contact ────────────────────────────
                  if (member.emergencyContactName.isNotEmpty)
                    _SectionCard(
                      title: context.l10n.tr('Emergency Contact'),
                      icon: Icons.contact_emergency_outlined,
                      children: [
                        _DetailRow(
                          icon: Icons.person_outline,
                          label: 'Name',
                          value: member.emergencyContactName,
                        ),
                        if (member.emergencyContactPhone.isNotEmpty)
                          _DetailRow(
                            icon: Icons.phone_in_talk_outlined,
                            label: 'Phone',
                            value: member.emergencyContactPhone,
                          ),
                      ],
                    ),
                  if (member.emergencyContactName.isNotEmpty)
                    const SizedBox(height: 14),

                  // ── Admin Note ───────────────────────────────────
                  _AdminNoteSection(member: member),
                  const SizedBox(height: 14),

                  // ── Recent Activity ──────────────────────────────
                  _RecentActivitySection(member: member),
                  const SizedBox(height: 14),

                  // ── Subscriptions ────────────────────────────────
                  _SubscriptionsSection(member: member),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName =
        member.displayName.isEmpty ? member.email : member.displayName;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLowest,
        elevation: 0,
        scrolledUnderElevation: 1,
        automaticallyImplyLeading: !widget.asDialog,
        leading: widget.asDialog
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: context.l10n.tr('Close'),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Row(
          children: [
            UserAvatar(
              radius: 16,
              photoUrl: member.photoUrl,
              initials: displayName[0].toUpperCase(),
              color: _roleColor(member.role),
            ),
            const SizedBox(width: 10),
            Text(displayName,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(width: 10),
            ..._roleBadges(),
          ],
        ),
        actions: [
          FilledButton.tonalIcon(
            onPressed: () => _generateInvoice(context),
            icon: const Icon(Icons.receipt_long_outlined, size: 16),
            label: Text(context.l10n.tr('Generate Invoice')),
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor:
                    const Color(0xFF0F766E).withValues(alpha: 0.12),
                foregroundColor: const Color(0xFF0F766E)),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () => showDialog(
                context: context,
                builder: (_) => _EditProfileDialog(member: member)),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(context.l10n.tr('Edit Profile')),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              if (v == 'set_password') {
                await showSetUserPasswordDialog(
                    context: context, member: member);
              } else if (v == 'change_role') {
                await _showChangeRoleDialog(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'set_password',
                child: ListTile(
                    leading: Icon(Icons.lock_reset_outlined),
                    title: Text(context.l10n.tr('Set password')),
                    contentPadding: EdgeInsets.zero),
              ),
              PopupMenuItem(
                value: 'change_role',
                child: ListTile(
                    leading: Icon(Icons.manage_accounts_outlined),
                    title: Text(context.l10n.tr('Change role')),
                    contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── LEFT SIDEBAR ──────────────────────────────────────────
              SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 10, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WebProfileCard(member: member),
                      const SizedBox(height: 14),
                      _WebStatsGrid(member: member),
                      const SizedBox(height: 14),
                      _WebQuickActions(member: member),
                    ],
                  ),
                ),
              ),

              // ── RIGHT CONTENT ─────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tab bar
                    Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        border: Border(
                          bottom: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tabs: [
                          Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_outline, size: 15),
                                SizedBox(width: 6),
                                Text(context.l10n.tr('Profile')),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history_outlined, size: 15),
                                SizedBox(width: 6),
                                Text(context.l10n.tr('Activity')),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.card_membership_outlined, size: 15),
                                SizedBox(width: 6),
                                Text(context.l10n.tr('Subscriptions')),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 15),
                                SizedBox(width: 6),
                                Text(context.l10n.tr('Invoices')),
                              ],
                            ),
                          ),
                        ],
                        labelStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                        unselectedLabelStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorWeight: 2.5,
                        dividerColor: Colors.transparent,
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _WebProfileTab(member: member),
                          _WebActivityTab(member: member),
                          SingleChildScrollView(
                            padding:
                                const EdgeInsets.fromLTRB(20, 20, 20, 40),
                            child: _SubscriptionsSection(member: member),
                          ),
                          _MemberInvoicesTab(member: member,
                              onGenerate: () => _generateInvoice(context)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _roleBadges() {
    return member.effectiveRoles
        .map((r) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _RoleBadge(role: r),
            ))
        .toList();
  }

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

  Future<void> _showChangeRoleDialog(BuildContext context) async {
    final selectedRoles = Set<String>.from(
        member.roles.isNotEmpty ? member.roles : [member.role]);
    // Always ensure 'member' is present
    selectedRoles.add('member');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Dialog(
          clipBehavior: Clip.antiAlias,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.manage_accounts,
                          color: Theme.of(ctx).colorScheme.onPrimaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(context.l10n.tr('Manage Roles'),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onPrimaryContainer)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Select all roles that apply. Member is always required.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                ),
                // Role cards
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      const RoleDef(
                        id: 'member',
                        label: 'Member',
                        description: 'Can book classes and view schedule',
                        icon: Icons.person_outline,
                        color: Color(0xFF0F766E),
                      ),
                      const RoleDef(
                        id: 'coach',
                        label: 'Coach',
                        description:
                            'Coach portal with class planning & check-in',
                        icon: Icons.sports_outlined,
                        color: Color(0xFF2563EB),
                      ),
                      const RoleDef(
                        id: 'staff',
                        label: 'Staff',
                        description:
                            'Access to admin panel and management tools',
                        icon: Icons.badge_outlined,
                        color: Color(0xFF7C3AED),
                      ),
                      const RoleDef(
                        id: 'admin',
                        label: 'Admin',
                        description: 'Full access — manages all settings',
                        icon: Icons.admin_panel_settings_outlined,
                        color: Color(0xFFDC2626),
                      ),
                    ].map((roleDef) {
                      final isSelected = selectedRoles.contains(roleDef.id);
                      final isMember = roleDef.id == 'member';
                      return RoleToggleCard(
                        role: roleDef,
                        isSelected: isSelected,
                        isLocked: isMember,
                        onToggle: isMember
                            ? null
                            : () {
                                setDlgState(() {
                                  if (isSelected) {
                                    selectedRoles.remove(roleDef.id);
                                  } else {
                                    selectedRoles.add(roleDef.id);
                                  }
                                  selectedRoles.add('member');
                                });
                              },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 4),
                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: Theme.of(ctx).colorScheme.outlineVariant)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(context.l10n.tr('Cancel')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          await MemberService(gymId: member.gymId).updateRoles(
                              userId: member.id, roles: selectedRoles.toList());
                          // ignore: use_build_context_synchronously
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.save, size: 16),
                        label: Text(context.l10n.tr('Save Roles')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _genderLabel(String g) {
    switch (g) {
      case 'male':
        return 'Male';
      case 'female':
        return 'Female';
      case 'prefer_not_to_say':
        return 'Prefer not to say';
      default:
        return g;
    }
  }
}

// ── Hero header ──────────────────────────────────────────────────────────────

class _MemberHeroHeader extends StatelessWidget {
  const _MemberHeroHeader({required this.member});

  final AppUser member;

  String get _displayName =>
      member.displayName.isEmpty ? member.email : member.displayName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = _displayName[0].toUpperCase();
    final statusColor = _statusColor(member.subscriptionStatus);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primary.withValues(alpha: 0.08),
            cs.surfaceContainerLowest,
          ],
        ),
        border: Border(
            bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      ),
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 56, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          Stack(
            children: [
              UserAvatar(
                photoUrl: member.photoUrl,
                initials: initials,
                color: _roleColor(member.role),
                radius: 44,
              ),
              // Status dot
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: cs.surfaceContainerLowest, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _displayName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  member.email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (member.phoneNumber.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.phone_outlined,
                          size: 11, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          member.phoneNumber,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ...member.effectiveRoles.map((r) => _RoleBadge(role: r)),
                    _StatusBadge(status: member.subscriptionStatus),
                    if (member.fitnessLevel.isNotEmpty)
                      _FitnessLevelBadge(level: member.fitnessLevel),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (member.age != null)
                      _InfoPill(
                          icon: Icons.cake_outlined,
                          label: '${member.age} yrs'),
                    if (member.joinDate != null)
                      _InfoPill(
                          icon: Icons.calendar_month_outlined,
                          label:
                              'Member for ${_memberForLabel(member.joinDate!)}'),
                    _InfoPill(
                        icon: Icons.fingerprint_outlined,
                        label: member.id.length > 6
                            ? member.id.substring(member.id.length - 6)
                            : member.id),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green.shade500;
      case 'paused':
        return Colors.orange.shade500;
      case 'cancelled':
        return Colors.red.shade500;
      default:
        return Colors.grey.shade400;
    }
  }

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
}

// ── Quick actions row ────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.member});

  final AppUser member;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionButton(
          icon: Icons.edit_outlined,
          label: 'Edit\nProfile',
          color: Theme.of(context).colorScheme.tertiary,
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _EditProfileDialog(member: member),
          ),
        ),
        const SizedBox(width: 10),
        _ActionButton(
          icon: Icons.assignment_turned_in_outlined,
          label: 'Assign\nOffer',
          color: Theme.of(context).colorScheme.primary,
          onTap: () async {
            final assigned = await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => AssignOfferScreen(
                    initialMemberId: member.id, gymId: member.gymId),
              ),
            );
            if (assigned == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.tr('Offer assigned.'))),
              );
            }
          },
        ),
        const SizedBox(width: 10),
        _ActionButton(
          icon: Icons.payments_outlined,
          label: 'Record\nPayment',
          color: Colors.green.shade600,
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => RecordPaymentScreen(
                gymId: member.gymId,
                userId: member.id,
                userName: member.displayName.isEmpty
                    ? member.email
                    : member.displayName,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _ActionButton(
          icon: Icons.receipt_long_outlined,
          label: 'All\nOffers',
          color: Colors.orange.shade600,
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => MemberAssignedOffersScreen(member: member),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _ActionButton(
          icon: Icons.description_outlined,
          label: 'Invoice',
          color: const Color(0xFF0F766E),
          onTap: () async {
            final ctx = context;
            await showModalBottomSheet<void>(
              context: ctx,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (sheetCtx) => CreateInvoiceSheet(
                gymId: member.gymId,
                memberService: MemberService(gymId: member.gymId),
                subscriptionService:
                    SubscriptionService(gymId: member.gymId),
                billingService: BillingService(gymId: member.gymId),
                preselectedMember: member,
                onCreated: (invoice) {
                  Navigator.of(sheetCtx).pop();
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(
                          '${ctx.l10n.tr('Invoice')} ${invoice.invoiceNumber} ${ctx.l10n.tr('generated.')}'),
                      backgroundColor: Colors.green.shade700,
                    ));
                  }
                },
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        _ActionButton(
          icon: Icons.lock_reset_outlined,
          label: 'Set\nPassword',
          color: Colors.blueGrey.shade600,
          onTap: () =>
              showSetUserPasswordDialog(context: context, member: member),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                context.l10n.tr(label),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 17, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.tr(title),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children.map((child) => child),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueWidget,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? valueWidget;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              context.l10n.tr(label),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: valueWidget ??
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ── Subscriptions section ────────────────────────────────────────────────────

class _SubscriptionsSection extends StatelessWidget {
  const _SubscriptionsSection({required this.member});

  final AppUser member;

  @override
  Widget build(BuildContext context) {
    final subscriptionService = SubscriptionService(gymId: member.gymId);

    return StreamBuilder<List<UserSubscription>>(
      stream: subscriptionService.streamUserSubscriptions(member.id),
      builder: (context, subSnap) {
        final subs = subSnap.data ?? <UserSubscription>[];

        return StreamBuilder<List<MembershipPlan>>(
          stream: subscriptionService.streamAllOffers(),
          builder: (context, planSnap) {
            final planById = <String, MembershipPlan>{
              for (final p in planSnap.data ?? <MembershipPlan>[]) p.id: p,
            };

            return _SectionCard(
              title: '${context.l10n.tr('Subscriptions')} (${subs.length})',
              icon: Icons.card_membership_outlined,
              children: subs.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No subscriptions yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ]
                  : subs
                      .map((s) => _SubscriptionTile(
                            subscription: s,
                            plan: planById[s.planId],
                            member: member,
                          ))
                      .toList(),
            );
          },
        );
      },
    );
  }
}

class _SubscriptionTile extends StatefulWidget {
  const _SubscriptionTile({
    required this.subscription,
    required this.plan,
    required this.member,
  });

  final UserSubscription subscription;
  final MembershipPlan? plan;
  final AppUser member;

  @override
  State<_SubscriptionTile> createState() => _SubscriptionTileState();
}

class _SubscriptionTileState extends State<_SubscriptionTile> {
  late final _subscriptionService =
      SubscriptionService(gymId: widget.member.gymId);
  bool _working = false;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _extendPeriod() async {
    final current = widget.subscription.endDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(DateTime.now()) ? current : DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      helpText: 'Select new end date',
    );
    if (picked == null || !mounted) return;

    setState(() => _working = true);
    try {
      await _subscriptionService.extendOffer(
        subscriptionId: widget.subscription.id,
        newEndDate: picked,
      );
      _snack('Offer extended to ${DateFormat('d MMM yyyy').format(picked)}');
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'extendAssignedOffer');
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _unassign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.link_off_rounded, color: Colors.red, size: 32),
        title: Text(context.l10n.tr('Unassign offer?')),
        content: Text(
          'This will remove the "${widget.plan?.name ?? widget.subscription.planId}" offer '
          'from ${widget.member.displayName.isEmpty ? widget.member.email : widget.member.displayName}.\n\n'
          'The subscription record will be deleted and their status reset to "none".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Unassign')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    try {
      await _subscriptionService.unassignOffer(
        subscriptionId: widget.subscription.id,
        userId: widget.member.id,
      );
      _snack('Offer unassigned successfully');
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'unassignAssignedOffer');
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = widget.subscription;
    final plan = widget.plan;
    final dateFormat = DateFormat('d MMM yyyy');
    final endText = sub.endDate == null ? '—' : dateFormat.format(sub.endDate!);
    final pct = sub.paymentPercentage;

    final Color statusColor;
    switch (sub.status) {
      case 'active':
        statusColor = Colors.green.shade600;
      case 'cancelled':
        statusColor = Colors.red.shade600;
      default:
        statusColor = Colors.orange.shade600;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title row ─────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan?.name ?? sub.planId,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      sub.status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Stats + payment ring ──────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SubStat(
                            label: 'Paid',
                            value: '${sub.amountPaid} ${sub.currency}',
                            color: Colors.green.shade600),
                        const SizedBox(height: 2),
                        _SubStat(
                            label: 'Remaining',
                            value: '${sub.remainingAmount} ${sub.currency}',
                            color: sub.remainingAmount > 0
                                ? Colors.orange.shade600
                                : Colors.green.shade600),
                        const SizedBox(height: 2),
                        _SubStat(
                            label: 'Expires',
                            value: endText,
                            color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: pct,
                          strokeWidth: 6,
                          backgroundColor: cs.outline.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            pct >= 1.0 ? Colors.green.shade500 : cs.primary,
                          ),
                        ),
                        Text(
                          '${(pct * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Action buttons ────────────────────────────────────
              if (_working)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(),
                ))
              else ...[
                // Record payment
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
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
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: Text(context.l10n.tr('Update payment history')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Extend period
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _extendPeriod,
                        icon: const Icon(Icons.date_range_outlined, size: 16),
                        label: Text(context.l10n.tr('Extend period')),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          foregroundColor: Colors.blue.shade700,
                          side: BorderSide(color: Colors.blue.shade200),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Unassign offer
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _unassign,
                        icon: const Icon(Icons.link_off_rounded, size: 16),
                        label: Text(context.l10n.tr('Unassign')),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          foregroundColor: Colors.red.shade600,
                          side: BorderSide(color: Colors.red.shade200),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SubStat extends StatelessWidget {
  const _SubStat(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${context.l10n.tr(label)}: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
        ),
      ],
    );
  }
}

// ── Shared badge widgets ──────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (role) {
      case 'admin':
      case 'owner':
        bg = const Color(0xFFEDE9FE);
        fg = const Color(0xFF7C3AED);
      case 'coach':
        bg = const Color(0xFFCCFBF1);
        fg = const Color(0xFF0F766E);
      case 'staff':
        bg = const Color(0xFFFEF9C3);
        fg = const Color(0xFFB45309);
      default:
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF2563EB);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: fg,
            letterSpacing: 0.4),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (status) {
      case 'active':
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
      case 'paused':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade700;
      case 'cancelled':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade600;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        status == 'none' ? 'NO PLAN' : status.toUpperCase(),
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: fg,
            letterSpacing: 0.4),
      ),
    );
  }
}

class _FitnessLevelBadge extends StatelessWidget {
  const _FitnessLevelBadge({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (level) {
      case 'rx':
        color = Colors.red.shade600;
      case 'intermediate':
        color = Colors.orange.shade600;
      default:
        color = Colors.green.shade600;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        level.toUpperCase(),
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.4),
      ),
    );
  }
}

// ── Info pill ────────────────────────────────────────────────────────────────

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            context.l10n.tr(label),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Member stats row ─────────────────────────────────────────────────────────

class _MemberStatsRow extends StatefulWidget {
  const _MemberStatsRow({required this.member});

  final AppUser member;

  @override
  State<_MemberStatsRow> createState() => _MemberStatsRowState();
}

class _MemberStatsRowState extends State<_MemberStatsRow> {
  late final _bookingService = BookingService(gymId: widget.member.gymId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: _bookingService.streamBookingsForUser(widget.member.id),
      builder: (context, snap) {
        final bookings = snap.data ?? <Booking>[];
        final now = DateTime.now();
        final totalBookings = bookings.length;
        final checkedIn = bookings.where((b) => b.checkedIn).length;
        final rate =
            totalBookings > 0 ? (checkedIn / totalBookings * 100).round() : 0;
        final thisMonth = bookings
            .where((b) =>
                b.createdAt.year == now.year && b.createdAt.month == now.month)
            .length;

        return Row(
          children: [
            Expanded(
                child: _StatCard(value: '$totalBookings', label: 'Bookings')),
            const SizedBox(width: 8),
            Expanded(child: _StatCard(value: '$checkedIn', label: 'Check-ins')),
            const SizedBox(width: 8),
            Expanded(child: _StatCard(value: '$rate%', label: 'Rate')),
            const SizedBox(width: 8),
            Expanded(child: _StatCard(value: '$thisMonth', label: 'This mo.')),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, this.icon});

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: cs.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 3),
          ],
          Text(
            value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: cs.primary),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.tr(label),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Recent activity section ──────────────────────────────────────────────────

class _RecentActivitySection extends StatefulWidget {
  const _RecentActivitySection({required this.member});

  final AppUser member;

  @override
  State<_RecentActivitySection> createState() => _RecentActivitySectionState();
}

class _RecentActivitySectionState extends State<_RecentActivitySection> {
  late final _bookingService = BookingService(gymId: widget.member.gymId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: _bookingService.streamBookingsForUser(widget.member.id),
      builder: (context, snap) {
        final bookings = (snap.data ?? <Booking>[]).take(6).toList();

        return _SectionCard(
          title: context.l10n.tr('Recent Activity'),
          icon: Icons.history_outlined,
          children: [
            if (bookings.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(context.l10n.tr('No activity yet.'),
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ...bookings.map((b) => _BookingActivityTile(booking: b)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: null,
                child: Text(context.l10n.tr('See all')),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BookingActivityTile extends StatelessWidget {
  const _BookingActivityTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('classes')
          .doc(booking.classId)
          .get(),
      builder: (ctx, snap) {
        final data = snap.data?.data();
        final title = data?['title'] as String? ?? 'Class';
        final startTime = (data?['startTime'] as Timestamp?)?.toDate();
        final displayTime = startTime ?? booking.createdAt;

        final attended = booking.checkedIn;
        final avatarColor =
            attended ? Colors.green.shade100 : Colors.grey.shade100;
        final iconColor =
            attended ? Colors.green.shade700 : Colors.grey.shade500;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: avatarColor,
            child: Icon(
              attended ? Icons.check : Icons.hourglass_empty_outlined,
              size: 14,
              color: iconColor,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            DateFormat('EEE d MMM • HH:mm').format(displayTime),
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: attended ? Colors.green.shade50 : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              attended ? 'Attended' : 'Pending',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: attended ? Colors.green.shade700 : cs.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Web layout widgets ────────────────────────────────────────────────────────

class _WebProfileCard extends StatelessWidget {
  const _WebProfileCard({required this.member});
  final AppUser member;

  String get _displayName =>
      member.displayName.isEmpty ? member.email : member.displayName;

  Color get _roleColor {
    switch (member.role) {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColorFor(member.subscriptionStatus);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // Gradient top area
          Container(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _roleColor.withValues(alpha: 0.10),
                  _roleColor.withValues(alpha: 0.03),
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // Avatar
                Stack(
                  children: [
                    UserAvatar(
                      photoUrl: member.photoUrl,
                      initials: _displayName[0].toUpperCase(),
                      color: _roleColor,
                      radius: 44,
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: cs.surfaceContainerLowest, width: 2.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  member.email,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                if (member.phoneNumber.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_outlined,
                          size: 11, color: cs.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        member.phoneNumber,
                        style:
                            TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    ...member.effectiveRoles.map((r) => _RoleBadge(role: r)),
                    _StatusBadge(status: member.subscriptionStatus),
                    if (member.fitnessLevel.isNotEmpty)
                      _FitnessLevelBadge(level: member.fitnessLevel),
                  ],
                ),
              ],
            ),
          ),
          // Info pills row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (member.age != null)
                  _InfoPill(
                      icon: Icons.cake_outlined, label: '${member.age} yrs'),
                if (member.joinDate != null)
                  _InfoPill(
                      icon: Icons.calendar_month_outlined,
                      label: _memberForLabel(member.joinDate!)),
                if (member.cinNumber.isNotEmpty)
                  _InfoPill(
                      icon: Icons.badge_outlined, label: member.cinNumber),
                if (member.gender.isNotEmpty)
                  _InfoPill(
                      icon: Icons.wc_outlined,
                      label: member.gender == 'male'
                          ? 'Male'
                          : member.gender == 'female'
                              ? 'Female'
                              : 'Other'),
                _InfoPill(
                  icon: Icons.fingerprint_outlined,
                  label: member.id.length > 6
                      ? member.id.substring(member.id.length - 6)
                      : member.id,
                ),
              ],
            ),
          ),
          if (member.address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      member.address,
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColorFor(String status) {
    switch (status) {
      case 'active':
        return Colors.green.shade500;
      case 'paused':
        return Colors.orange.shade500;
      case 'cancelled':
        return Colors.red.shade500;
      default:
        return Colors.grey.shade400;
    }
  }
}

class _WebStatsGrid extends StatefulWidget {
  const _WebStatsGrid({required this.member});
  final AppUser member;

  @override
  State<_WebStatsGrid> createState() => _WebStatsGridState();
}

class _WebStatsGridState extends State<_WebStatsGrid> {
  late final _bookingService = BookingService(gymId: widget.member.gymId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: _bookingService.streamBookingsForUser(widget.member.id),
      builder: (context, snap) {
        final bookings = snap.data ?? <Booking>[];
        final now = DateTime.now();
        final totalBookings = bookings.length;
        final checkedIn = bookings.where((b) => b.checkedIn).length;
        final rate =
            totalBookings > 0 ? (checkedIn / totalBookings * 100).round() : 0;
        final thisMonth = bookings
            .where((b) =>
                b.createdAt.year == now.year && b.createdAt.month == now.month)
            .length;

        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.5,
          children: [
            _StatCard(
                value: '$totalBookings',
                label: 'Bookings',
                icon: Icons.event_outlined),
            _StatCard(
                value: '$checkedIn',
                label: 'Check-ins',
                icon: Icons.how_to_reg_outlined),
            _StatCard(
                value: '$rate%',
                label: 'Att. Rate',
                icon: Icons.trending_up_outlined),
            _StatCard(
                value: '$thisMonth',
                label: 'This Month',
                icon: Icons.today_outlined),
          ],
        );
      },
    );
  }
}

class _WebQuickActions extends StatelessWidget {
  const _WebQuickActions({required this.member});
  final AppUser member;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              'Actions',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  letterSpacing: 0.4),
            ),
          ),
          const Divider(height: 1),
          _QuickActionTile(
            icon: Icons.receipt_long_outlined,
            label: 'Generate Invoice',
            color: const Color(0xFF0F766E),
            onTap: () async {
              final ctx = context;
              await showModalBottomSheet<void>(
                context: ctx,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (sheetCtx) => CreateInvoiceSheet(
                  gymId: member.gymId,
                  memberService: MemberService(gymId: member.gymId),
                  subscriptionService:
                      SubscriptionService(gymId: member.gymId),
                  billingService: BillingService(gymId: member.gymId),
                  preselectedMember: member,
                  onCreated: (invoice) {
                    Navigator.of(sheetCtx).pop();
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(
                            '${ctx.l10n.tr('Invoice')} ${invoice.invoiceNumber} ${ctx.l10n.tr('generated.')}'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.green.shade700,
                      ));
                    }
                  },
                ),
              );
            },
          ),
          _QuickActionTile(
            icon: Icons.assignment_turned_in_outlined,
            label: 'Assign Offer',
            color: cs.primary,
            onTap: () async {
              final assigned = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                    builder: (_) => AssignOfferScreen(
                        initialMemberId: member.id, gymId: member.gymId)),
              );
              if (assigned == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(context.l10n.tr('Offer assigned.'))));
              }
            },
          ),
          _QuickActionTile(
            icon: Icons.payments_outlined,
            label: 'Record Payment',
            color: Colors.green.shade600,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => RecordPaymentScreen(
                  gymId: member.gymId,
                  userId: member.id,
                  userName: member.displayName.isEmpty
                      ? member.email
                      : member.displayName,
                ),
              ),
            ),
          ),
          _QuickActionTile(
            icon: Icons.receipt_long_outlined,
            label: 'All Offers',
            color: Colors.orange.shade600,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                  builder: (_) => MemberAssignedOffersScreen(member: member)),
            ),
          ),
          _QuickActionTile(
            icon: Icons.lock_reset_outlined,
            label: 'Set Password',
            color: Colors.blueGrey.shade600,
            onTap: () =>
                showSetUserPasswordDialog(context: context, member: member),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 12),
            Text(context.l10n.tr(label),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.chevron_right,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _WebProfileTab extends StatelessWidget {
  const _WebProfileTab({required this.member});
  final AppUser member;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left column ─────────────────────────────────────
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionCard(
                  title: context.l10n.tr('Personal Info'),
                  icon: Icons.person_outline,
                  children: [
                    _DetailRow(
                      icon: Icons.person_outline,
                      label: 'Name',
                      value:
                          member.displayName.isEmpty ? '—' : member.displayName,
                    ),
                    _DetailRow(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: member.email,
                      trailing: Builder(
                        builder: (ctx) => IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: member.email));
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                content: Text(context.l10n.tr('Email copied')),
                                duration: Duration(seconds: 1)));
                          },
                        ),
                      ),
                    ),
                    if (member.phoneNumber.isNotEmpty)
                      _DetailRow(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: member.phoneNumber,
                        trailing: Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: member.phoneNumber));
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                  content:
                                      Text(context.l10n.tr('Phone copied')),
                                  duration: Duration(seconds: 1)));
                            },
                          ),
                        ),
                      ),
                    if (member.cinNumber.isNotEmpty)
                      _DetailRow(
                        icon: Icons.badge_outlined,
                        label: 'CIN / Passport',
                        value: member.cinNumber,
                        trailing: Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: member.cinNumber));
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                  content: Text(context.l10n.tr('ID copied')),
                                  duration: Duration(seconds: 1)));
                            },
                          ),
                        ),
                      ),
                    if (member.address.isNotEmpty)
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        label: 'Address',
                        value: member.address,
                      ),
                    if (member.dateOfBirth != null)
                      _DetailRow(
                        icon: Icons.cake_outlined,
                        label: 'Date of birth',
                        value: '',
                        valueWidget: Row(children: [
                          Text(
                            DateFormat('d MMM yyyy')
                                .format(member.dateOfBirth!),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (member.age != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                  '${member.age} ${context.l10n.tr('yrs')}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.green.shade700)),
                            ),
                          ],
                        ]),
                      ),
                    if (member.gender.isNotEmpty)
                      _DetailRow(
                        icon: Icons.wc_outlined,
                        label: 'Gender',
                        value: _genderLabel(member.gender),
                      ),
                    if (member.joinDate != null)
                      _DetailRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'Member since',
                        value:
                            '${DateFormat('MMM yyyy').format(member.joinDate!)}  •  ${_memberForLabel(member.joinDate!)}',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _AdminNoteSection(member: member),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // ── Right column ────────────────────────────────────
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (member.fitnessLevel.isNotEmpty ||
                    member.healthNotes.isNotEmpty) ...[
                  _SectionCard(
                    title: context.l10n.tr('Fitness & Health'),
                    icon: Icons.fitness_center_outlined,
                    children: [
                      if (member.fitnessLevel.isNotEmpty)
                        _DetailRow(
                          icon: Icons.military_tech_outlined,
                          label: 'Level',
                          value: member.fitnessLevel.toUpperCase(),
                          valueWidget:
                              _FitnessLevelBadge(level: member.fitnessLevel),
                        ),
                      if (member.healthNotes.isNotEmpty)
                        _DetailRow(
                          icon: Icons.medical_information_outlined,
                          label: 'Health notes',
                          value: member.healthNotes,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (member.emergencyContactName.isNotEmpty) ...[
                  _SectionCard(
                    title: context.l10n.tr('Emergency Contact'),
                    icon: Icons.contact_emergency_outlined,
                    children: [
                      _DetailRow(
                        icon: Icons.person_outline,
                        label: 'Name',
                        value: member.emergencyContactName,
                      ),
                      if (member.emergencyContactPhone.isNotEmpty)
                        _DetailRow(
                          icon: Icons.phone_in_talk_outlined,
                          label: 'Phone',
                          value: member.emergencyContactPhone,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                // Membership info card
                _SectionCard(
                  title: context.l10n.tr('Membership'),
                  icon: Icons.card_membership_outlined,
                  children: [
                    _DetailRow(
                      icon: Icons.circle_outlined,
                      label: 'Status',
                      value: '',
                      valueWidget:
                          _StatusBadge(status: member.subscriptionStatus),
                    ),
                    if (member.membershipPlanId.isNotEmpty)
                      _DetailRow(
                        icon: Icons.local_offer_outlined,
                        label: 'Plan ID',
                        value: member.membershipPlanId,
                      ),
                    _DetailRow(
                      icon: Icons.fingerprint_outlined,
                      label: 'User ID',
                      value: member.id.length > 10
                          ? '…${member.id.substring(member.id.length - 8)}'
                          : member.id,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _genderLabel(String g) {
    switch (g) {
      case 'male':
        return 'Male';
      case 'female':
        return 'Female';
      case 'prefer_not_to_say':
        return 'Prefer not to say';
      default:
        return g;
    }
  }
}

class _WebActivityTab extends StatefulWidget {
  const _WebActivityTab({required this.member});
  final AppUser member;

  @override
  State<_WebActivityTab> createState() => _WebActivityTabState();
}

class _WebActivityTabState extends State<_WebActivityTab> {
  late final _bookingService = BookingService(gymId: widget.member.gymId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: _bookingService.streamBookingsForUser(widget.member.id),
      builder: (context, snap) {
        final bookings = snap.data ?? <Booking>[];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: _SectionCard(
            title: '${context.l10n.tr('All Activity')} (${bookings.length})',
            icon: Icons.history_outlined,
            children: bookings.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.l10n.tr('No activity yet.'),
                          style: const TextStyle(color: Colors.grey)),
                    )
                  ]
                : bookings
                    .map((b) => _BookingActivityTile(booking: b))
                    .toList(),
          ),
        );
      },
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.member});

  final AppUser member;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _cinCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _emergencyNameCtrl;
  late final TextEditingController _emergencyPhoneCtrl;
  late final TextEditingController _healthNotesCtrl;
  late final TabController _tabCtrl;
  DateTime? _dob;
  late String _gender;
  late String _fitnessLevel;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _nameCtrl = TextEditingController(text: widget.member.displayName);
    _phoneCtrl = TextEditingController(text: widget.member.phoneNumber);
    _cinCtrl = TextEditingController(text: widget.member.cinNumber);
    _addressCtrl = TextEditingController(text: widget.member.address);
    _emergencyNameCtrl =
        TextEditingController(text: widget.member.emergencyContactName);
    _emergencyPhoneCtrl =
        TextEditingController(text: widget.member.emergencyContactPhone);
    _healthNotesCtrl = TextEditingController(text: widget.member.healthNotes);
    _dob = widget.member.dateOfBirth;
    _gender =
        ['male', 'female', 'prefer_not_to_say'].contains(widget.member.gender)
            ? widget.member.gender
            : 'prefer_not_to_say';
    _fitnessLevel =
        ['beginner', 'intermediate', 'rx'].contains(widget.member.fitnessLevel)
            ? widget.member.fitnessLevel
            : 'beginner';
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cinCtrl.dispose();
    _addressCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _healthNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await MemberService(gymId: widget.member.gymId).updateProfile(
        userId: widget.member.id,
        displayName: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        photoUrl: widget.member.photoUrl,
        gender: _gender,
        dateOfBirth: _dob,
        fitnessLevel: _fitnessLevel,
        emergencyContactName: _emergencyNameCtrl.text.trim(),
        emergencyContactPhone: _emergencyPhoneCtrl.text.trim(),
        healthNotes: _healthNotesCtrl.text.trim(),
        cinNumber: _cinCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = widget.member.displayName.isEmpty
        ? widget.member.email
        : widget.member.displayName;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 680),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withValues(alpha: 0.12),
                    cs.primary.withValues(alpha: 0.04),
                  ],
                ),
                border: Border(
                    bottom: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.4))),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.edit_outlined,
                            size: 18, color: cs.primary),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.tr('Edit Profile'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                          Text(displayName,
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Tab bar
                  TabBar(
                    controller: _tabCtrl,
                    tabs: [
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person_outline, size: 14),
                          SizedBox(width: 6),
                          Text(context.l10n.tr('Personal')),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.fitness_center_outlined, size: 14),
                          SizedBox(width: 6),
                          Text(context.l10n.tr('Fitness & Health')),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.contact_emergency_outlined, size: 14),
                          SizedBox(width: 6),
                          Text(context.l10n.tr('Emergency')),
                        ]),
                      ),
                    ],
                    labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorWeight: 2.5,
                    dividerColor: Colors.transparent,
                  ),
                ],
              ),
            ),

            // ── Tab content ──────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // Tab 0 — Personal
                  _EditTab(children: [
                    _EditRow(children: [
                      _EditField(
                        label: 'Display Name',
                        icon: Icons.person_outline,
                        controller: _nameCtrl,
                        hint: 'Full name',
                      ),
                      _EditField(
                        label: 'Phone Number',
                        icon: Icons.phone_outlined,
                        controller: _phoneCtrl,
                        hint: '+213 …',
                        inputType: TextInputType.phone,
                      ),
                    ]),
                    _EditRow(children: [
                      _EditField(
                        label: 'CIN / Passport Number',
                        icon: Icons.badge_outlined,
                        controller: _cinCtrl,
                        hint: 'e.g. 12345678',
                      ),
                      _EditField(
                        label: 'Address',
                        icon: Icons.location_on_outlined,
                        controller: _addressCtrl,
                        hint: 'Street, city…',
                        maxLines: 2,
                      ),
                    ]),
                    // Date of birth
                    _EditLabel(
                        label: 'Date of Birth', icon: Icons.cake_outlined),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dob ?? DateTime(1990),
                          firstDate: DateTime(1930),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => _dob = picked);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: 0.6)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.event_outlined,
                                size: 16, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text(
                              _dob != null
                                  ? DateFormat('d MMMM yyyy').format(_dob!)
                                  : 'Select date of birth',
                              style: TextStyle(
                                  color: _dob != null
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant,
                                  fontWeight: _dob != null
                                      ? FontWeight.w600
                                      : FontWeight.w400),
                            ),
                            const Spacer(),
                            if (_dob != null)
                              TextButton(
                                onPressed: () => setState(() => _dob = null),
                                style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap),
                                child: Text(context.l10n.tr('Clear')),
                              )
                            else
                              Icon(Icons.arrow_drop_down,
                                  color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Gender
                    _EditLabel(label: 'Gender', icon: Icons.wc_outlined),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
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
                            value: 'prefer_not_to_say',
                            label: Text(context.l10n.tr('Other'))),
                      ],
                      selected: {_gender},
                      onSelectionChanged: (v) =>
                          setState(() => _gender = v.first),
                    ),
                  ]),

                  // Tab 1 — Fitness & Health
                  _EditTab(children: [
                    _EditLabel(
                        label: 'Fitness Level',
                        icon: Icons.military_tech_outlined),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                            value: 'beginner',
                            label: Text(context.l10n.tr('Beginner')),
                            icon: Icon(Icons.directions_walk, size: 16)),
                        ButtonSegment(
                            value: 'intermediate',
                            label: Text(context.l10n.tr('Intermediate')),
                            icon: Icon(Icons.directions_run, size: 16)),
                        ButtonSegment(
                            value: 'rx',
                            label: Text(context.l10n.tr('RX')),
                            icon: Icon(Icons.bolt, size: 16)),
                      ],
                      selected: {_fitnessLevel},
                      onSelectionChanged: (v) =>
                          setState(() => _fitnessLevel = v.first),
                    ),
                    const SizedBox(height: 20),
                    _EditLabel(
                        label: 'Health Notes / Injuries',
                        icon: Icons.medical_information_outlined),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _healthNotesCtrl,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText:
                            'Describe any injuries, medical conditions or restrictions…',
                        filled: true,
                        fillColor: cs.surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.6)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.6)),
                        ),
                        alignLabelWithHint: true,
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ]),

                  // Tab 2 — Emergency Contact
                  _EditTab(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.red.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This person will be contacted in case of emergency during training.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _EditRow(children: [
                      _EditField(
                        label: 'Contact Full Name',
                        icon: Icons.contact_emergency_outlined,
                        controller: _emergencyNameCtrl,
                        hint: 'e.g. Jane Doe',
                      ),
                      _EditField(
                        label: 'Contact Phone',
                        icon: Icons.phone_in_talk_outlined,
                        controller: _emergencyPhoneCtrl,
                        hint: '+213 …',
                        inputType: TextInputType.phone,
                      ),
                    ]),
                  ]),
                ],
              ),
            ),

            // ── Footer ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                border: Border(
                    top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: Row(
                children: [
                  Text(
                    'All changes are saved immediately.',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.tr('Cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.onPrimary),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: Text(_saving ? 'Saving…' : 'Save changes'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
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

// ── Edit dialog helpers ───────────────────────────────────────────────────────

class _EditTab extends StatelessWidget {
  const _EditTab({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  const _EditRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spaced = children
        .expand((w) => [Expanded(child: w), const SizedBox(width: 16)])
        .toList();
    spaced.removeLast();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spaced,
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.label,
    required this.icon,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.inputType,
  });
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? inputType;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditLabel(label: label, icon: icon),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: inputType,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: cs.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _EditLabel extends StatelessWidget {
  const _EditLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 13, color: cs.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          context.l10n.tr(label),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ── Admin Note Section ───────────────────────────────────────────────────────

class _AdminNoteSection extends StatefulWidget {
  const _AdminNoteSection({required this.member});
  final AppUser member;

  @override
  State<_AdminNoteSection> createState() => _AdminNoteSectionState();
}

class _AdminNoteSectionState extends State<_AdminNoteSection> {
  bool _saving = false;

  Future<void> _openEditDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: widget.member.adminNote);
    final cs = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border:
                      Border(bottom: BorderSide(color: Colors.amber.shade200)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sticky_note_2_outlined,
                        color: Colors.amber.shade700, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Admin Remarque',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.amber.shade800),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Private note visible only to admins.',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText:
                            context.l10n.tr('Write a note about this member…'),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.amber.shade50.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: StatefulBuilder(
                  builder: (ctx2, setSt) => Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.member.adminNote.isNotEmpty)
                        TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  setSt(() => _saving = true);
                                  try {
                                    await MemberService(
                                            gymId: widget.member.gymId)
                                        .updateAdminNote(
                                      userId: widget.member.id,
                                      adminNote: '',
                                    );
                                  } finally {
                                    setSt(() => _saving = false);
                                  }
                                  if (ctx2.mounted) {
                                    Navigator.pop(ctx2);
                                  }
                                },
                          icon: const Icon(Icons.delete_outline,
                              size: 16, color: Colors.red),
                          label: Text(context.l10n.tr('Clear'),
                              style: TextStyle(color: Colors.red)),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(context.l10n.tr('Cancel')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                        ),
                        onPressed: _saving
                            ? null
                            : () async {
                                setSt(() => _saving = true);
                                try {
                                  await MemberService(
                                          gymId: widget.member.gymId)
                                      .updateAdminNote(
                                    userId: widget.member.id,
                                    adminNote: ctrl.text.trim(),
                                  );
                                } finally {
                                  setSt(() => _saving = false);
                                }
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                }
                              },
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined, size: 16),
                        label: Text(context.l10n.tr('Save Note')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasNote = widget.member.adminNote.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.sticky_note_2_outlined,
                    size: 17, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Text(
                  'Admin Remarque',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber.shade800,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openEditDialog(context),
                  icon: Icon(
                    hasNote ? Icons.edit_outlined : Icons.add,
                    size: 14,
                    color: Colors.amber.shade700,
                  ),
                  label: Text(
                    hasNote ? 'Edit' : 'Add note',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade700,
                        fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.amber.shade200),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: hasNote
                ? SelectableText(
                    widget.member.adminNote,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber.shade900,
                      height: 1.5,
                    ),
                  )
                : Text(
                    'No note yet. Tap "Add note" to add a private admin remark.',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.amber.shade700,
                        fontStyle: FontStyle.italic),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Member Invoices Tab ───────────────────────────────────────────────────────

class _MemberInvoicesTab extends StatelessWidget {
  const _MemberInvoicesTab({
    required this.member,
    required this.onGenerate,
  });

  final AppUser member;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final billing = BillingService(gymId: member.gymId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            border: Border(
                bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4))),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 18, color: const Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Text(
                context.l10n.tr('Invoices'),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.add, size: 16),
                label: Text(context.l10n.tr('Generate Invoice')),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),

        // ── Invoice list ─────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<Invoice>>(
            stream: billing.streamInvoicesForUser(member.id),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final invoices = snap.data ?? [];
              if (invoices.isEmpty) {
                return _InvoicesEmptyState(onGenerate: onGenerate);
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                itemCount: invoices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) =>
                    _MemberInvoiceCard(invoice: invoices[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InvoicesEmptyState extends StatelessWidget {
  const _InvoicesEmptyState({required this.onGenerate});
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 52,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Text(
            context.l10n.tr('No invoices yet'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.tr('Generate the first invoice for this member.'),
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.l10n.tr('Generate Invoice')),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E)),
          ),
        ],
      ),
    );
  }
}

class _MemberInvoiceCard extends StatelessWidget {
  const _MemberInvoiceCard({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('d MMM yyyy');
    final outstanding = invoice.totalAmount - invoice.amountPaid;

    Color statusColor;
    String statusLabel;
    switch (invoice.status) {
      case 'paid':
        statusColor = Colors.green.shade600;
        statusLabel = 'Paid';
      case 'partial':
        statusColor = Colors.orange.shade600;
        statusLabel = 'Partial';
      case 'cancelled':
        statusColor = Colors.red.shade600;
        statusLabel = 'Cancelled';
      default:
        statusColor = Colors.blue.shade600;
        statusLabel = 'Pending';
    }

    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => InvoiceDetailScreen(invoice: invoice),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_outlined,
                    size: 20, color: statusColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          invoice.invoiceNumber,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            context.l10n.tr(statusLabel),
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${invoice.items.isNotEmpty ? invoice.items.first.description : '—'}  •  ${dateFmt.format(invoice.issuedAt)}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${invoice.currency} ${invoice.totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  if (outstanding > 0)
                    Text(
                      '${context.l10n.tr('Due')}: ${invoice.currency} ${outstanding.toStringAsFixed(0)}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.orange.shade600),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 16, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
