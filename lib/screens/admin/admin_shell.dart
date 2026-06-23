import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../services/notification_service.dart';
import '../notifications/notifications_screen.dart';
import 'admin_calendar_screen.dart';
import 'admin_dashboard_screen.dart' show BookingSettingsDialog;
import 'payment_calendar_screen.dart';
import 'tabs/admin_attendance_tab.dart';
import 'tabs/admin_checkin_tab.dart';
import 'tabs/admin_classes_tab.dart';
import 'tabs/admin_dropins_tab.dart';
import 'tabs/admin_members_tab.dart';
import 'tabs/admin_offers_tab.dart';
import 'tabs/admin_personal_training_tab.dart';
import 'tabs/admin_templates_tab.dart';
import 'tabs/admin_coaches_tab.dart';
import 'tabs/admin_wod_calendar_tab.dart';
import 'tabs/admin_wod_tab.dart';
import 'tabs/admin_billing_tab.dart';
import 'tabs/admin_finance_tab.dart';
import 'tabs/admin_announcements_tab.dart';
import '../../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _AdminSection {
  const _AdminSection({required this.title, required this.items});
  final String title;
  final List<_AdminItem> items;
}

class _AdminItem {
  const _AdminItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.color,
  });
  final int index;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color color;
}

// ⚠️  DUAL-FILE NAV: When adding a new item here, you MUST also update
//    admin_dashboard_screen.dart (_tabs + _buildTabChildren + _sidebarGroups)
//    for the mobile sidebar, otherwise the new tab will be invisible on mobile.
const _adminSections = <_AdminSection>[
  _AdminSection(title: 'SCHEDULING', items: [
    _AdminItem(
      index: 0,
      label: 'Calendar',
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month,
      color: Color(0xFF0F766E),
    ),
    _AdminItem(
      index: 1,
      label: 'Classes',
      icon: Icons.fitness_center_outlined,
      activeIcon: Icons.fitness_center,
      color: Color(0xFF0F766E),
    ),
    _AdminItem(
      index: 2,
      label: 'Templates',
      icon: Icons.repeat_outlined,
      activeIcon: Icons.repeat,
      color: Color(0xFF7C3AED),
    ),
  ]),
  _AdminSection(title: 'TRAINING', items: [
    _AdminItem(
      index: 3,
      label: 'Workouts',
      icon: Icons.local_fire_department_outlined,
      activeIcon: Icons.local_fire_department,
      color: Color(0xFFF97316),
    ),
    _AdminItem(
      index: 4,
      label: 'WOD Calendar',
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today,
      color: Color(0xFFF97316),
    ),
    _AdminItem(
      index: 14,
      label: 'Private PT',
      icon: Icons.person_pin_outlined,
      activeIcon: Icons.person_pin,
      color: Color(0xFF7C3AED),
    ),
  ]),
  _AdminSection(title: 'PEOPLE', items: [
    _AdminItem(
      index: 5,
      label: 'Members',
      icon: Icons.group_outlined,
      activeIcon: Icons.group,
      color: Color(0xFF0369A1),
    ),
    _AdminItem(
      index: 10,
      label: 'Coaches',
      icon: Icons.sports_outlined,
      activeIcon: Icons.sports,
      color: Color(0xFF2563EB),
    ),
    _AdminItem(
      index: 6,
      label: 'Attendance',
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      color: Color(0xFFDC2626),
    ),
    _AdminItem(
      index: 7,
      label: 'Check-in QR',
      icon: Icons.qr_code_2_rounded,
      activeIcon: Icons.qr_code_2_rounded,
      color: Color(0xFF0D7377),
    ),
  ]),
  _AdminSection(title: 'BUSINESS', items: [
    _AdminItem(
      index: 8,
      label: 'Offers',
      icon: Icons.card_membership_outlined,
      activeIcon: Icons.card_membership,
      color: Color(0xFF059669),
    ),
    _AdminItem(
      index: 9,
      label: 'Drop-ins',
      icon: Icons.directions_walk_outlined,
      activeIcon: Icons.directions_walk,
      color: Color(0xFFEA580C),
    ),
    _AdminItem(
      index: 11,
      label: 'Billing',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      color: Color(0xFF059669),
    ),
    _AdminItem(
      index: 12,
      label: 'Finance',
      icon: Icons.bar_chart_rounded,
      activeIcon: Icons.bar_chart_rounded,
      color: Color(0xFF0F766E),
    ),
    _AdminItem(
      index: 13,
      label: 'Announcements',
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign_rounded,
      color: Color(0xFF7C3AED),
    ),
  ]),
];

