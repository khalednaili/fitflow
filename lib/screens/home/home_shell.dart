import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/member_service.dart';
import '../../services/notification_service.dart';
import '../admin/admin_dashboard_screen.dart';
import '../admin/admin_shell.dart';
import '../checkin/qr_scanner_screen.dart';
import '../coach/coach_portal_screen.dart';
import '../notifications/notifications_screen.dart';
import '../wod/wod_screen.dart';
import 'classes_screen.dart';
import 'dashboard_screen.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

// Nav item data model
class _NavItem {
  _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.color,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color? color;
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _memberService = MemberService();
  final _notificationService = NotificationService();
  String? _streamUserId;
  Stream<AppUser?>? _cachedUserStream;

  static const _primaryTeal = Color(0xFF0F766E);
  static const _accentOrange = Color(0xFFF97316);

  Stream<AppUser?> _userStreamFor(String userId) {
    if (_streamUserId != userId || _cachedUserStream == null) {
      _streamUserId = userId;
      _cachedUserStream = _memberService.streamUser(userId);
    }
    return _cachedUserStream!;
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NotificationsScreen()),
    );
  }

  List<Widget> _buildScreens(
      bool showAdminTab, bool showCoachTab, String gymId) {
    final showScanTab = !showAdminTab && !showCoachTab;
    final screens = <Widget>[
      DashboardScreen(
        gymId: gymId,
        onGoToClasses: () => setState(() => _index = 1),
      ),
      ClassesScreen(gymId: gymId),
      WodScreen(gymId: gymId),
      MyBookingsScreen(gymId: gymId),
      ProfileScreen(gymId: gymId),
    ];
    if (showScanTab) screens.add(QrScannerScreen(gymId: gymId));
    if (showCoachTab) screens.add(CoachPortalScreen());
    if (showAdminTab) screens.add(AdminDashboardScreen());
    return screens;
  }

  List<_NavItem> _buildNavItems(
    bool showAdminTab,
    bool showCoachTab,
    AppLocalizations l10n,
  ) {
    final showScanTab = !showAdminTab && !showCoachTab;
    final items = <_NavItem>[
      _NavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: l10n.tr('Home'),
        color: _primaryTeal,
      ),
      _NavItem(
        icon: Icons.fitness_center_outlined,
        activeIcon: Icons.fitness_center,
        label: l10n.tr('Classes'),
        color: _primaryTeal,
      ),
      _NavItem(
        icon: Icons.local_fire_department_outlined,
        activeIcon: Icons.local_fire_department,
        label: l10n.tr('WOD'),
        color: _accentOrange,
      ),
      _NavItem(
        icon: Icons.event_note_outlined,
        activeIcon: Icons.event_note,
        label: l10n.tr('Bookings'),
        color: _primaryTeal,
      ),
      _NavItem(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: l10n.tr('Profile'),
        color: _primaryTeal,
      ),
    ];
    if (showScanTab) {
      items.add(_NavItem(
        icon: Icons.qr_code_scanner_outlined,
        activeIcon: Icons.qr_code_scanner_rounded,
        label: l10n.tr('Scan'),
        color: _primaryTeal,
      ));
    }
    if (showCoachTab) {
      items.add(_NavItem(
        icon: Icons.sports_outlined,
        activeIcon: Icons.sports,
        label: l10n.tr('Coach'),
        color: Color(0xFF7C3AED),
      ));
    }
    if (showAdminTab) {
      items.add(_NavItem(
        icon: Icons.admin_panel_settings_outlined,
        activeIcon: Icons.admin_panel_settings,
        label: l10n.tr('Admin'),
        color: Color(0xFFDC2626),
      ));
    }
    return items;
  }

  bool _canAccessAdmin(AppUser? appUser) {
    if (appUser == null) return false;
    return appUser.isAdmin || appUser.isStaff;
  }

  bool _isCoach(AppUser? appUser) {
    if (appUser == null) return false;
    return appUser.isCoach;
  }

  Widget _buildNotificationBell(String userId) {
    return StreamBuilder<int>(
      stream: _notificationService.streamUnreadCount(userId),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return IconButton(
          tooltip: context.l10n.tr('Notifications'),
          onPressed: _openNotifications,
          icon: count > 0
              ? Badge(
                  label: Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(fontSize: 10),
                  ),
                  child: Icon(Icons.notifications_outlined),
                )
              : Icon(Icons.notifications_outlined),
        );
      },
    );
  }

  Widget _buildAppBar(String userId) {
    return AppBar(
      toolbarHeight: 52,
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _primaryTeal,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.fitness_center, color: Colors.white, size: 16),
          ),
          SizedBox(width: 8),
          Text(
            context.l10n.tr('FitFlow'),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ],
      ),
      actions: [_buildNotificationBell(userId)],
      elevation: 0,
      scrolledUnderElevation: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    if (currentUserId == null) {
      final screens = _buildScreens(false, false, '');
      final navItems = _buildNavItems(false, false, l10n);
      final selectedIndex = _index.clamp(0, screens.length - 1);
      return _buildScaffold(
        isWide: isWide,
        screens: screens,
        navItems: navItems,
        selectedIndex: selectedIndex,
        userId: null,
      );
    }

    return StreamBuilder<AppUser?>(
      stream: _userStreamFor(currentUserId),
      builder: (context, snapshot) {
        // Show loading indicator while waiting for user data
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final appUser = snapshot.data;
        final canAccessAdmin = _canAccessAdmin(appUser);

        // Admins get a completely separate admin-only shell
        if (canAccessAdmin) {
          return AdminShell(userId: currentUserId, appUser: appUser);
        }

        final showCoachTab = _isCoach(appUser);
        final screens =
            _buildScreens(false, showCoachTab, appUser?.gymId ?? '');
        final navItems = _buildNavItems(false, showCoachTab, l10n);
        final selectedIndex = _index.clamp(0, screens.length - 1);

        return _buildScaffold(
          isWide: isWide,
          screens: screens,
          navItems: navItems,
          selectedIndex: selectedIndex,
          userId: currentUserId,
        );
      },
    );
  }

  Widget _buildScaffold({
    required bool isWide,
    required List<Widget> screens,
    required List<_NavItem> navItems,
    required int selectedIndex,
    required String? userId,
  }) {
    void onTap(int i) {
      HapticFeedback.selectionClick();
      setState(() => _index = i);
    }

    if (isWide) {
      // ── Wide layout: NavigationRail on the left ────────────────────────
      return Scaffold(
        appBar:
            userId != null ? _buildAppBar(userId) as PreferredSizeWidget : null,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onTap,
              labelType: NavigationRailLabelType.all,
              backgroundColor: Theme.of(context).colorScheme.surface,
              indicatorColor: _primaryTeal.withValues(alpha: 0.12),
              selectedIconTheme: IconThemeData(color: _primaryTeal),
              selectedLabelTextStyle: TextStyle(
                color: _primaryTeal,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
              unselectedLabelTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
              destinations: navItems
                  .map((item) => NavigationRailDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.activeIcon,
                            color: item.color ?? _primaryTeal),
                        label: Text(item.label),
                      ))
                  .toList(),
            ),
            VerticalDivider(width: 1),
            Expanded(child: screens[selectedIndex]),
          ],
        ),
      );
    }

    // ── Mobile layout: custom floating bottom nav ──────────────────────
    return Scaffold(
      appBar:
          userId != null ? _buildAppBar(userId) as PreferredSizeWidget : null,
      body: screens[selectedIndex],
      bottomNavigationBar: _FloatingNavBar(
        items: navItems,
        selectedIndex: selectedIndex,
        onTap: onTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom floating bottom nav bar
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Color(0xFF1C1C1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 8,
            bottom: bottomPad > 0 ? 4 : 10,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final item = items[i];
              final isSelected = i == selectedIndex;
              final color = item.color ?? Color(0xFF0F766E);

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pill indicator + icon
                        AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          padding: EdgeInsets.symmetric(
                            horizontal: isSelected ? 16 : 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? color.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            isSelected ? item.activeIcon : item.icon,
                            size: 22,
                            color: isSelected
                                ? color
                                : cs.onSurfaceVariant.withValues(alpha: 0.65),
                          ),
                        ),
                        SizedBox(height: 2),
                        // Label
                        AnimatedDefaultTextStyle(
                          duration: Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w400,
                            color: isSelected
                                ? color
                                : cs.onSurfaceVariant.withValues(alpha: 0.65),
                            letterSpacing: isSelected ? 0.3 : 0,
                          ),
                          child: Text(item.label, maxLines: 1),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
