import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/app_user.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import '../../services/member_service.dart';
import 'admin_calendar_screen.dart';
import 'tabs/admin_attendance_tab.dart';
import 'tabs/admin_checkin_tab.dart';
import 'tabs/admin_classes_tab.dart';
import 'tabs/admin_dropins_tab.dart';
import 'tabs/admin_members_tab.dart';
import 'tabs/admin_offers_tab.dart';
import 'tabs/admin_templates_tab.dart';
import 'tabs/admin_personal_training_tab.dart';
import 'tabs/admin_coaches_tab.dart';
import 'tabs/admin_wod_calendar_tab.dart';
import 'tabs/admin_wod_tab.dart';
import 'tabs/admin_billing_tab.dart';
import 'tabs/admin_finance_tab.dart';
import 'tabs/admin_announcements_tab.dart';
import '../../l10n/app_localizations.dart';

// Tab definition
class _AdminTab {
  const _AdminTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.color,
  });
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color color;
}

// ⚠️  DUAL-FILE NAV: When adding a new tab here, you MUST also update
//    admin_shell.dart (_adminSections + _buildContent) for the web sidebar,
//    otherwise the new tab will be invisible on Chrome/web.
const _tabs = <_AdminTab>[
  _AdminTab(
    label: 'Calendar',
    icon: Icons.calendar_month_outlined,
    activeIcon: Icons.calendar_month,
    color: Color(0xFF0F766E),
  ),
  _AdminTab(
    label: 'Classes',
    icon: Icons.fitness_center_outlined,
    activeIcon: Icons.fitness_center,
    color: Color(0xFF0F766E),
  ),
  _AdminTab(
    label: 'Templates',
    icon: Icons.repeat_outlined,
    activeIcon: Icons.repeat,
    color: Color(0xFF7C3AED),
  ),
  _AdminTab(
    label: 'Workouts',
    icon: Icons.local_fire_department_outlined,
    activeIcon: Icons.local_fire_department,
    color: Color(0xFFF97316),
  ),
  _AdminTab(
    label: 'WOD Calendar',
    icon: Icons.calendar_today_outlined,
    activeIcon: Icons.calendar_today,
    color: Color(0xFFF97316),
  ),
  _AdminTab(
    label: 'Members',
    icon: Icons.group_outlined,
    activeIcon: Icons.group,
    color: Color(0xFF0369A1),
  ),
  _AdminTab(
    label: 'Offers',
    icon: Icons.card_membership_outlined,
    activeIcon: Icons.card_membership,
    color: Color(0xFF059669),
  ),
  _AdminTab(
    label: 'Attendance',
    icon: Icons.fact_check_outlined,
    activeIcon: Icons.fact_check,
    color: Color(0xFFDC2626),
  ),
  _AdminTab(
    label: 'Check-in QR',
    icon: Icons.qr_code_2_rounded,
    activeIcon: Icons.qr_code_2_rounded,
    color: Color(0xFF0D7377),
  ),
  _AdminTab(
    label: 'Drop-ins',
    icon: Icons.directions_walk_outlined,
    activeIcon: Icons.directions_walk,
    color: Color(0xFFEA580C),
  ),
  _AdminTab(
    label: 'Private PT',
    icon: Icons.person_outlined,
    activeIcon: Icons.person,
    color: Color(0xFF7C3AED),
  ),
  _AdminTab(
    label: 'Coaches',
    icon: Icons.sports_outlined,
    activeIcon: Icons.sports,
    color: Color(0xFF2563EB),
  ),
  _AdminTab(
    label: 'Billing',
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long,
    color: Color(0xFF059669),
  ),
  _AdminTab(
    label: 'Finance',
    icon: Icons.bar_chart_rounded,
    activeIcon: Icons.bar_chart_rounded,
    color: Color(0xFF0F766E),
  ),
  _AdminTab(
    label: 'Announcements',
    icon: Icons.campaign_outlined,
    activeIcon: Icons.campaign_rounded,
    color: Color(0xFF7C3AED),
  ),
];

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _memberService = MemberService();
  int _currentTab = 0;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    // Always sync immediately so sidebar highlight is instant
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() => setState(() => _currentTab = _tabController.index));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Widget> _buildTabChildren(String gymId, String? uid) => [
        _WithAdminBanner(
            gymId: gymId,
            userId: uid,
            child: AdminCalendarScreen(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminClassesTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminTemplatesTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminWodTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId,
            userId: uid,
            child: AdminWodCalendarTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminMembersTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminOffersTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminAttendanceTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminCheckinTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminDropInsTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId,
            userId: uid,
            child: AdminPersonalTrainingTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminCoachesTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminBillingTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId, userId: uid, child: AdminFinanceTab(gymId: gymId)),
        _WithAdminBanner(
            gymId: gymId,
            userId: uid,
            child: AdminAnnouncementsTab(gymId: gymId)),
      ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // ── Wide (≥1024 px): sidebar layout ──────────────────────────
          if (constraints.maxWidth >= 1024) {
            return Row(
              children: [
                _AdminSidebar(
                  currentIndex: _currentTab,
                  collapsed: _sidebarCollapsed,
                  onToggle: () =>
                      setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                  onSelect: (i) {
                    setState(() => _currentTab = i);
                    _tabController.animateTo(i,
                        duration: const Duration(milliseconds: 200));
                  },
                  uid: uid,
                  memberService: _memberService,
                ),
                Expanded(
                  child: StreamBuilder<AppUser?>(
                    stream: uid == null
                        ? Stream<AppUser?>.empty()
                        : _memberService.streamUser(uid),
                    builder: (context, userSnap) {
                      if (userSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final gymId = userSnap.data?.gymId ?? '';
                      if (gymId.isEmpty) {
                        return Center(
                            child: Text(context.l10n.tr('No gym assigned')));
                      }
                      return TabBarView(
                        controller: _tabController,
                        // Disable swipe on wide — sidebar is the navigation
                        physics: const NeverScrollableScrollPhysics(),
                        children: _buildTabChildren(gymId, uid),
                      );
                    },
                  ),
                ),
              ],
            );
          }

          // ── Narrow (<1024 px): top tab bar layout ────────────────────
          return NestedScrollView(
            headerSliverBuilder: (ctx, _) => [
              SliverAppBar(
                pinned: true,
                floating: false,
                automaticallyImplyLeading: false,
                backgroundColor: const Color(0xFF0F4C45),
                toolbarHeight: 0,
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: _AdminTabBar(
                    controller: _tabController,
                    currentIndex: _currentTab,
                  ),
                ),
              ),
            ],
            body: StreamBuilder<AppUser?>(
              stream: uid == null
                  ? Stream<AppUser?>.empty()
                  : _memberService.streamUser(uid),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final gymId = userSnap.data?.gymId ?? '';
                if (gymId.isEmpty) {
                  return Center(
                      child: Text(context.l10n.tr('No gym assigned')));
                }
                return TabBarView(
                  controller: _tabController,
                  children: _buildTabChildren(gymId, uid),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wrapper: puts the banner above each tab's content
// ─────────────────────────────────────────────────────────────────────────────

class _WithAdminBanner extends StatefulWidget {
  const _WithAdminBanner({
    required this.gymId,
    required this.userId,
    required this.child,
  });

  final String gymId;
  final String? userId;
  final Widget child;

  @override
  State<_WithAdminBanner> createState() => _WithAdminBannerState();
}

class _WithAdminBannerState extends State<_WithAdminBanner> {
  late final MemberService _memberSvc = MemberService(gymId: widget.gymId);
  late final ClassService _classSvc = ClassService(gymId: widget.gymId);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AdminBanner(
          memberService: _memberSvc,
          classService: _classSvc,
          userId: widget.userId,
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gradient banner: admin info + quick stats
// ─────────────────────────────────────────────────────────────────────────────

class _AdminBanner extends StatefulWidget {
  const _AdminBanner({
    required this.memberService,
    required this.classService,
    required this.userId,
  });

  final MemberService memberService;
  final ClassService classService;
  final String? userId;

  @override
  State<_AdminBanner> createState() => _AdminBannerState();
}

class _AdminBannerState extends State<_AdminBanner> {
  late final MemberService _memberService = widget.memberService;
  late final ClassService _classService = widget.classService;

  static String _todayLabel() {
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0F4C45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.admin_panel_settings,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: widget.userId != null
                    ? StreamBuilder<AppUser?>(
                        stream: _memberService.streamUser(widget.userId!),
                        builder: (_, snap) {
                          final name = snap.data?.displayName.isNotEmpty == true
                              ? snap.data!.displayName
                              : context.l10n.tr('Admin');
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(context.l10n.tr('Admin Panel'),
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.65),
                                      fontSize: 11)),
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                            ],
                          );
                        },
                      )
                    : Text(context.l10n.tr('Admin Panel'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_todayLabel(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              // ── Booking settings button ────────────────────────────────
              Tooltip(
                message: context.l10n.tr('Booking settings'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        BookingSettingsDialog(gymId: _classService.gymId),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune_outlined,
                        color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stats row
          IntrinsicHeight(
            child: Row(
              children: [
                _StatChip(
                  icon: Icons.group_outlined,
                  stream: _memberService.streamMembers().map((m) => m.length),
                  label: 'Members',
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.fitness_center_outlined,
                  stream: _classService
                      .streamUpcomingClasses()
                      .map((c) => c.length),
                  label: 'Upcoming',
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.today_outlined,
                  stream: _classService.streamUpcomingClasses().map((classes) =>
                      classes
                          .where((c) =>
                              DateUtils.isSameDay(c.startTime, DateTime.now()))
                          .length),
                  label: 'Today',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.stream,
    required this.label,
  });
  final IconData icon;
  final Stream<int> stream;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: StreamBuilder<int>(
        stream: stream,
        builder: (_, snap) {
          final count = snap.data ?? 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15), width: 1),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1)),
                    Text(context.l10n.tr(label),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 9,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom scrollable tab bar
// ─────────────────────────────────────────────────────────────────────────────

class _AdminTabBar extends StatelessWidget {
  const _AdminTabBar({
    required this.controller,
    required this.currentIndex,
  });
  final TabController controller;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: const Color(0xFF0F4C45),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: Colors.transparent,
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        tabs: List.generate(_tabs.length, (i) {
          final tab = _tabs[i];
          final isSelected = i == currentIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected
                  ? tab.color.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? tab.activeIcon : tab.icon,
                  size: 14,
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 5),
                Text(
                  context.l10n.tr(tab.label),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar navigation (wide-screen only)
// ─────────────────────────────────────────────────────────────────────────────

// Maps section label → tab indices
const _sidebarGroups = <(String, List<int>)>[
  ('SCHEDULE', [0, 1, 2, 3]),
  ('PEOPLE', [4, 5, 6, 7, 8, 9, 10]),
  ('FINANCE', [11, 12]),
  ('COMMS', [13]),
];

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.currentIndex,
    required this.collapsed,
    required this.onToggle,
    required this.onSelect,
    required this.uid,
    required this.memberService,
  });

  final int currentIndex;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<int> onSelect;
  final String? uid;
  final MemberService memberService;

  static const _kExpanded = 220.0;
  static const _kCollapsed = 60.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: collapsed ? _kCollapsed : _kExpanded,
      color: const Color(0xFF0F4C45),
      child: SafeArea(
        child: Column(
          children: [
            _SidebarHeader(collapsed: collapsed, onToggle: onToggle),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: _SidebarNav(
                currentIndex: currentIndex,
                collapsed: collapsed,
                onSelect: onSelect,
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _SidebarFooter(
              collapsed: collapsed,
              uid: uid,
              memberService: memberService,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed, required this.onToggle});
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return SizedBox(
        height: 52,
        child: Center(
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.menu_rounded,
                  color: Colors.white70, size: 18),
            ),
          ),
        ),
      );
    }
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.admin_panel_settings,
                color: Colors.white, size: 17),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Admin Panel',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.chevron_left_rounded,
                  color: Colors.white.withValues(alpha: 0.6), size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNav extends StatelessWidget {
  const _SidebarNav({
    required this.currentIndex,
    required this.collapsed,
    required this.onSelect,
  });

  final int currentIndex;
  final bool collapsed;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final (groupLabel, indices) in _sidebarGroups) ...[
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 3),
              child: Text(
                groupLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(
                  color: Colors.white12, height: 1, indent: 12, endIndent: 12),
            ),
          for (final idx in indices)
            _SidebarItem(
              tab: _tabs[idx],
              selected: currentIndex == idx,
              collapsed: collapsed,
              onTap: () => onSelect(idx),
            ),
        ],
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.tab,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final _AdminTab tab;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconData = selected ? tab.activeIcon : tab.icon;
    final iconColor =
        selected ? Colors.white : Colors.white.withValues(alpha: 0.55);

    if (collapsed) {
      return Tooltip(
        message: tab.label,
        preferBelow: false,
        verticalOffset: 0,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: selected
                  ? tab.color.withValues(alpha: 0.85)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Icon(iconData, size: 18, color: iconColor)),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color:
              selected ? tab.color.withValues(alpha: 0.85) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(iconData, size: 16, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tab.label,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.collapsed,
    required this.uid,
    required this.memberService,
  });

  final bool collapsed;
  final String? uid;
  final MemberService memberService;

  @override
  Widget build(BuildContext context) {
    if (uid == null) return const SizedBox(height: 52);

    return StreamBuilder<AppUser?>(
      stream: memberService.streamUser(uid!),
      builder: (context, snap) {
        final user = snap.data;
        final name = user?.displayName ?? 'Admin';
        final initials = name
            .trim()
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase())
            .take(2)
            .join();

        if (collapsed) {
          return Container(
            height: 52,
            alignment: Alignment.center,
            child: CircleAvatar(
              radius: 15,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              backgroundImage: user?.photoUrl.isNotEmpty == true
                  ? NetworkImage(user!.photoUrl)
                  : null,
              child: user?.photoUrl.isEmpty != false
                  ? Text(initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700))
                  : null,
            ),
          );
        }

        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                backgroundImage: user?.photoUrl.isNotEmpty == true
                    ? NetworkImage(user!.photoUrl)
                    : null,
                child: user?.photoUrl.isEmpty != false
                    ? Text(initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Administrator',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 9),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Sign out',
                child: InkWell(
                  onTap: () => FirebaseAuth.instance.signOut(),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.logout_rounded,
                        color: Colors.white.withValues(alpha: 0.55), size: 15),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Booking settings dialog
// ─────────────────────────────────────────────────────────────────────────────

class BookingSettingsDialog extends StatefulWidget {
  const BookingSettingsDialog({super.key, this.gymId = ''});

  final String gymId;

  @override
  State<BookingSettingsDialog> createState() => BookingSettingsDialogState();
}

class BookingSettingsDialogState extends State<BookingSettingsDialog> {
  late final _bookingService = BookingService(gymId: widget.gymId);
  final _maxPerDayCtrl = TextEditingController();
  final _lateCancelCtrl = TextEditingController();
  final _minAdvanceCtrl = TextEditingController();
  // unit: 'minutes' | 'hours' | 'days'
  String _minAdvanceUnit = 'hours';
  bool _preventOverlapping = false;
  bool _preventSameTypePerDay = false;
  bool _hideClassesWithoutSub = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxPerDayCtrl.dispose();
    _lateCancelCtrl.dispose();
    _minAdvanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _bookingService.getMaxBookingsPerDay(),
      _bookingService.getLateCancellationMinutes(),
      _bookingService.getMinAdvanceBookingMinutes(),
      _bookingService.getPreventOverlappingBookings(),
      _bookingService.getPreventSameClassTypePerDay(),
      _bookingService.getHideClassesWithoutSubscription(),
    ]);
    if (mounted) {
      setState(() {
        final max = results[0] as int;
        final lateMins = results[1] as int;
        final advanceMins = results[2] as int;
        _preventOverlapping = results[3] as bool;
        _preventSameTypePerDay = results[4] as bool;
        _hideClassesWithoutSub = results[5] as bool;
        _maxPerDayCtrl.text = max == 0 ? '' : '$max';
        _lateCancelCtrl.text = lateMins == 0 ? '' : '$lateMins';
        // Convert stored minutes to preferred unit
        if (advanceMins == 0) {
          _minAdvanceCtrl.text = '';
          _minAdvanceUnit = 'hours';
        } else if (advanceMins % 1440 == 0) {
          _minAdvanceUnit = 'days';
          _minAdvanceCtrl.text = '${advanceMins ~/ 1440}';
        } else if (advanceMins % 60 == 0) {
          _minAdvanceUnit = 'hours';
          _minAdvanceCtrl.text = '${advanceMins ~/ 60}';
        } else {
          _minAdvanceUnit = 'minutes';
          _minAdvanceCtrl.text = '$advanceMins';
        }
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final maxRaw = _maxPerDayCtrl.text.trim();
    final maxValue = maxRaw.isEmpty ? 0 : (int.tryParse(maxRaw) ?? 0);
    if (maxValue < 0) return;

    final lateRaw = _lateCancelCtrl.text.trim();
    final lateValue = lateRaw.isEmpty ? 0 : (int.tryParse(lateRaw) ?? 0);
    if (lateValue < 0) return;

    final advRaw = _minAdvanceCtrl.text.trim();
    final advNum = advRaw.isEmpty ? 0 : (int.tryParse(advRaw) ?? 0);
    if (advNum < 0) return;
    final advMinutes = advNum == 0
        ? 0
        : _minAdvanceUnit == 'days'
            ? advNum * 1440
            : _minAdvanceUnit == 'hours'
                ? advNum * 60
                : advNum;

    setState(() => _saving = true);
    await Future.wait([
      _bookingService.setMaxBookingsPerDay(maxValue),
      _bookingService.setLateCancellationMinutes(lateValue),
      _bookingService.setMinAdvanceBookingMinutes(advMinutes),
      _bookingService.setPreventOverlappingBookings(_preventOverlapping),
      _bookingService.setPreventSameClassTypePerDay(_preventSameTypePerDay),
      _bookingService.setHideClassesWithoutSubscription(_hideClassesWithoutSub),
    ]);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('Booking rules saved.')),
          backgroundColor: const Color(0xFF0F766E),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.tune_outlined,
                color: Color(0xFF0F766E), size: 20),
          ),
          const SizedBox(width: 10),
          Text(context.l10n.tr('Booking Rules'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 60, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Max bookings per day ──────────────────────────────
                  Text(
                    context.l10n.tr('Max bookings per member per day'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.tr('Leave empty or set to 0 for unlimited.'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _maxPerDayCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: context.l10n.tr('0 = unlimited'),
                      prefixIcon: const Icon(Icons.event_repeat_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.amber, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.tr(
                              'Applies to all member bookings. Admin bookings for members bypass this limit.',
                            ),
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.75)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),

                  // ── Late-cancellation penalty ─────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.timer_off_outlined,
                            color: Colors.orange, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.tr('Late-cancellation penalty'),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.tr(
                      'If a member cancels within this many minutes before the class starts, it counts as a used session against their offer. Set to 0 to disable.',
                    ),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lateCancelCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: context.l10n.tr('0 = disabled  (e.g. 30)'),
                      prefixIcon: const Icon(Icons.timer_off_outlined),
                      suffixText: 'min',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.orange, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.tr(
                              'Example: setting 30 means a member who cancels less than 30 minutes before the class loses one session from their offer.',
                            ),
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.75)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),

                  // ── Minimum advance booking time ──────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.schedule_outlined,
                            color: Colors.blue, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n
                              .tr('Booking window (opens X before class)'),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.tr(
                      'Booking opens this many hours/minutes before the class starts. Members cannot book earlier than this window. Set to 0 to disable.',
                    ),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _minAdvanceCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: InputDecoration(
                            hintText: context.l10n.tr('0 = disabled'),
                            prefixIcon: const Icon(Icons.schedule_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      DropdownButtonHideUnderline(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: cs.outline.withValues(alpha: 0.5)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButton<String>(
                            value: _minAdvanceUnit,
                            items: [
                              DropdownMenuItem(
                                  value: 'minutes',
                                  child: Text(context.l10n.tr('min'))),
                              DropdownMenuItem(
                                  value: 'hours',
                                  child: Text(context.l10n.tr('hours'))),
                              DropdownMenuItem(
                                  value: 'days',
                                  child: Text(context.l10n.tr('days'))),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _minAdvanceUnit = v);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.tr(
                              'Example: "1 day" means members must book at least 24 hours before the class starts. Admin force-reservations bypass this rule.',
                            ),
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.75)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),

                  // ── Prevent overlapping time slots ────────────────────
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.event_busy_outlined,
                          color: Colors.red, size: 16),
                    ),
                    title: Text(
                      context.l10n.tr('Prevent overlapping bookings'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      context.l10n.tr(
                          'Members cannot book a class whose time slot overlaps with an existing booking.'),
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant),
                    ),
                    value: _preventOverlapping,
                    onChanged: (v) =>
                        setState(() => _preventOverlapping = v),
                  ),

                  const SizedBox(height: 8),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),

                  // ── Prevent same class type per day ───────────────────
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.block_outlined,
                          color: Colors.purple, size: 16),
                    ),
                    title: Text(
                      context.l10n.tr('One class type per day'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      context.l10n.tr(
                          'Members can only book one class of the same type per day (requires class type to be set on each class).'),
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant),
                    ),
                    value: _preventSameTypePerDay,
                    onChanged: (v) =>
                        setState(() => _preventSameTypePerDay = v),
                  ),

                  const SizedBox(height: 8),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),

                  // ── Hide classes without subscription ─────────────────
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.visibility_off_outlined,
                          color: Colors.orange, size: 16),
                    ),
                    title: Text(
                      context.l10n.tr('Hide classes without subscription'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      context.l10n.tr(
                          'Members without an active subscription cannot see or browse the class schedule.'),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                    value: _hideClassesWithoutSub,
                    onChanged: (v) =>
                        setState(() => _hideClassesWithoutSub = v),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.tr('Cancel'))),
        FilledButton(
          onPressed: _saving ? null : _save,
          style:
              FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(context.l10n.tr('Save')),
        ),
      ],
    );
  }
}
