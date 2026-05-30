import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../services/member_service.dart';
import '../../../widgets/role_widgets.dart';
import '../../../widgets/user_avatar.dart';
import '../assigned_offers_screen.dart';
import '../create_member_screen.dart';
import '../member_detail_screen.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _kWideBreakpoint = 800.0;
// Detail panel opens as modal dialog only at this wider breakpoint
// (matches MemberDetailScreen's 900px wide-layout threshold).
const _kDialogBreakpoint = 900.0;

const _statusFilters = <String>['all', 'active', 'paused', 'cancelled', 'none'];

// ── Main Tab ─────────────────────────────────────────────────────────────────

class AdminMembersTab extends StatefulWidget {
  const AdminMembersTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminMembersTab> createState() => _AdminMembersTabState();
}

class _AdminMembersTabState extends State<AdminMembersTab> {
  late final _memberService = MemberService(gymId: widget.gymId);
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all';
  String _sortField = 'name'; // 'name' | 'status' | 'joinDate'
  bool _sortAscending = true;
  String? _selectedMemberId;
  bool _dialogOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppUser> _process(List<AppUser> members) {
    final q = _searchQuery.toLowerCase();
    var result = members.where((m) {
      final matchSearch = q.isEmpty ||
          m.displayName.toLowerCase().contains(q) ||
          m.email.toLowerCase().contains(q) ||
          m.effectiveRoles.any((r) => r.contains(q));
      final matchStatus =
          _statusFilter == 'all' || m.subscriptionStatus == _statusFilter;
      return matchSearch && matchStatus;
    }).toList();

    result.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case 'status':
          cmp = a.subscriptionStatus.compareTo(b.subscriptionStatus);
        case 'joinDate':
          final aDate = a.joinDate ?? DateTime(1970);
          final bDate = b.joinDate ?? DateTime(1970);
          cmp = aDate.compareTo(bDate);
        default:
          final aName = a.displayName.isEmpty ? a.email : a.displayName;
          final bName = b.displayName.isEmpty ? b.email : b.displayName;
          cmp = aName.toLowerCase().compareTo(bName.toLowerCase());
      }
      return _sortAscending ? cmp : -cmp;
    });
    return result;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _openProfile(AppUser member) {
    if (_dialogOpen) return; // prevent dialog stacking
    final width = MediaQuery.sizeOf(context).width;
    if (width >= _kDialogBreakpoint) {
      setState(() {
        _selectedMemberId = member.id;
        _dialogOpen = true;
      });
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        transitionDuration: const Duration(milliseconds: 220),
        transitionBuilder: (ctx, anim, _, child) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
        pageBuilder: (ctx, _, __) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: double.maxFinite,
            height: double.maxFinite,
            child: MemberDetailScreen(member: member, asDialog: true),
          ),
        ),
      ).whenComplete(() {
        if (mounted) {
          setState(() {
            _selectedMemberId = null;
            _dialogOpen = false;
          });
        }
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MemberDetailScreen(member: member),
        ),
      );
    }
  }

  Future<void> _copyEmail(AppUser member) async {
    await Clipboard.setData(ClipboardData(text: member.email));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10n.tr('Copied')}: ${member.email}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _addMember() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CreateMemberScreen(gymId: widget.gymId),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('Member created.'))),
      );
    }
  }

  Future<void> _toggleStatus(AppUser member) async {
    final newStatus =
        member.subscriptionStatus == 'active' ? 'paused' : 'active';
    await _memberService.updateMembership(
      userId: member.id,
      membershipPlanId: member.membershipPlanId,
      subscriptionStatus: newStatus,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'active'
                ? '${member.displayName} ${context.l10n.tr('activated.')}'
                : '${member.displayName} ${context.l10n.tr('paused.')}',
          ),
        ),
      );
    }
  }

  Future<void> _showChangeRoleDialog(AppUser member) async {
    final selected = Set<String>.from(member.effectiveRoles);
    const allRoles = ['member', 'coach', 'staff', 'admin'];
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('${context.l10n.tr('Change role')} — ${member.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: allRoles.map((r) {
              return CheckboxListTile(
                value: selected.contains(r),
                title: Text(_roleLabel(context, r)),
                secondary: Icon(_roleIcon(r), color: _roleColor(r)),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      selected.add(r);
                    } else {
                      if (selected.length > 1) selected.remove(r);
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
                  userId: member.id,
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

  Future<void> _showDeleteConfirm(AppUser member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 32),
        title: Text(context.l10n.tr('Delete member?')), 
        content: Text(
          '${context.l10n.tr('This will permanently remove')} ${member.displayName.isEmpty ? member.email : member.displayName} ${context.l10n.tr('from the system. This action cannot be undone.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(member.id)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.displayName} ${context.l10n.tr('deleted.')}')), 
        );
      }
    }
  }

  void _cycleSortField(String field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = true;
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _kWideBreakpoint;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: StreamBuilder<List<AppUser>>(
          stream: _memberService.streamMembers(),
          builder: (context, snapshot) {
            final allMembers = snapshot.data ?? <AppUser>[];
            final processed = _process(allMembers);
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;

            return Column(
              children: [
                _MembersHeader(
                  allMembers: allMembers,
                  searchController: _searchController,
                  searchQuery: _searchQuery,
                  statusFilter: _statusFilter,
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  onFilterChanged: (v) => setState(() => _statusFilter = v),
                  isWide: isWide,
                  onAddMember: _addMember,
                  onAssignedOffers: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AssignedOffersScreen(gymId: widget.gymId),
                    ),
                  ),
                  sortField: _sortField,
                  sortAscending: _sortAscending,
                  onSortChanged: _cycleSortField,
                ),
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : processed.isEmpty
                          ? _EmptyState(
                              hasSearch: _searchQuery.isNotEmpty ||
                                  _statusFilter != 'all',
                            )
                          : isWide
                              ? _WebMembersTable(
                                  members: processed,
                                  sortField: _sortField,
                                  sortAscending: _sortAscending,
                                  onSortChanged: _cycleSortField,
                                  onProfile: _openProfile,
                                  onCopyEmail: _copyEmail,
                                  onChangeRole: _showChangeRoleDialog,
                                  onToggleStatus: _toggleStatus,
                                  onDelete: _showDeleteConfirm,
                                  selectedMemberId: _selectedMemberId,
                                )
                              : _MobileList(
                                  members: processed,
                                  onProfile: _openProfile,
                                  onCopyEmail: _copyEmail,
                                  onChangeRole: _showChangeRoleDialog,
                                  onToggleStatus: _toggleStatus,
                                  onDelete: _showDeleteConfirm,
                                ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: isWide
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'assigned-offers-fab',
                    tooltip: context.l10n.tr('All assigned offers'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AssignedOffersScreen(gymId: widget.gymId),
                      ),
                    ),
                    child: const Icon(Icons.receipt_long_outlined),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.extended(
                    heroTag: 'add-member-fab',
                    onPressed: _addMember,
                    icon: const Icon(Icons.person_add_outlined),
                    label: Text(context.l10n.tr('Add Member')), 
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _MembersHeader extends StatelessWidget {
  const _MembersHeader({
    required this.allMembers,
    required this.searchController,
    required this.searchQuery,
    required this.statusFilter,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.isWide,
    required this.onAddMember,
    required this.onAssignedOffers,
    required this.sortField,
    required this.sortAscending,
    required this.onSortChanged,
  });

  final List<AppUser> allMembers;
  final TextEditingController searchController;
  final String searchQuery;
  final String statusFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;
  final bool isWide;
  final VoidCallback onAddMember;
  final VoidCallback onAssignedOffers;
  final String sortField;
  final bool sortAscending;
  final ValueChanged<String> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = allMembers.length;
    final active =
        allMembers.where((m) => m.subscriptionStatus == 'active').length;
    final coaches = allMembers
        .where((m) =>
            m.effectiveRoles.contains('coach') ||
            m.effectiveRoles.contains('staff'))
        .length;
    final noPlan =
        allMembers.where((m) => m.subscriptionStatus == 'none').length;

    return Container(
      color: cs.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar: stats + (web) action buttons
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _StatBadge(
                        icon: Icons.groups_outlined,
                        label: '$total ${context.l10n.tr('total')}',
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        icon: Icons.check_circle_outline,
                        label: '$active ${context.l10n.tr('active')}',
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        icon: Icons.sports_martial_arts_outlined,
                        label: '$coaches ${context.l10n.tr('coaches')}',
                        color: const Color(0xFF0F766E),
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        icon: Icons.remove_circle_outline,
                        label: '$noPlan ${context.l10n.tr('no plan')}',
                        color: Colors.grey.shade600,
                      ),
                    ],
                  ),
                ),
              ),
              if (isWide) ...[
                const SizedBox(width: 12),
                // Sort menu
                _SortButton(
                  sortField: sortField,
                  sortAscending: sortAscending,
                  onChanged: onSortChanged,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onAssignedOffers,
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text(context.l10n.tr('Offers')), 
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onAddMember,
                  icon: const Icon(Icons.person_add_outlined, size: 16),
                  label: Text(context.l10n.tr('Add Member')), 
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Search + filter row
          if (isWide)
            Row(
              children: [
                Expanded(
                    child: _SearchField(
                  controller: searchController,
                  query: searchQuery,
                  onChanged: onSearchChanged,
                )),
                const SizedBox(width: 12),
                _FilterChips(
                  statusFilter: statusFilter,
                  onChanged: onFilterChanged,
                ),
              ],
            )
          else ...[
            _SearchField(
              controller: searchController,
              query: searchQuery,
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 10),
            _FilterChips(
              statusFilter: statusFilter,
              onChanged: onFilterChanged,
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: context.l10n.tr('Search by name, email, role…'),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        isDense: true,
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.statusFilter, required this.onChanged});

  final String statusFilter;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _statusFilters.map((s) {
          final selected = statusFilter == s;
          final color = _filterColor(s, context);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: selected,
              label: Text(_filterLabel(context, s)),
              avatar: selected ? null : Icon(_filterIcon(s), size: 14),
              onSelected: (_) => onChanged(s),
              selectedColor: color.withValues(alpha: 0.15),
              side: BorderSide(
                color: selected
                    ? color
                    : Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.4),
              ),
              labelStyle: TextStyle(
                fontSize: 12,
                color: selected ? color : null,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  String _filterLabel(BuildContext context, String s) {
    switch (s) {
      case 'all':
        return context.l10n.tr('All');
      case 'active':
        return context.l10n.tr('Active');
      case 'paused':
        return context.l10n.tr('Paused');
      case 'cancelled':
        return context.l10n.tr('Cancelled');
      case 'none':
        return context.l10n.tr('No plan');
      default:
        return s;
    }
  }

  IconData _filterIcon(String s) {
    switch (s) {
      case 'active':
        return Icons.check_circle_outline;
      case 'paused':
        return Icons.pause_circle_outline;
      case 'cancelled':
        return Icons.cancel_outlined;
      case 'none':
        return Icons.remove_circle_outline;
      default:
        return Icons.people_outline;
    }
  }

  Color _filterColor(String s, BuildContext context) {
    switch (s) {
      case 'active':
        return Colors.green.shade600;
      case 'paused':
        return Colors.orange.shade600;
      case 'cancelled':
        return Colors.red.shade600;
      case 'none':
        return Colors.grey.shade600;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.sortField,
    required this.sortAscending,
    required this.onChanged,
  });

  final String sortField;
  final bool sortAscending;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: context.l10n.tr('Sort'),
      offset: const Offset(0, 40),
      itemBuilder: (_) => [
        _sortItem('name', context.l10n.tr('Name')), 
        _sortItem('status', context.l10n.tr('Status')), 
        _sortItem('joinDate', context.l10n.tr('Join Date')), 
      ],
      onSelected: onChanged,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              _sortLabel(context, sortField),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 14),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (sortField == value)
            Icon(
              sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: Colors.blue,
            )
          else
            const SizedBox(width: 14),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  String _sortLabel(BuildContext context, String f) {
    switch (f) {
      case 'status':
        return context.l10n.tr('Status');
      case 'joinDate':
        return context.l10n.tr('Join Date');
      default:
        return context.l10n.tr('Name');
    }
  }
}

// ── Web Table ────────────────────────────────────────────────────────────────

class _WebMembersTable extends StatelessWidget {
  const _WebMembersTable({
    required this.members,
    required this.sortField,
    required this.sortAscending,
    required this.onSortChanged,
    required this.onProfile,
    required this.onCopyEmail,
    required this.onChangeRole,
    required this.onToggleStatus,
    required this.onDelete,
    this.selectedMemberId,
  });

  final List<AppUser> members;
  final String sortField;
  final bool sortAscending;
  final ValueChanged<String> onSortChanged;
  final ValueChanged<AppUser> onProfile;
  final ValueChanged<AppUser> onCopyEmail;
  final ValueChanged<AppUser> onChangeRole;
  final ValueChanged<AppUser> onToggleStatus;
  final ValueChanged<AppUser> onDelete;
  final String? selectedMemberId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Header row
        Container(
          color: cs.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              _HeaderCell(
                label: context.l10n.tr('Member'),
                flex: 3,
                field: 'name',
                sortField: sortField,
                sortAscending: sortAscending,
                onSort: onSortChanged,
              ),
              _HeaderCell(
                label: context.l10n.tr('Email'),
                flex: 3,
                field: null,
                sortField: sortField,
                sortAscending: sortAscending,
                onSort: onSortChanged,
              ),
              _HeaderCell(
                label: context.l10n.tr('Status'),
                flex: 2,
                field: 'status',
                sortField: sortField,
                sortAscending: sortAscending,
                onSort: onSortChanged,
              ),
              _HeaderCell(
                label: context.l10n.tr('Joined'),
                flex: 2,
                field: 'joinDate',
                sortField: sortField,
                sortAscending: sortAscending,
                onSort: onSortChanged,
              ),
              const SizedBox(width: 120), // actions column
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: members.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _WebMemberRow(
              member: members[i],
              isSelected: selectedMemberId == members[i].id,
              onProfile: onProfile,
              onCopyEmail: onCopyEmail,
              onChangeRole: onChangeRole,
              onToggleStatus: onToggleStatus,
              onDelete: onDelete,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.flex,
    required this.field,
    required this.sortField,
    required this.sortAscending,
    required this.onSort,
  });

  final String label;
  final int flex;
  final String? field;
  final String sortField;
  final bool sortAscending;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final isActive = field != null && sortField == field;
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Expanded(
      flex: flex,
      child: field != null
          ? InkWell(
              onTap: () => onSort(field!),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (isActive)
                      Icon(
                        sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 12,
                        color: color,
                      )
                    else
                      Icon(
                        Icons.unfold_more,
                        size: 12,
                        color: color.withValues(alpha: 0.5),
                      ),
                  ],
                ),
              ),
            )
          : Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
    );
  }
}

