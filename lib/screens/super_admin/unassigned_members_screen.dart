import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../../models/app_user.dart';
import '../../services/member_service.dart';
import '../../l10n/app_localizations.dart';

class UnassignedMembersScreen extends StatelessWidget {
  const UnassignedMembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('Unassigned Members')),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Tooltip(
              message: context.l10n.tr(
                'Members who registered but are not yet linked to any gym',
              ),
              child: Icon(Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: MemberService().streamUnassignedMembers(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('${context.l10n.tr('Error')}: ${snap.error}'),
            );
          }
          final members = snap.data ?? [];
          if (members.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 72, color: Colors.green.shade400),
                  SizedBox(height: 16),
                  Text(context.l10n.tr('All members are assigned!'),
                      style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 8),
                  Text(
                    context.l10n.tr('No members are currently without a gym.'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryBanner(count: members.length),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.all(16),
                  itemCount: members.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _UnassignedMemberCard(member: members[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Summary banner ────────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: cs.errorContainer.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(Icons.person_off_outlined, color: cs.error, size: 20),
          SizedBox(width: 10),
          Text(
            '$count ${context.l10n.tr(count == 1 ? 'member not assigned to any gym' : 'members not assigned to any gym')}',
            style: TextStyle(
                color: cs.onErrorContainer, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Member card ───────────────────────────────────────────────────────────────

class _UnassignedMemberCard extends StatelessWidget {
  const _UnassignedMemberCard({required this.member});
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: cs.primaryContainer,
              child: Text(_initials,
                  style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.bold)),
            ),
            SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName.isNotEmpty
                        ? member.displayName
                        : member.email,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  SizedBox(height: 2),
                  Text(member.email,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  if (joinDate != null) ...[
                    SizedBox(height: 2),
                    Text(
                      '${context.l10n.tr('Registered')} ${DateFormat.yMMMd().format(joinDate)}',
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                  if (member.role.isNotEmpty && member.role != 'member')
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(member.role,
                            style: TextStyle(
                                fontSize: 10,
                                color: cs.onTertiaryContainer,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            // Assign button
            FilledButton.tonal(
              onPressed: () => _showAssignDialog(context),
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

  void _showAssignDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AssignGymDialog(member: member),
    );
  }
}

// ── Assign gym dialog ─────────────────────────────────────────────────────────

class AssignGymDialog extends StatefulWidget {
  const AssignGymDialog({super.key, required this.member});
  final AppUser member;

  @override
  State<AssignGymDialog> createState() => _AssignGymDialogState();
}

class _AssignGymDialogState extends State<AssignGymDialog> {
  String? _selectedGymId;
  bool _saving = false;

  Future<void> _confirm() async {
    final gymId = _selectedGymId;
    if (gymId == null) return;
    setState(() => _saving = true);
    try {
      await MemberService().assignToGym(widget.member.id, gymId);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.tr(
              '${widget.member.displayName.isNotEmpty ? widget.member.displayName : widget.member.email} assigned successfully!',
            )),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'assignMemberToGym');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.tr('Error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final memberName = widget.member.displayName.isNotEmpty
        ? widget.member.displayName
        : widget.member.email;

    return AlertDialog(
      title: Text(context.l10n.tr('Assign to Gym')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Member chip
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 18, color: cs.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(memberName,
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(widget.member.email,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            Text(context.l10n.tr('Select a gym:'),
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: cs.onSurfaceVariant)),
            SizedBox(height: 10),
            // Gym list from Firestore
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('gyms')
                  .where('status', isEqualTo: 'active')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                final gyms = snap.data?.docs ?? [];
                if (gyms.isEmpty) {
                  return Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      context.l10n
                          .tr('No active gyms found. Create a gym first.'),
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  );
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: gyms.length,
                    itemBuilder: (context, i) {
                      final doc = gyms[i];
                      final name = (doc.data()['name'] as String? ?? '').trim();
                      final address =
                          (doc.data()['address'] as String? ?? '').trim();
                      final gymId = doc.id;
                      final isSelected = _selectedGymId == gymId;

                      return Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => _selectedGymId = gymId),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 150),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color:
                                    isSelected ? cs.primary : cs.outlineVariant,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: isSelected
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                  size: 20,
                                ),
                                SizedBox(width: 10),
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isSelected
                                      ? cs.primary
                                      : cs.primaryContainer,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                        color: isSelected
                                            ? cs.onPrimary
                                            : cs.onPrimaryContainer,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? cs.onPrimaryContainer
                                                  : null)),
                                      if (address.isNotEmpty)
                                        Text(address,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: cs.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(context.l10n.tr('Cancel')),
        ),
        FilledButton(
          onPressed: (_selectedGymId == null || _saving) ? null : _confirm,
          child: _saving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(context.l10n.tr('Assign')),
        ),
      ],
    );
  }
}