// ─────────────────────────────────────────────────────────────────────────────
// Bottom nav quick-access items (mobile only)
// ─────────────────────────────────────────────────────────────────────────────

class _QuickItem {
  const _QuickItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
  final int index;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _quickItems = <_QuickItem>[
  _QuickItem(
    index: 0,
    label: 'Calendar',
    icon: Icons.calendar_month_outlined,
    activeIcon: Icons.calendar_month,
  ),
  _QuickItem(
    index: 1,
    label: 'Classes',
    icon: Icons.fitness_center_outlined,
    activeIcon: Icons.fitness_center,
  ),
  _QuickItem(
    index: 5,
    label: 'Members',
    icon: Icons.group_outlined,
    activeIcon: Icons.group,
  ),
  _QuickItem(
    index: 6,
    label: 'Attendance',
    icon: Icons.fact_check_outlined,
    activeIcon: Icons.fact_check,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// AdminShell
// ─────────────────────────────────────────────────────────────────────────────

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.userId, this.appUser});

  final String userId;
  final AppUser? appUser;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;
  final _notificationService = NotificationService();

  // ── Helpers ──────────────────────────────────────────────────────────────

  String get _adminName => widget.appUser?.displayName.isNotEmpty == true
      ? widget.appUser!.displayName
      : 'Admin';

  String get _adminInitials {
    final name = _adminName;
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'A';
  }

  // ── Content ───────────────────────────────────────────────────────────────

