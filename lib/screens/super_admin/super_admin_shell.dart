import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../services/member_service.dart';
import 'super_admin_dashboard_screen.dart';
import 'gyms_list_screen.dart';
import 'super_admins_list_screen.dart';
import 'unassigned_members_screen.dart';
import '../../l10n/app_localizations.dart';

enum _SuperAdminTab { dashboard, gyms, unassignedMembers, superAdmins }

class SuperAdminShell extends StatefulWidget {
  const SuperAdminShell({super.key});

  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  _SuperAdminTab _selected = _SuperAdminTab.dashboard;

  List<_NavItem> _navItems(BuildContext context) => [
        _NavItem(
          tab: _SuperAdminTab.dashboard,
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          label: context.l10n.tr('Dashboard'),
        ),
        _NavItem(
          tab: _SuperAdminTab.gyms,
          icon: Icons.fitness_center_outlined,
          activeIcon: Icons.fitness_center,
          label: context.l10n.tr('Gyms'),
        ),
        _NavItem(
          tab: _SuperAdminTab.unassignedMembers,
          icon: Icons.person_off_outlined,
          activeIcon: Icons.person_off,
          label: context.l10n.tr('Unassigned'),
        ),
        _NavItem(
          tab: _SuperAdminTab.superAdmins,
          icon: Icons.admin_panel_settings_outlined,
          activeIcon: Icons.admin_panel_settings,
          label: context.l10n.tr('Super Admins'),
        ),
      ];

  Widget get _body {
    switch (_selected) {
      case _SuperAdminTab.dashboard:
        return const SuperAdminDashboardScreen();
      case _SuperAdminTab.gyms:
        return const GymsListScreen();
      case _SuperAdminTab.unassignedMembers:
        return const UnassignedMembersScreen();
      case _SuperAdminTab.superAdmins:
        return const SuperAdminsListScreen();
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.tr('Sign out')),
        content: Text(context.l10n.tr('Are you sure you want to sign out?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.tr('Sign out')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 900;
    final navItems = _navItems(context);
    return Scaffold(
      body: StreamBuilder<List<AppUser>>(
        stream: MemberService().streamUnassignedMembers(),
        builder: (context, unassignedSnap) {
          final unassignedCount = unassignedSnap.data?.length ?? 0;
          return Row(
            children: [
              NavigationRail(
                extended: wide,
                selectedIndex: _selected.index,
                onDestinationSelected: (i) =>
                    setState(() => _selected = _SuperAdminTab.values[i]),
                leading: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(Icons.bolt,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary),
                      SizedBox(height: 4),
                      if (wide)
                        Text(
                          context.l10n.tr('FitFlow'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: IconButton(
                        icon: Icon(Icons.logout),
                        tooltip: context.l10n.tr('Sign out'),
                        onPressed: () => _signOut(context),
                      ),
                    ),
                  ),
                ),
                destinations: navItems.map((item) {
                  final isUnassigned =
                      item.tab == _SuperAdminTab.unassignedMembers;
                  final showBadge = isUnassigned && unassignedCount > 0;
                  return NavigationRailDestination(
                    icon: showBadge
                        ? Badge(
                            label: Text(
                              unassignedCount > 99 ? '99+' : '$unassignedCount',
                              style: TextStyle(fontSize: 10),
                            ),
                            child: Icon(item.icon),
                          )
                        : Icon(item.icon),
                    selectedIcon: Icon(item.activeIcon),
                    label: Text(item.label),
                  );
                }).toList(),
              ),
              VerticalDivider(thickness: 1, width: 1),
              Expanded(child: _body),
            ],
          );
        },
      ),
    );
  }
}

class _NavItem {
  _NavItem({
    required this.tab,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final _SuperAdminTab tab;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
