import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/gym.dart';
import '../../services/member_service.dart';
import 'gyms_list_screen.dart';
import 'unassigned_members_screen.dart';
import '../../l10n/app_localizations.dart';

class SuperAdminDashboardScreen extends StatelessWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('Dashboard')),
        actions: [
          IconButton(
            icon: Icon(Icons.sync),
            tooltip: context.l10n.tr('Migrate all data to gym'),
            onPressed: () => _showMigrationDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('gyms')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, gymSnap) {
          if (gymSnap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (gymSnap.hasError) {
            return Center(
              child: Text('${context.l10n.tr('Error')}: ${gymSnap.error}'),
            );
          }

          final gyms = gymSnap.data?.docs.map(Gym.fromSnapshot).toList() ?? [];
          final totalGyms = gyms.length;
          final activeGyms = gyms.where((g) => g.isActive).length;
          final suspendedGyms = gyms.where((g) => !g.isActive).length;

          return StreamBuilder<List<AppUser>>(
            stream: MemberService().streamUnassignedMembers(),
            builder: (context, memberSnap) {
              final unassigned = memberSnap.data ?? [];

              return SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.tr('Overview'),
                        style: Theme.of(context).textTheme.headlineSmall),
                    SizedBox(height: 24),
                    // ── Stat cards ──────────────────────────────────────────
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _StatCard(
                          icon: Icons.fitness_center,
                          label: context.l10n.tr('Total Gyms'),
                          value: '$totalGyms',
                          color: Colors.blue,
                        ),
                        _StatCard(
                          icon: Icons.check_circle_outline,
                          label: context.l10n.tr('Active'),
                          value: '$activeGyms',
                          color: Colors.green,
                        ),
                        _StatCard(
                          icon: Icons.pause_circle_outline,
                          label: context.l10n.tr('Suspended'),
                          value: '$suspendedGyms',
                          color: Colors.orange,
                        ),
                        _StatCard(
                          icon: Icons.person_off_outlined,
                          label: context.l10n.tr('Unassigned'),
                          value: '${unassigned.length}',
                          color: unassigned.isEmpty ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                    SizedBox(height: 40),

                    // ── Unassigned members ──────────────────────────────────
                    if (unassigned.isNotEmpty) ...[
                      _SectionHeader(
                        icon: Icons.person_off_outlined,
                        title: context.l10n.tr('Unassigned Members'),
                        badge: unassigned.length,
                        badgeColor: Colors.red,
                      ),
                      SizedBox(height: 12),
                      ...unassigned.map(
                        (member) => _DashboardUnassignedTile(member: member),
                      ),
                      SizedBox(height: 40),
                    ],

                    // ── Recent gyms ─────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.l10n.tr('Recent Gyms'),
                            style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                    SizedBox(height: 16),
                    if (gyms.isEmpty)
                      Text(context.l10n
                          .tr('No gyms yet. Create your first gym!'))
                    else
                      ...gyms.take(5).map(
                            (gym) => _RecentGymTile(
                              gym: gym,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => GymDetailScreen(gym: gym),
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showMigrationDialog(BuildContext context) async {
    final gymIdController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Migrate all data to gym')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.tr(
                'This will set gymId on ALL existing documents (classes, members, offers, WODs…) that have no gymId yet.',
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: gymIdController,
              decoration: InputDecoration(
                labelText: context.l10n.tr('Gym ID'),
                hintText: context.l10n.tr('e.g. F8WMn2jjEY89l5YgoiqZ'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.tr('Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Run Migration')),
          ),
        ],
      ),
    );

    if (confirmed != true || gymIdController.text.trim().isEmpty) return;
    if (!context.mounted) return;

    final gymId = gymIdController.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    try {
      messenger.showSnackBar(SnackBar(
        content:
            Text(context.l10n.tr('Running migration… this may take a minute')),
        duration: Duration(seconds: 60),
      ));
      final result = await FirebaseFunctions.instance
          .httpsCallable('migrateAllToGym')
          .call({'gymId': gymId});
      messenger.hideCurrentSnackBar();
      final summary = (result.data['summary'] as Map?)
          ?.entries
          .where((e) => (e.value as int) > 0)
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(context.l10n.tr('Migration complete ✅')),
            content: Text(summary?.isNotEmpty == true
                ? summary!
                : context.l10n.tr('Nothing needed updating.')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.tr('OK')))
            ],
          ),
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                '${context.l10n.tr('Migration failed')}: $e',
              ),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.badge,
    this.badgeColor,
  });

  final IconData icon;
  final String title;
  final int? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: badgeColor ?? cs.primary),
        SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (badge != null && badge! > 0) ...[
          SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (badgeColor ?? cs.primary).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: (badgeColor ?? cs.primary).withValues(alpha: 0.3)),
            ),
            child: Text(
              '$badge',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: badgeColor ?? cs.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Unassigned member tile (dashboard inline) ─────────────────────────────────

class _DashboardUnassignedTile extends StatelessWidget {
  const _DashboardUnassignedTile({required this.member});

  final AppUser member;

  String get _initials {
    final parts = member.displayName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return member.displayName.isNotEmpty
        ? member.displayName[0].toUpperCase()
        : member.email[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final joinDate = member.joinDate;

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: cs.primaryContainer,
              child: Text(
                _initials,
                style: TextStyle(
                    color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName.isNotEmpty
                        ? member.displayName
                        : member.email,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    member.email,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  if (joinDate != null)
                    Text(
                      '${context.l10n.tr('Registered')} ${DateFormat.yMMMd().format(joinDate)}',
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AssignGymDialog(member: member),
              ),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_business_outlined, size: 16),
                  SizedBox(width: 6),
                  Text(context.l10n.tr('Assign')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
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
    return Card(
      child: Container(
        width: 180,
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            SizedBox(height: 12),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ── Recent gym tile ───────────────────────────────────────────────────────────

class _RecentGymTile extends StatelessWidget {
  const _RecentGymTile({required this.gym, required this.onTap});

  final Gym gym;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Icon(Icons.fitness_center)),
        title: Text(gym.name),
        subtitle: Text(gym.adminEmail),
        trailing: _StatusChip(status: gym.status),
        onTap: onTap,
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Chip(
      label: Text(
        context.l10n.tr(isActive ? 'Active' : 'Suspended'),
        style: TextStyle(
          color: isActive ? Colors.green.shade800 : Colors.orange.shade800,
          fontSize: 12,
        ),
      ),
      backgroundColor: isActive ? Colors.green.shade50 : Colors.orange.shade50,
      side: BorderSide(
        color: isActive ? Colors.green.shade200 : Colors.orange.shade200,
      ),
    );
  }
}
