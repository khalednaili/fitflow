import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/gym_class.dart';
import '../../../services/class_service.dart';
import '../../../services/member_service.dart';
import '../../../widgets/role_widgets.dart';
import '../member_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main tab widget
// ─────────────────────────────────────────────────────────────────────────────

class AdminCoachesTab extends StatefulWidget {
  const AdminCoachesTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminCoachesTab> createState() => _AdminCoachesTabState();
}

class _AdminCoachesTabState extends State<AdminCoachesTab> {
  late final _memberService = MemberService(gymId: widget.gymId);
  late final _classService = ClassService(gymId: widget.gymId);
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppUser> _filter(List<AppUser> coaches) {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return coaches;
    return coaches
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            c.email.toLowerCase().contains(q))
        .toList();
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _openProfile(AppUser coach) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemberDetailScreen(member: coach),
      ),
    );
  }

  void _openSchedule(AppUser coach, List<GymClass> upcomingClasses) {
    final coachClasses =
        upcomingClasses.where((c) => c.coachIds.contains(coach.id)).toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _CoachScheduleScreen(coach: coach, classes: coachClasses),
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _copyEmail(AppUser coach) async {
    await Clipboard.setData(ClipboardData(text: coach.email));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10n.tr('Copied')}: ${coach.email}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showChangeRoleDialog(AppUser coach) async {
    final selected = Set<String>.from(coach.effectiveRoles);
    const allRoles = ['member', 'coach', 'staff', 'admin'];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            '${context.l10n.tr('Roles')} — ${coach.displayName.isEmpty ? coach.email : coach.displayName}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: allRoles.map((r) {
              final def = kAllRoles.firstWhere((d) => d.id == r);
              return CheckboxListTile(
                value: selected.contains(r),
                title: Text(def.label),
                secondary: Icon(def.icon, color: def.color),
                onChanged: (v) {
                  setDialogState(() {
                    if (v == true) {
                      selected.add(r);
                    } else if (selected.length > 1) {
                      selected.remove(r);
                    }
                  });
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _memberService.updateRoles(
                  userId: coach.id,
                  roles: selected.toList(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.tr('Roles updated.'))),
                  );
                }
              },
              child: Text(context.l10n.tr('Save')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: StreamBuilder<List<AppUser>>(
          stream: _memberService.streamCoaches(),
          builder: (context, coachSnap) {
            return StreamBuilder<List<GymClass>>(
              stream: _classService.streamUpcomingClasses(),
              builder: (context, classSnap) {
                final coaches = coachSnap.data ?? <AppUser>[];
                final upcomingClasses = classSnap.data ?? <GymClass>[];
                final filtered = _filter(coaches);
                final isLoading =
                    coachSnap.connectionState == ConnectionState.waiting;

                return Column(
                  children: [
                    _CoachesHeader(
                      coaches: coaches,
                      searchController: _searchController,
                      searchQuery: _searchQuery,
                      onSearchChanged: (v) => setState(() => _searchQuery = v),
                      isWide: isWide,
                    ),
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : filtered.isEmpty
                              ? _EmptyState(hasSearch: _searchQuery.isNotEmpty)
                              : isWide
                                  ? _CoachesTable(
                                      coaches: filtered,
                                      upcomingClasses: upcomingClasses,
                                      onProfile: _openProfile,
                                      onSchedule: (c) =>
                                          _openSchedule(c, upcomingClasses),
                                      onCopyEmail: _copyEmail,
                                      onChangeRole: _showChangeRoleDialog,
                                    )
                                  : _CoachesList(
                                      coaches: filtered,
                                      upcomingClasses: upcomingClasses,
                                      onProfile: _openProfile,
                                      onSchedule: (c) =>
                                          _openSchedule(c, upcomingClasses),
                                      onCopyEmail: _copyEmail,
                                      onChangeRole: _showChangeRoleDialog,
                                    ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _CoachesHeader extends StatelessWidget {
  const _CoachesHeader({
    required this.coaches,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.isWide,
  });

  final List<AppUser> coaches;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final coachCount =
        coaches.where((c) => c.effectiveRoles.contains('coach')).length;
    final staffCount =
        coaches.where((c) => c.effectiveRoles.contains('staff')).length;
    final adminCount = coaches
        .where((c) =>
            c.effectiveRoles.contains('admin') ||
            c.effectiveRoles.contains('owner'))
        .length;

    return Container(
      color: cs.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _StatChip(
                        icon: Icons.sports_outlined,
                        label: '${coaches.length} ${context.l10n.tr('total')}',
                        color: const Color(0xFF0F766E),
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.sports_martial_arts_outlined,
                        label: '$coachCount ${context.l10n.tr('coaches')}',
                        color: const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.badge_outlined,
                        label: '$staffCount ${context.l10n.tr('staff')}',
                        color: const Color(0xFF7C3AED),
                      ),
                      if (adminCount > 0) ...[
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.admin_panel_settings_outlined,
                          label: '$adminCount ${context.l10n.tr('admin')}',
                          color: const Color(0xFFDC2626),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: context.l10n.tr('Search coaches by name or email…'),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mobile list
// ─────────────────────────────────────────────────────────────────────────────

class _CoachesList extends StatelessWidget {
  const _CoachesList({
    required this.coaches,
    required this.upcomingClasses,
    required this.onProfile,
    required this.onSchedule,
    required this.onCopyEmail,
    required this.onChangeRole,
  });

  final List<AppUser> coaches;
  final List<GymClass> upcomingClasses;
  final ValueChanged<AppUser> onProfile;
  final ValueChanged<AppUser> onSchedule;
  final ValueChanged<AppUser> onCopyEmail;
  final ValueChanged<AppUser> onChangeRole;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: coaches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _CoachCard(
        coach: coaches[i],
        upcomingCount: upcomingClasses
            .where((c) => c.coachIds.contains(coaches[i].id))
            .length,
        onProfile: onProfile,
        onSchedule: onSchedule,
        onCopyEmail: onCopyEmail,
        onChangeRole: onChangeRole,
      ),
    );
  }
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    required this.coach,
    required this.upcomingCount,
    required this.onProfile,
    required this.onSchedule,
    required this.onCopyEmail,
    required this.onChangeRole,
  });

  final AppUser coach;
  final int upcomingCount;
  final ValueChanged<AppUser> onProfile;
  final ValueChanged<AppUser> onSchedule;
  final ValueChanged<AppUser> onCopyEmail;
  final ValueChanged<AppUser> onChangeRole;

  String get _initials {
    final name = coach.displayName.trim();
    if (name.isEmpty) {
      return coach.email.isNotEmpty ? coach.email[0].toUpperCase() : '?';
    }
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  Color get _avatarColor => roleColor(coach.role);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = coach.displayName.isNotEmpty ? coach.displayName : coach.email;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onProfile(coach),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: _avatarColor.withValues(alpha: 0.15),
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: _avatarColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      coach.email,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: RoleBadgeRow(roles: coach.effectiveRoles),
                        ),
                        if (upcomingCount > 0) ...[
                          const SizedBox(width: 8),
                          _ClassCountBadge(count: upcomingCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Context menu
              PopupMenuButton<String>(
                icon:
                    Icon(Icons.more_vert, color: cs.onSurfaceVariant, size: 20),
                onSelected: (v) {
                  switch (v) {
                    case 'profile':
                      onProfile(coach);
                    case 'schedule':
                      onSchedule(coach);
                    case 'copy':
                      onCopyEmail(coach);
                    case 'roles':
                      onChangeRole(coach);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(children: [
                      Icon(Icons.person_outline, size: 16),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('View Profile')),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'schedule',
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('Upcoming Schedule')),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'copy',
                    child: Row(children: [
                      Icon(Icons.copy_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('Copy Email')),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'roles',
                    child: Row(children: [
                      Icon(Icons.manage_accounts_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('Change Roles')),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Web / wide table
// ─────────────────────────────────────────────────────────────────────────────

class _CoachesTable extends StatelessWidget {
  const _CoachesTable({
    required this.coaches,
    required this.upcomingClasses,
    required this.onProfile,
    required this.onSchedule,
    required this.onCopyEmail,
    required this.onChangeRole,
  });

  final List<AppUser> coaches;
  final List<GymClass> upcomingClasses;
  final ValueChanged<AppUser> onProfile;
  final ValueChanged<AppUser> onSchedule;
  final ValueChanged<AppUser> onCopyEmail;
  final ValueChanged<AppUser> onChangeRole;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: cs.surfaceContainerHighest,
              child: Row(
                children: [
                  const SizedBox(width: 44), // avatar space
                  const SizedBox(width: 12),
                  const Expanded(flex: 3, child: _ColHeader('Name')),
                  const Expanded(flex: 3, child: _ColHeader('Email')),
                  const Expanded(flex: 2, child: _ColHeader('Roles')),
                  const SizedBox(width: 110, child: _ColHeader('Upcoming')),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // Rows
            ...coaches.map((coach) {
              final classCount = upcomingClasses
                  .where((c) => c.coachIds.contains(coach.id))
                  .length;
              return _TableRow(
                coach: coach,
                upcomingCount: classCount,
                onProfile: onProfile,
                onSchedule: onSchedule,
                onCopyEmail: onCopyEmail,
                onChangeRole: onChangeRole,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.coach,
    required this.upcomingCount,
    required this.onProfile,
    required this.onSchedule,
    required this.onCopyEmail,
    required this.onChangeRole,
  });

  final AppUser coach;
  final int upcomingCount;
  final ValueChanged<AppUser> onProfile;
  final ValueChanged<AppUser> onSchedule;
  final ValueChanged<AppUser> onCopyEmail;
  final ValueChanged<AppUser> onChangeRole;

  String get _initials {
    final name = coach.displayName.trim();
    if (name.isEmpty) {
      return coach.email.isNotEmpty ? coach.email[0].toUpperCase() : '?';
    }
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = coach.displayName.isNotEmpty ? coach.displayName : coach.email;
    final color = roleColor(coach.role);

    return InkWell(
      onTap: () => onProfile(coach),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Text(
                _initials,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(
                name,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                coach.email,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: RoleBadgeRow(roles: coach.effectiveRoles),
            ),
            SizedBox(
              width: 110,
              child: upcomingCount > 0
                  ? _ClassCountBadge(count: upcomingCount)
                  : Text(
                      '—',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
            ),
            SizedBox(
              width: 48,
              child: PopupMenuButton<String>(
                icon:
                    Icon(Icons.more_vert, color: cs.onSurfaceVariant, size: 18),
                onSelected: (v) {
                  switch (v) {
                    case 'profile':
                      onProfile(coach);
                    case 'schedule':
                      onSchedule(coach);
                    case 'copy':
                      onCopyEmail(coach);
                    case 'roles':
                      onChangeRole(coach);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(children: [
                      Icon(Icons.person_outline, size: 16),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('View Profile')),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'schedule',
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('Upcoming Schedule')),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'copy',
                    child: Row(children: [
                      Icon(Icons.copy_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('Copy Email')),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'roles',
                    child: Row(children: [
                      Icon(Icons.manage_accounts_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(context.l10n.tr('Change Roles')),
                    ]),
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

// ─────────────────────────────────────────────────────────────────────────────
// Coach schedule screen
// ─────────────────────────────────────────────────────────────────────────────

class _CoachScheduleScreen extends StatelessWidget {
  const _CoachScheduleScreen({
    required this.coach,
    required this.classes,
  });

  final AppUser coach;
  final List<GymClass> classes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = coach.displayName.isNotEmpty ? coach.displayName : coach.email;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(context.l10n.tr('Upcoming schedule'),
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ),
      body: classes.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_busy_outlined,
                      size: 48, color: cs.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.tr('No upcoming classes assigned to $name.'),
                    style: TextStyle(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: classes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ScheduleClassCard(gymClass: classes[i]),
            ),
    );
  }
}

class _ScheduleClassCard extends StatelessWidget {
  const _ScheduleClassCard({required this.gymClass});
  final GymClass gymClass;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('EEE, MMM d · h:mm a');
    final classColor = gymClass.classColorValue != null
        ? Color(gymClass.classColorValue!)
        : const Color(0xFF0F766E);

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: classColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gymClass.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    fmt.format(gymClass.startTime),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${gymClass.bookedCount}/${gymClass.capacity}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  'booked',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _ClassCountBadge extends StatelessWidget {
  const _ClassCountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fitness_center_outlined,
              size: 11, color: Color(0xFF0F766E)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$count upcoming',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F766E)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch});
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch ? Icons.search_off_outlined : Icons.sports_outlined,
            size: 52,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            hasSearch
                ? context.l10n.tr('No coaches match your search.')
                : context.l10n.tr(
                    'No coaches found.\nAssign the coach or staff role to a member.',
                  ),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