class _WebMemberRow extends StatefulWidget {
  const _WebMemberRow({
    required this.member,
    required this.onProfile,
    required this.onCopyEmail,
    required this.onChangeRole,
    required this.onToggleStatus,
    required this.onDelete,
    this.isSelected = false,
  });

  final AppUser member;
  final ValueChanged<AppUser> onProfile;
  final ValueChanged<AppUser> onCopyEmail;
  final ValueChanged<AppUser> onChangeRole;
  final ValueChanged<AppUser> onToggleStatus;
  final ValueChanged<AppUser> onDelete;
  final bool isSelected;

  @override
  State<_WebMemberRow> createState() => _WebMemberRowState();
}

class _WebMemberRowState extends State<_WebMemberRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = widget.member;
    final name = m.displayName.isEmpty ? m.email : m.displayName;
    final joinDate =
        m.joinDate != null ? DateFormat('d MMM yyyy').format(m.joinDate!) : '—';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? cs.primary.withValues(alpha: 0.08)
              : _hovered
                  ? cs.primary.withValues(alpha: 0.04)
                  : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: widget.isSelected ? cs.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: InkWell(
          onTap: () => widget.onProfile(m),
          child: Padding(
            padding: EdgeInsets.only(
              left: widget.isSelected ? 17 : 20,
              right: 20,
              top: 12,
              bottom: 12,
            ),
            child: Row(
              children: [
                // Member column
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      _MemberAvatar(
                        photoUrl: m.photoUrl,
                        initials: name[0].toUpperCase(),
                        role: m.role,
                        radius: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            RoleBadgeRow(roles: m.effectiveRoles),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Email column
                Expanded(
                  flex: 3,
                  child: Text(
                    m.email,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Status column
                Expanded(
                  flex: 2,
                  child: _StatusPill(status: m.subscriptionStatus),
                ),
                // Joined column
                Expanded(
                  flex: 2,
                  child: Text(
                    joinDate,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                // Actions (always visible on wide)
                SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _RowIconBtn(
                        icon: Icons.open_in_new_rounded,
                        tooltip: context.l10n.tr('View profile'),
                        onTap: () => widget.onProfile(m),
                      ),
                      _RowIconBtn(
                        icon: Icons.copy_outlined,
                        tooltip: context.l10n.tr('Copy email'),
                        onTap: () => widget.onCopyEmail(m),
                      ),
                      _MemberPopupMenu(
                        member: m,
                        onProfile: widget.onProfile,
                        onCopyEmail: widget.onCopyEmail,
                        onChangeRole: widget.onChangeRole,
                        onToggleStatus: widget.onToggleStatus,
                        onDelete: widget.onDelete,
                        isWebRow: true,
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
}

class _RowIconBtn extends StatelessWidget {
  const _RowIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ── Mobile Card List ──────────────────────────────────────────────────────────

class _MobileList extends StatelessWidget {
  const _MobileList({
    required this.members,
    required this.onProfile,
    required this.onCopyEmail,
    required this.onChangeRole,
    required this.onToggleStatus,
    required this.onDelete,
  });

  final List<AppUser> members;
  final ValueChanged<AppUser> onProfile;
  final ValueChanged<AppUser> onCopyEmail;
  final ValueChanged<AppUser> onChangeRole;
  final ValueChanged<AppUser> onToggleStatus;
  final ValueChanged<AppUser> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: members.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _MemberCard(
        member: members[index],
        onProfile: onProfile,
        onCopyEmail: onCopyEmail,
        onChangeRole: onChangeRole,
        onToggleStatus: onToggleStatus,
        onDelete: onDelete,
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onProfile,
    required this.onCopyEmail,
    required this.onChangeRole,
    required this.onToggleStatus,
    required this.onDelete,
  });

  final AppUser member;
  final ValueChanged<AppUser> onProfile;
  final ValueChanged<AppUser> onCopyEmail;
  final ValueChanged<AppUser> onChangeRole;
  final ValueChanged<AppUser> onToggleStatus;
  final ValueChanged<AppUser> onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = member.displayName.isEmpty ? member.email : member.displayName;
    final initials = name[0].toUpperCase();
    final joinDate = member.joinDate != null
        ? DateFormat('d MMM yyyy').format(member.joinDate!)
        : null;

    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onProfile(member),
        child: IntrinsicHeight(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left status accent bar
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: _statusColor(member.subscriptionStatus),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Avatar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _MemberAvatar(
                    photoUrl: member.photoUrl,
                    initials: initials,
                    role: member.role,
                    radius: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        RoleBadgeRow(roles: member.effectiveRoles),
                        const SizedBox(height: 3),
                        Text(
                          member.email,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _StatusPill(status: member.subscriptionStatus),
                            if (member.fitnessLevel.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _FitnessChip(level: member.fitnessLevel),
                            ],
                            if (joinDate != null) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.calendar_today_outlined,
                                  size: 11,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.6)),
                              const SizedBox(width: 2),
                              Text(
                                joinDate,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Actions
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _MemberPopupMenu(
                    member: member,
                    onProfile: onProfile,
                    onCopyEmail: onCopyEmail,
                    onChangeRole: onChangeRole,
                    onToggleStatus: onToggleStatus,
                    onDelete: onDelete,
                    isWebRow: false,
                  ),
                ),
              ],
            ),
          ),
        ),
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
}

// ── Shared Popup Menu ─────────────────────────────────────────────────────────

enum _MemberAction {
  viewProfile,
  copyEmail,
  changeRole,
  toggleStatus,
  delete,
}

class _MemberPopupMenu extends StatelessWidget {
  const _MemberPopupMenu({
    required this.member,
    required this.onProfile,
    required this.onCopyEmail,
    required this.onChangeRole,
    required this.onToggleStatus,
    required this.onDelete,
    required this.isWebRow,
  });

  final AppUser member;
  final ValueChanged<AppUser> onProfile;
  final ValueChanged<AppUser> onCopyEmail;
  final ValueChanged<AppUser> onChangeRole;
  final ValueChanged<AppUser> onToggleStatus;
  final ValueChanged<AppUser> onDelete;
  final bool isWebRow;

  @override
  Widget build(BuildContext context) {
    final isActive = member.subscriptionStatus == 'active';
    final isPaused = member.subscriptionStatus == 'paused';
    final canToggle = isActive || isPaused;

    return PopupMenuButton<_MemberAction>(
      tooltip: context.l10n.tr('More actions'),
      icon: const Icon(Icons.more_vert_rounded),
      iconSize: 18,
      offset: const Offset(0, 40),
      onSelected: (action) {
        switch (action) {
          case _MemberAction.viewProfile:
            onProfile(member);
          case _MemberAction.copyEmail:
            onCopyEmail(member);
          case _MemberAction.changeRole:
            onChangeRole(member);
          case _MemberAction.toggleStatus:
            onToggleStatus(member);
          case _MemberAction.delete:
            onDelete(member);
        }
      },
      itemBuilder: (_) => [
        if (!isWebRow)
          PopupMenuItem(
            value: _MemberAction.viewProfile,
            child: _PopupItem(
              icon: Icons.person_outline_rounded,
              label: context.l10n.tr('View Profile'),
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        PopupMenuItem(
          value: _MemberAction.copyEmail,
          child: _PopupItem(
            icon: Icons.copy_outlined,
            label: context.l10n.tr('Copy Email'),
          ),
        ),
        PopupMenuItem(
          value: _MemberAction.changeRole,
          child: _PopupItem(
            icon: Icons.manage_accounts_outlined,
            label: context.l10n.tr('Change Role'),
          ),
        ),
        if (canToggle)
          PopupMenuItem(
            value: _MemberAction.toggleStatus,
            child: _PopupItem(
              icon: isActive
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              label: isActive ? context.l10n.tr('Pause Membership') : context.l10n.tr('Activate Membership'),
              color: isActive ? Colors.orange.shade700 : Colors.green.shade700,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _MemberAction.delete,
          child: _PopupItem(
            icon: Icons.delete_outline_rounded,
            label: context.l10n.tr('Delete Member'),
            color: Colors.red,
          ),
        ),
      ],
    );
  }
}

class _PopupItem extends StatelessWidget {
  const _PopupItem({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: c, fontSize: 14)),
      ],
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.photoUrl,
    required this.initials,
    required this.role,
    required this.radius,
  });

  final String photoUrl;
  final String initials;
  final String role;
  final double radius;

  Color _roleColor() {
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

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      photoUrl: photoUrl,
      initials: initials,
      color: _roleColor(),
      radius: radius,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    switch (status) {
      case 'active':
        color = Colors.green.shade600;
        icon = Icons.check_circle_rounded;
      case 'paused':
        color = Colors.orange.shade600;
        icon = Icons.pause_circle_rounded;
      case 'cancelled':
        color = Colors.red.shade600;
        icon = Icons.cancel_rounded;
      default:
        color = Colors.grey.shade500;
        icon = Icons.remove_circle_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            status == 'none'
                ? context.l10n.tr('No plan')
                : context.l10n.tr(status[0].toUpperCase() + status.substring(1)),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FitnessChip extends StatelessWidget {
  const _FitnessChip({required this.level});

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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        level.toUpperCase(),
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
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
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch});

  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearch ? Icons.search_off_rounded : Icons.people_outline,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              hasSearch ? context.l10n.tr('No members match your search.') : context.l10n.tr('No members yet.'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Role helpers (shared) ─────────────────────────────────────────────────────

String _roleLabel(BuildContext context, String r) {
  switch (r) {
    case 'admin':
      return context.l10n.tr('Admin');
    case 'owner':
      return context.l10n.tr('Owner');
    case 'staff':
      return context.l10n.tr('Staff');
    case 'coach':
      return context.l10n.tr('Coach');
    default:
      return context.l10n.tr('Member');
  }
}

IconData _roleIcon(String r) {
  switch (r) {
    case 'admin':
    case 'owner':
      return Icons.shield_outlined;
    case 'staff':
      return Icons.badge_outlined;
    case 'coach':
      return Icons.sports_martial_arts_outlined;
    default:
      return Icons.person_outline;
  }
}

Color _roleColor(String r) {
  switch (r) {
    case 'admin':
    case 'owner':
      return const Color(0xFF7C3AED);
    case 'staff':
    case 'coach':
      return const Color(0xFF0F766E);
    default:
      return const Color(0xFF2563EB);
  }
}