  Widget _buildContent() {
    final gymId = widget.appUser?.gymId ?? '';
    return switch (_selectedIndex) {
      0 => AdminCalendarScreen(gymId: gymId),
      1 => AdminClassesTab(gymId: gymId),
      2 => AdminTemplatesTab(gymId: gymId),
      3 => AdminWodTab(gymId: gymId),
      4 => AdminWodCalendarTab(gymId: gymId),
      14 => AdminPersonalTrainingTab(gymId: gymId),
      5 => AdminMembersTab(gymId: gymId),
      6 => AdminAttendanceTab(gymId: gymId),
      7 => AdminCheckinTab(gymId: gymId),
      8 => AdminOffersTab(gymId: gymId),
      9 => AdminDropInsTab(gymId: gymId),
      10 => AdminCoachesTab(gymId: gymId),
      11 => AdminBillingTab(gymId: gymId),
      12 => AdminFinanceTab(gymId: gymId),
      13 => AdminAnnouncementsTab(gymId: gymId),
      _ => AdminCalendarScreen(gymId: gymId),
    };
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 700;

    return AppBar(
      backgroundColor: const Color(0xFF0F2922),
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: isWide
          ? IconButton(
              icon: Icon(
                _sidebarExpanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                color: Colors.white70,
              ),
              tooltip: context.l10n.tr(_sidebarExpanded ? 'Collapse sidebar' : 'Expand sidebar'),
              onPressed: () =>
                  setState(() => _sidebarExpanded = !_sidebarExpanded),
            )
          : null,
      automaticallyImplyLeading: !isWide,
      title: isWide
          ? _buildWebBreadcrumb()
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.fitness_center,
                      color: Colors.white, size: 15),
                ),
                const SizedBox(width: 8),
                const Text(
                  'FitFlow Admin',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ],
            ),
      actions: [
        // Booking rules button
        IconButton(
          tooltip: context.l10n.tr('Booking Rules'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) =>
                BookingSettingsDialog(gymId: widget.appUser?.gymId ?? ''),
          ),
          icon: const Icon(Icons.tune_outlined, color: Colors.white),
        ),
        // Notification bell
        StreamBuilder<int>(
          stream: _notificationService.streamUnreadCount(widget.userId),
          builder: (context, snap) {
            final count = snap.data ?? 0;
            return IconButton(
              tooltip: context.l10n.tr('Notifications'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => NotificationsScreen()),
              ),
              icon: count > 0
                  ? Badge(
                      label:
                          Text('$count', style: const TextStyle(fontSize: 10)),
                      child: const Icon(Icons.notifications_outlined,
                          color: Colors.white),
                    )
                  : const Icon(Icons.notifications_outlined,
                      color: Colors.white),
            );
          },
        ),
        // Admin profile chip (wide) with dropdown, or sign-out icon (mobile)
        if (isWide)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: PopupMenuButton<String>(
                tooltip: context.l10n.tr('Admin menu'),
                offset: const Offset(0, 40),
                onSelected: (v) async {
                  if (v == 'signout') await FirebaseAuth.instance.signOut();
                  if (v == 'booking_rules' && context.mounted) {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => BookingSettingsDialog(
                          gymId: widget.appUser?.gymId ?? ''),
                    );
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: const Color(0xFF0F766E),
                        child: Text(_adminInitials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 7),
                      Text(_adminName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 5),
                      const Icon(Icons.expand_more,
                          color: Colors.white70, size: 14),
                    ],
                  ),
                ),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_adminName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(widget.appUser?.email ?? '',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'booking_rules',
                    child: Row(children: [
                      const Icon(Icons.tune_outlined, size: 16),
                      const SizedBox(width: 8),
                      Text(context.l10n.tr('Booking Rules')),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'signout',
                    child: Row(children: [
                      const Icon(Icons.logout, size: 16),
                      const SizedBox(width: 8),
                      Text(context.l10n.tr('Sign out')),
                    ]),
                  ),
                ],
              ),
            ),
          )
        else
          IconButton(
            tooltip: context.l10n.tr('Sign out'),
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () async => FirebaseAuth.instance.signOut(),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildWebBreadcrumb() {
    String sectionTitle = '';
    _AdminItem? currentItem;
    for (final section in _adminSections) {
      for (final item in section.items) {
        if (item.index == _selectedIndex) {
          sectionTitle = section.title;
          currentItem = item;
          break;
        }
      }
      if (currentItem != null) break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (currentItem != null) ...[
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: currentItem.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(currentItem.activeIcon,
                color: currentItem.color, size: 15),
          ),
          const SizedBox(width: 10),
          Text(
            context.l10n.tr(sectionTitle),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.w400,
                fontSize: 13),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.4), size: 16),
          ),
          Text(
            context.l10n.tr(currentItem.label),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ] else
          Text('${context.l10n.tr('FitFlow')} ${context.l10n.tr('Admin')}',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
      ],
    );
  }

  // ── Sidebar (web) ─────────────────────────────────────────────────────────

  Widget _buildSidebar(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isRailMode = width < 1050;
    final showLabels = !isRailMode && _sidebarExpanded;
    final sidebarWidth = isRailMode ? 68.0 : (_sidebarExpanded ? 240.0 : 68.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: sidebarWidth,
      decoration: const BoxDecoration(
        color: Color(0xFF0A1F1A),
        border: Border(right: BorderSide(color: Color(0xFF1A3530), width: 1)),
      ),
      child: Column(
        children: [
          _buildSidebarBrand(showLabels: showLabels),
          _buildSidebarAdminInfo(showLabels: showLabels),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _adminSections
                  .map((s) =>
                      _buildSidebarSection(s, context, showLabels: showLabels))
                  .toList(),
            ),
          ),
          _buildSidebarBookingSettings(showLabels: showLabels),
          _buildSidebarPaymentCalendar(showLabels: showLabels),
          _buildSidebarLogout(showLabels: showLabels),
        ],
      ),
    );
  }

  Widget _buildSidebarBrand({required bool showLabels}) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: showLabels ? 16 : 12, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1A3530))),
      ),
      child: Row(
        mainAxisAlignment:
            showLabels ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.fitness_center, color: Colors.white, size: 18),
          ),
          if (showLabels) ...[
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.tr('FitFlow'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                Text(context.l10n.tr('Admin Panel'),
                    style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 11)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSidebarAdminInfo({required bool showLabels}) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: showLabels ? 16 : 0, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1A3530))),
      ),
      child: showLabels
          ? Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF0F766E),
                  child: Text(_adminInitials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_adminName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(DateFormat('EEE, d MMM').format(DateTime.now()),
                          style: const TextStyle(
                              color: Color(0xFF6EE7B7), fontSize: 11)),
                    ],
                  ),
                ),
              ],
            )
          : Center(
              child: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF0F766E),
                child: Text(_adminInitials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ),
    );
  }

  Widget _buildSidebarBookingSettings({required bool showLabels}) {
    void openDialog() => showDialog<void>(
          context: context,
          builder: (_) =>
              BookingSettingsDialog(gymId: widget.appUser?.gymId ?? ''),
        );

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1A3530))),
      ),
      child: showLabels
          ? ListTile(
              dense: true,
              leading: const Icon(Icons.tune_outlined,
                  size: 18, color: Color(0xFF6B7280)),
              title: Text(context.l10n.tr('Booking Rules'),
                  style:
                      const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
              onTap: openDialog,
            )
          : Tooltip(
              message: context.l10n.tr('Booking Rules'),
              child: InkWell(
                onTap: openDialog,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: Icon(Icons.tune_outlined,
                          size: 18, color: Color(0xFF6B7280))),
                ),
              ),
            ),
    );
  }

  Widget _buildSidebarPaymentCalendar({required bool showLabels}) {
    void openCalendar() => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                PaymentCalendarScreen(gymId: widget.appUser?.gymId ?? ''),
          ),
        );

    return showLabels
        ? ListTile(
            dense: true,
            leading: const Icon(Icons.calendar_month_outlined,
                size: 18, color: Color(0xFF6B7280)),
            title: Text(context.l10n.tr('Payment Calendar'),
                style:
                    const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
            onTap: openCalendar,
          )
        : Tooltip(
            message: context.l10n.tr('Payment Calendar'),
            child: InkWell(
              onTap: openCalendar,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                    child: Icon(Icons.calendar_month_outlined,
                        size: 18, color: Color(0xFF6B7280))),
              ),
            ),
          );
  }

  Widget _buildSidebarLogout({required bool showLabels}) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1A3530))),
      ),
      child: showLabels
          ? ListTile(
              dense: true,
              leading:
                  const Icon(Icons.logout, size: 18, color: Color(0xFF6B7280)),
              title: Text(context.l10n.tr('Sign out'),
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
              onTap: () async => FirebaseAuth.instance.signOut(),
            )
          : Tooltip(
              message: context.l10n.tr('Sign out'),
              child: InkWell(
                onTap: () async => FirebaseAuth.instance.signOut(),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: Icon(Icons.logout,
                          size: 18, color: Color(0xFF6B7280))),
                ),
              ),
            ),
    );
  }

  Widget _buildSidebarSection(_AdminSection section, BuildContext context,
      {required bool showLabels}) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(showLabels ? 12 : 4, 10, showLabels ? 12 : 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLabels)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Text(
                context.l10n.tr(section.title),
                style: const TextStyle(
                    color: Color(0xFF4B7A6E),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Divider(color: const Color(0xFF1A3530), height: 1),
            ),
          ...section.items.map((item) =>
              _buildSidebarItem(item, context, showLabels: showLabels)),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(_AdminItem item, BuildContext context,
      {required bool showLabels}) {
    final isSelected = _selectedIndex == item.index;

    final itemWidget = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? item.color.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Left accent bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: isSelected ? item.color : Colors.transparent,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(3),
                bottomRight: Radius.circular(3),
              ),
            ),
          ),
          Expanded(
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: showLabels ? 10 : 6, vertical: 0),
              leading: Icon(
                isSelected ? item.activeIcon : item.icon,
                size: 18,
                color: isSelected ? item.color : const Color(0xFF9CA3AF),
              ),
              title: showLabels
                  ? Text(
                      context.l10n.tr(item.label),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w400,
                        color:
                            isSelected ? Colors.white : const Color(0xFF9CA3AF),
                      ),
                    )
                  : null,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              selected: isSelected,
              onTap: () => setState(() => _selectedIndex = item.index),
            ),
          ),
        ],
      ),
    );

    if (!showLabels) {
      return Tooltip(
        message: context.l10n.tr(item.label),
        preferBelow: false,
        verticalOffset: 0,
        child: itemWidget,
      );
    }
    return itemWidget;
  }

  // ── Drawer (mobile) ───────────────────────────────────────────────────────

  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0A1F1A),
      child: SafeArea(
        child: Column(
          children: [
            _buildSidebarBrand(showLabels: true),
            _buildSidebarAdminInfo(showLabels: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _adminSections
                    .map((s) =>
                        _buildSidebarSection(s, context, showLabels: true))
                    .toList(),
              ),
            ),
            _buildSidebarBookingSettings(showLabels: true),
            _buildSidebarPaymentCalendar(showLabels: true),
            _buildSidebarLogout(showLabels: true),
          ],
        ),
      ),
    );
  }

  // ── Bottom nav (mobile) ───────────────────────────────────────────────────

  BottomNavigationBar _buildBottomNav(BuildContext context) {
    final quickSelected =
        _quickItems.indexWhere((q) => q.index == _selectedIndex);

    return BottomNavigationBar(
      currentIndex: quickSelected >= 0 ? quickSelected : 0,
      onTap: (i) {
        setState(() => _selectedIndex = _quickItems[i].index);
      },
      selectedItemColor: const Color(0xFF0F766E),
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      items: _quickItems
          .map(
            (q) => BottomNavigationBarItem(
              icon: Icon(q.icon),
              activeIcon: Icon(q.activeIcon),
              label: q.label,
            ),
          )
          .toList(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final content = _buildContent();

    if (isWide) {
      return Scaffold(
        appBar: _buildAppBar(context),
        body: Row(
          children: [
            _buildSidebar(context),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) =>
                    FadeTransition(opacity: a, child: c),
                child:
                    KeyedSubtree(key: ValueKey(_selectedIndex), child: content),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(context),
      drawer: _buildDrawer(context),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
        child: KeyedSubtree(key: ValueKey(_selectedIndex), child: content),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }
}
