import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import 'package:fit_flow/utils/currency.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/user_subscription.dart';
import '../../services/member_service.dart';
import '../../services/subscription_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/user_avatar.dart';
import 'membership_screen.dart';
import 'my_offers_screen.dart';
import 'friends_screen.dart';

// ── Brand colours (mirror home_shell.dart) ────────────────────────────────
const _kTeal = Color(0xFF0F766E);
const _kOrange = Color(0xFFF97316);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.gymId = ''});

  final String gymId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _memberService = MemberService(gymId: widget.gymId);
  late final _subscriptionService = SubscriptionService(gymId: widget.gymId);
  late TextEditingController _displayNameController;
  late TextEditingController _phoneController;
  late TextEditingController _photoUrlController;
  late TextEditingController _emergencyNameController;
  late TextEditingController _emergencyPhoneController;
  late TextEditingController _healthNotesController;
  String _gender = '';
  String _fitnessLevel = '';
  DateTime? _dateOfBirth;
  bool _isSaving = false;

  late final Stream<AppUser?> _userStream;
  late final Stream<UserSubscription?> _subscriptionStream;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _phoneController = TextEditingController();
    _photoUrlController = TextEditingController();
    _emergencyNameController = TextEditingController();
    _emergencyPhoneController = TextEditingController();
    _healthNotesController = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    _userStream =
        user != null ? _memberService.streamUser(user.uid) : Stream.empty();
    _subscriptionStream = user != null
        ? _subscriptionService.streamUserSubscription(user.uid)
        : Stream.empty();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _photoUrlController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _healthNotesController.dispose();
    super.dispose();
  }

  void _showEditProfileDialog(BuildContext context, AppUser? appUser) {
    _displayNameController.text = appUser?.displayName ?? '';
    _phoneController.text = appUser?.phoneNumber ?? '';
    _photoUrlController.text = appUser?.photoUrl ?? '';
    _emergencyNameController.text = appUser?.emergencyContactName ?? '';
    _emergencyPhoneController.text = appUser?.emergencyContactPhone ?? '';
    _healthNotesController.text = appUser?.healthNotes ?? '';
    _gender = appUser?.gender ?? '';
    _fitnessLevel = appUser?.fitnessLevel ?? '';
    _dateOfBirth = appUser?.dateOfBirth;
    _isSaving = false;

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext stateContext, StateSetter setState) {
          Future<void> pickDate() async {
            final picked = await showDatePicker(
              context: stateContext,
              initialDate: _dateOfBirth ??
                  DateTime.now().subtract(Duration(days: 365 * 25)),
              firstDate: DateTime(1940),
              lastDate: DateTime.now().subtract(Duration(days: 365 * 14)),
            );
            if (picked != null) {
              setState(() => _dateOfBirth = picked);
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit_outlined),
                SizedBox(width: 12),
                Text(context.l10n.tr('Edit Profile')),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Personal Info ──────────────────────────────
                    _SectionHeader(label: context.l10n.tr('Personal Info')),
                    SizedBox(height: 12),
                    TextField(
                      controller: _displayNameController,
                      enabled: !_isSaving,
                      maxLength: 50,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Full name'),
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        counterText: '${_displayNameController.text.length}/50',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      enabled: !_isSaving,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Phone number'),
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    SizedBox(height: 12),
                    // Date of birth picker
                    InkWell(
                      onTap: _isSaving ? null : pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: context.l10n.tr('Date of birth'),
                          prefixIcon: Icon(Icons.cake_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(
                          _dateOfBirth != null
                              ? DateFormat('dd / MM / yyyy')
                                  .format(_dateOfBirth!)
                              : context.l10n.tr('Select date'),
                          style: TextStyle(
                            color:
                                _dateOfBirth != null ? null : Colors.grey[500],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    // Gender
                    DropdownButtonFormField<String>(
                      value: _gender.isEmpty ? null : _gender,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Gender'),
                        prefixIcon: Icon(Icons.wc_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        DropdownMenuItem(
                            value: 'male',
                            child: Text(context.l10n.tr('Male'))),
                        DropdownMenuItem(
                            value: 'female',
                            child: Text(context.l10n.tr('Female'))),
                        DropdownMenuItem(
                            value: 'prefer_not_to_say',
                            child: Text(context.l10n.tr('Prefer not to say'))),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (v) => setState(() => _gender = v ?? ''),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _photoUrlController,
                      enabled: !_isSaving,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Profile photo URL'),
                        prefixIcon: Icon(Icons.image_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        hintText: context.l10n.tr('https://...'),
                      ),
                    ),
                    SizedBox(height: 20),

                    // ── Fitness Profile ────────────────────────────
                    _SectionHeader(label: context.l10n.tr('Fitness Profile')),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _fitnessLevel.isEmpty ? null : _fitnessLevel,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Fitness level'),
                        prefixIcon: Icon(Icons.fitness_center_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        DropdownMenuItem(
                            value: 'beginner',
                            child: Text(context.l10n.tr('Beginner'))),
                        DropdownMenuItem(
                            value: 'intermediate',
                            child: Text(context.l10n.tr('Intermediate'))),
                        DropdownMenuItem(
                            value: 'rx', child: Text(context.l10n.tr('RX'))),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (v) => setState(() => _fitnessLevel = v ?? ''),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _healthNotesController,
                      enabled: !_isSaving,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Health notes / injuries'),
                        prefixIcon: Icon(Icons.medical_information_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        hintText: context.l10n.tr(
                            'Any injuries or conditions coaches should know'),
                      ),
                    ),
                    SizedBox(height: 20),

                    // ── Emergency Contact ──────────────────────────
                    _SectionHeader(label: context.l10n.tr('Emergency Contact')),
                    SizedBox(height: 12),
                    TextField(
                      controller: _emergencyNameController,
                      enabled: !_isSaving,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Contact name'),
                        prefixIcon: Icon(Icons.contact_emergency_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _emergencyPhoneController,
                      enabled: !_isSaving,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Contact phone'),
                        prefixIcon: Icon(Icons.phone_in_talk_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    SizedBox(height: 8),
                    // Email lock notice
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline,
                              color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.l10n.tr('Email cannot be changed'),
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    _isSaving ? null : () => Navigator.pop(dialogContext),
                child: Text(context.l10n.tr('Cancel')),
              ),
              FilledButton(
                onPressed: _isSaving ||
                        _displayNameController.text.trim().isEmpty
                    ? null
                    : () async {
                        setState(() => _isSaving = true);
                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            await MemberService(gymId: widget.gymId)
                                .updateProfile(
                              userId: user.uid,
                              displayName: _displayNameController.text.trim(),
                              phoneNumber: _phoneController.text.trim(),
                              photoUrl: _photoUrlController.text.trim(),
                              gender: _gender,
                              dateOfBirth: _dateOfBirth,
                              fitnessLevel: _fitnessLevel,
                              emergencyContactName:
                                  _emergencyNameController.text.trim(),
                              emergencyContactPhone:
                                  _emergencyPhoneController.text.trim(),
                              healthNotes: _healthNotesController.text.trim(),
                              cinNumber: '',
                              address: '',
                            );
                            if (stateContext.mounted) {
                              Navigator.pop(stateContext);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        Icon(Icons.check_circle,
                                            color: Colors.white),
                                        SizedBox(width: 8),
                                        Text(
                                            context.l10n.tr('Profile updated')),
                                      ],
                                    ),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          }
                        } catch (e, s) {
                          await CrashLogger.log(e, s, reason: 'updateProfile');
                          if (stateContext.mounted) {
                            ScaffoldMessenger.of(stateContext).showSnackBar(
                              SnackBar(
                                content:
                                    Text('${context.l10n.tr('Error')}: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } finally {
                          setState(() => _isSaving = false);
                        }
                      },
                child: _isSaving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.l10n.tr('Save')),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = FirebaseAuth.instance.currentUser;
    final authService = AuthService();

    if (user == null) {
      return Scaffold(
        body: Center(child: Text(l10n.tr('Please sign in.'))),
      );
    }

    return Scaffold(
      body: StreamBuilder<AppUser?>(
        stream: _userStream,
        builder: (context, userSnapshot) {
          final appUser = userSnapshot.data;

          return StreamBuilder<UserSubscription?>(
            stream: _subscriptionStream,
            builder: (context, subSnapshot) {
              final subscription = subSnapshot.data;

              return CustomScrollView(
                slivers: [
                  // ── Hero header ──────────────────────────────────
                  _ProfileHeroHeader(
                    appUser: appUser,
                    user: user,
                    l10n: l10n,
                    onEdit: () => _showEditProfileDialog(context, appUser),
                  ),

                  SliverToBoxAdapter(
                    child: Builder(
                      builder: (context) {
                        final isWide = MediaQuery.sizeOf(context).width >= 700;
                        return Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: isWide ? 760 : double.infinity),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                  16, 0, 16, isWide ? 24 : 80),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Quick stats ────────────────────────────
                                  _QuickStatsRow(
                                    appUser: appUser,
                                    subscription: subscription,
                                    l10n: l10n,
                                  ),
                                  SizedBox(height: 20),

                                  // ── Personal info card ─────────────────────
                                  _InfoCard(
                                    title: l10n.tr('Personal Info'),
                                    icon: Icons.person_outline_rounded,
                                    iconColor: _kTeal,
                                    children: [
                                      _InfoTile(
                                        icon: Icons.email_outlined,
                                        label: l10n.tr('Email'),
                                        value: user.email ?? '',
                                      ),
                                      if ((appUser?.phoneNumber ?? '')
                                          .isNotEmpty)
                                        _InfoTile(
                                          icon: Icons.phone_outlined,
                                          label: l10n.tr('Phone'),
                                          value: appUser!.phoneNumber,
                                        ),
                                      if (appUser?.dateOfBirth != null)
                                        _InfoTile(
                                          icon: Icons.cake_outlined,
                                          label: l10n.tr('Date of birth'),
                                          value:
                                              '${DateFormat('dd / MM / yyyy').format(appUser!.dateOfBirth!)}'
                                              '${appUser.age != null ? '  ·  ${appUser.age} ${l10n.tr('years old')}' : ''}',
                                        ),
                                      if ((appUser?.gender ?? '').isNotEmpty)
                                        _InfoTile(
                                          icon: Icons.wc_outlined,
                                          label: l10n.tr('Gender'),
                                          value: _genderLabel(
                                              appUser!.gender, l10n),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: 12),

                                  // ── Health & safety card ───────────────────
                                  if ((appUser?.emergencyContactName ?? '')
                                          .isNotEmpty ||
                                      (appUser?.healthNotes ?? '')
                                          .isNotEmpty) ...[
                                    _InfoCard(
                                      title: l10n.tr('Health & Safety'),
                                      icon: Icons.health_and_safety_outlined,
                                      iconColor: Colors.red.shade400,
                                      children: [
                                        if ((appUser?.emergencyContactName ??
                                                '')
                                            .isNotEmpty)
                                          _InfoTile(
                                            icon: Icons
                                                .contact_emergency_outlined,
                                            label: l10n.tr('Emergency contact'),
                                            value:
                                                '${appUser!.emergencyContactName}'
                                                '${appUser.emergencyContactPhone.isNotEmpty ? '  ·  ${appUser.emergencyContactPhone}' : ''}',
                                          ),
                                        if ((appUser?.healthNotes ?? '')
                                            .isNotEmpty)
                                          _InfoTile(
                                            icon: Icons
                                                .medical_information_outlined,
                                            label: l10n
                                                .tr('Health notes / injuries'),
                                            value: appUser!.healthNotes,
                                          ),
                                      ],
                                    ),
                                    SizedBox(height: 12),
                                  ],

                                  // ── Payment card ───────────────────────────
                                  if (subscription != null) ...[
                                    _PaymentCard(
                                      subscription: subscription,
                                      l10n: l10n,
                                    ),
                                    SizedBox(height: 12),
                                  ],

                                  // ── Navigation cards ───────────────────────
                                  Builder(builder: (context) {
                                    final isWide =
                                        MediaQuery.sizeOf(context).width >= 700;
                                    final offersCard = _NavCard(
                                      icon: Icons.local_offer_outlined,
                                      iconColor: _kOrange,
                                      label: l10n.tr('My Offers'),
                                      subtitle:
                                          l10n.tr('View your active offers'),
                                      onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                              builder: (_) => MyOffersScreen(
                                                  gymId: widget.gymId))),
                                    );
                                    final membershipCard = _NavCard(
                                      icon: Icons.card_membership_outlined,
                                      iconColor: _kTeal,
                                      label: l10n.tr('Manage Membership'),
                                      subtitle:
                                          l10n.tr('Plans, renewals & billing'),
                                      onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                              builder: (_) => MembershipScreen(
                                                  gymId: widget.gymId))),
                                    );
                                    final friendsCard = _NavCard(
                                      icon: Icons.group_outlined,
                                      iconColor: Color(0xFF7C3AED),
                                      label: l10n.tr('Friends'),
                                      subtitle: l10n.tr('Find & connect with gym members'),
                                      onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                              builder: (_) => FriendsScreen(
                                                  gymId: widget.gymId))),
                                    );
                                    if (isWide) {
                                      return Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(child: offersCard),
                                              SizedBox(width: 10),
                                              Expanded(child: membershipCard),
                                            ],
                                          ),
                                          SizedBox(height: 10),
                                          friendsCard,
                                        ],
                                      );
                                    }
                                    return Column(
                                      children: [
                                        offersCard,
                                        SizedBox(height: 10),
                                        membershipCard,
                                        SizedBox(height: 10),
                                        friendsCard,
                                      ],
                                    );
                                  }),
                                  SizedBox(height: 20),

                                  // ── Sign out ───────────────────────────────
                                  _SignOutButton(
                                    label: l10n.tr('Sign out'),
                                    onTap: () async => authService.signOut(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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

  String _genderLabel(String gender, AppLocalizations l10n) {
    switch (gender) {
      case 'male':
        return l10n.tr('Male');
      case 'female':
        return l10n.tr('Female');
      case 'prefer_not_to_say':
        return l10n.tr('Prefer not to say');
      default:
        return gender;
    }
  }
}

// ── Hero header ────────────────────────────────────────────────────────────

class _ProfileHeroHeader extends StatelessWidget {
  const _ProfileHeroHeader({
    required this.appUser,
    required this.user,
    required this.l10n,
    required this.onEdit,
  });

  final AppUser? appUser;
  final User user;
  final AppLocalizations l10n;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final photoUrl = appUser?.photoUrl ?? '';
    final name = user.displayName ?? l10n.tr('Member');
    final role = appUser?.role ?? 'member';
    final level = appUser?.fitnessLevel ?? '';
    final topPad = MediaQuery.paddingOf(context).top;

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(
              top: topPad > 0 ? 8 : 20,
              left: 20,
              right: 20,
              bottom: 28,
            ),
            child: Column(
              children: [
                // ── Top row: title + edit button ────────────────
                Row(
                  children: [
                    Text(
                      l10n.tr('Profile'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Spacer(),
                    _EditButton(onTap: onEdit, label: l10n.tr('Edit Profile')),
                  ],
                ),
                SizedBox(height: 24),

                // ── Avatar + info ────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _HeroAvatar(photoUrl: photoUrl, user: user),
                    SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(height: 6),
                          Row(
                            children: [
                              _RoleBadge(role: role),
                              if (level.isNotEmpty) ...[
                                SizedBox(width: 6),
                                _FitnessLevelBadge(level: level),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.photoUrl, required this.user});

  final String photoUrl;
  final User user;

  @override
  Widget build(BuildContext context) {
    final initials = ((user.displayName ?? user.email ?? 'U')[0]).toUpperCase();
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final radius = isWide ? 56.0 : 40.0;

    return Container(
      padding: EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: UserAvatar(
        photoUrl: photoUrl,
        initials: initials,
        color: Colors.white,
        radius: radius,
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onTap, required this.label});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Quick stats row ────────────────────────────────────────────────────────

class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({
    required this.appUser,
    required this.subscription,
    required this.l10n,
  });

  final AppUser? appUser;
  final UserSubscription? subscription;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final status = appUser?.subscriptionStatus ?? 'none';
    final joinDate = appUser?.joinDate;
    final level = appUser?.fitnessLevel ?? '';

    final Color statusColor = switch (status) {
      'active' => Color(0xFF16A34A),
      'expired' => Color(0xFFDC2626),
      _ => Color(0xFF9CA3AF),
    };

    return Transform.translate(
      offset: Offset(0, -16),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _StatChip(
              icon: Icons.verified_outlined,
              label: l10n.tr('Status'),
              value: status.isNotEmpty ? status : 'none',
              valueColor: statusColor,
            ),
            _StatDivider(),
            _StatChip(
              icon: Icons.calendar_today_outlined,
              label: l10n.tr('Member since'),
              value: joinDate != null
                  ? DateFormat('MMM yyyy').format(joinDate)
                  : '—',
            ),
            if (level.isNotEmpty) ...[
              _StatDivider(),
              _StatChip(
                icon: Icons.fitness_center_outlined,
                label: l10n.tr('Level'),
                value: level.toUpperCase(),
                valueColor: _levelColor(level),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _levelColor(String level) => switch (level) {
        'rx' => Color(0xFFDC2626),
        'intermediate' => Color(0xFFF97316),
        _ => Color(0xFF16A34A),
      };
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: cs.primary.withValues(alpha: 0.8)),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor ?? cs.onSurface,
            ),
          ),
          SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
      margin: EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ── Info card ──────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
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
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: cs.outline.withValues(alpha: 0.2),
          ),
          // Fields
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(
                        height: 1,
                        color: cs.outline.withValues(alpha: 0.15),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.primary.withValues(alpha: 0.7)),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(height: 3),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Payment card ───────────────────────────────────────────────────────────

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.subscription, required this.l10n});

  final UserSubscription subscription;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = subscription.totalAmount > 0
        ? subscription.amountPaid / subscription.totalAmount
        : 0.0;
    final hasRemaining = subscription.remainingAmount > 0;

    return _InfoCard(
      title: l10n.tr('Payment Information'),
      icon: Icons.receipt_long_outlined,
      iconColor: Color(0xFF7C3AED),
      children: [
        _PaymentRow(
          label: l10n.tr('Total Price'),
          value: Currency.format(subscription.totalAmount, subscription.currency),
          valueStyle: TextStyle(fontWeight: FontWeight.w700),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: cs.outline.withValues(alpha: 0.15)),
        ),
        _PaymentRow(
          label: l10n.tr('Amount Paid'),
          value: Currency.format(subscription.amountPaid, subscription.currency),
          valueStyle: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF16A34A),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: cs.outline.withValues(alpha: 0.15)),
        ),
        _PaymentRow(
          label: l10n.tr('Remaining Amount'),
          value:
              Currency.format(subscription.remainingAmount, subscription.currency),
          valueStyle: TextStyle(
            fontWeight: FontWeight.w700,
            color: hasRemaining ? Color(0xFFF97316) : Color(0xFF16A34A),
          ),
        ),
        SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: cs.outline.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              hasRemaining ? Color(0xFFF97316) : Color(0xFF16A34A),
            ),
          ),
        ),
        SizedBox(height: 6),
        Text(
          '${(pct * 100).toStringAsFixed(1)}% ${l10n.tr('Payment Progress')}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.value,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: valueStyle),
      ],
    );
  }
}

// ── Navigation cards ───────────────────────────────────────────────────────

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sign-out button ────────────────────────────────────────────────────────

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFDC2626);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: red.withValues(alpha: 0.6), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: red, size: 18),
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: red,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
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
        color = Colors.red;
      case 'intermediate':
        color = Colors.orange;
      default:
        color = Colors.green;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        level.toUpperCase(),
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
    );
  }
}
