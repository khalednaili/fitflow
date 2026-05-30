import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../../models/gym.dart';
import '../../services/gym_service.dart';
import 'create_gym_screen.dart';
import '../../l10n/app_localizations.dart';

class GymsListScreen extends StatelessWidget {
  const GymsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('Gyms')),
        actions: [
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const CreateGymScreen()),
            ),
            icon: Icon(Icons.add),
            label: Text(context.l10n.tr('New Gym')),
          ),
          SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('gyms')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('${context.l10n.tr('Error')}: ${snapshot.error}'),
            );
          }

          final gyms = snapshot.data?.docs.map(Gym.fromSnapshot).toList() ?? [];

          if (gyms.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fitness_center_outlined,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(context.l10n.tr('No gyms yet')),
                  SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const CreateGymScreen()),
                    ),
                    icon: Icon(Icons.add),
                    label: Text(context.l10n.tr('Create First Gym')),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.all(16),
            itemCount: gyms.length,
            separatorBuilder: (_, __) => SizedBox(height: 8),
            itemBuilder: (context, i) => _GymCard(gym: gyms[i]),
          );
        },
      ),
    );
  }
}

class _GymCard extends StatefulWidget {
  const _GymCard({required this.gym});

  final Gym gym;

  @override
  State<_GymCard> createState() => _GymCardState();
}

class _GymCardState extends State<_GymCard> {
  bool _deleting = false;

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.tr('Delete Gym')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(
                      text: context.l10n.tr('This will permanently delete ')),
                  TextSpan(
                    text: widget.gym.name,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: context.l10n.tr(
                      ' and ALL related data including members, classes, bookings, subscriptions, and their login accounts.',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(
              l10n.tr('This action cannot be undone.'),
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.l10n.tr('Delete Everything')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // ignore: use_build_context_synchronously
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('superAdminDeleteGym');
      await callable.call(<String, dynamic>{'gymId': widget.gym.id});
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.tr('"${widget.gym.name}" deleted successfully.'),
            ),
          ),
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'deleteGym');
      if (mounted) {
        setState(() => _deleting = false);
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('${l10n.tr('Error')}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            widget.gym.name.isNotEmpty ? widget.gym.name[0].toUpperCase() : '?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(widget.gym.name,
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.gym.adminEmail),
            if (widget.gym.address.isNotEmpty)
              Text(widget.gym.address,
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusChip(status: widget.gym.status),
            SizedBox(width: 4),
            if (_deleting)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              PopupMenuButton<_GymAction>(
                icon: Icon(Icons.more_vert),
                onSelected: (action) {
                  if (action == _GymAction.delete) {
                    _confirmDelete(context);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _GymAction.delete,
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever_outlined,
                            color: Colors.red, size: 20),
                        SizedBox(width: 10),
                        Text(context.l10n.tr('Delete gym'),
                            style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        onTap: _deleting
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => GymDetailScreen(gym: widget.gym)),
                ),
      ),
    );
  }
}

enum _GymAction { delete }

// ---------------------------------------------------------------------------
// Gym Detail Screen
// ---------------------------------------------------------------------------
class GymDetailScreen extends StatefulWidget {
  const GymDetailScreen({super.key, required this.gym});

  final Gym gym;

  @override
  State<GymDetailScreen> createState() => _GymDetailScreenState();
}

class _GymDetailScreenState extends State<GymDetailScreen> {
  late Gym _gym;
  bool _toggling = false;
  final _gymService = GymService();

  @override
  void initState() {
    super.initState();
    _gym = widget.gym;
  }

  Future<void> _toggleStatus() async {
    final newStatus = _gym.isActive ? 'suspended' : 'active';
    final actionLabel = context.l10n.tr(_gym.isActive ? 'Suspend' : 'Activate');
    final dialogTitle = context.l10n.tr(
      _gym.isActive ? 'Suspend Gym' : 'Activate Gym',
    );
    final dialogMessage = context.l10n.tr(
      _gym.isActive
          ? 'Are you sure you want to suspend "${_gym.name}"?'
          : 'Are you sure you want to activate "${_gym.name}"?',
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(dialogTitle),
        content: Text(dialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: _gym.isActive
                ? FilledButton.styleFrom(backgroundColor: Colors.orange)
                : null,
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _toggling = true);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('superAdminToggleGymStatus');
      await callable.call(<String, dynamic>{
        'gymId': _gym.id,
        'status': newStatus,
      });
      final updated = await _gymService.getGym(_gym.id);
      if (updated != null && mounted) {
        setState(() {
          _gym = updated;
          _toggling = false;
        });
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'toggleGymStatus');
      if (mounted) {
        setState(() => _toggling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.tr('Error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_gym.name),
        actions: [
          if (_toggling)
            Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton.icon(
              icon: Icon(_gym.isActive ? Icons.pause : Icons.play_arrow),
              label: Text(
                context.l10n.tr(_gym.isActive ? 'Suspend' : 'Activate'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: _gym.isActive ? Colors.orange : Colors.green,
              ),
              onPressed: _toggleStatus,
            ),
          SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionCard(
              title: context.l10n.tr('Gym Information'),
              children: [
                _InfoRow(label: context.l10n.tr('Name'), value: _gym.name),
                _InfoRow(
                  label: context.l10n.tr('Status'),
                  child: _StatusChip(status: _gym.status),
                ),
                if (_gym.address.isNotEmpty)
                  _InfoRow(
                    label: context.l10n.tr('Address'),
                    value: _gym.address,
                  ),
                if (_gym.description.isNotEmpty)
                  _InfoRow(
                    label: context.l10n.tr('Description'),
                    value: _gym.description,
                  ),
                _InfoRow(
                  label: context.l10n.tr('Created'),
                  value:
                      '${_gym.createdAt.day}/${_gym.createdAt.month}/${_gym.createdAt.year}',
                ),
              ],
            ),
            SizedBox(height: 16),
            _SectionCard(
              title: context.l10n.tr('Admin Account'),
              children: [
                _InfoRow(
                    label: context.l10n.tr('Email'), value: _gym.adminEmail),
                _InfoRow(label: context.l10n.tr('UID'), value: _gym.adminUid),
              ],
            ),
            SizedBox(height: 16),
            _GymStatsCard(gymId: _gym.id),
          ],
        ),
      ),
    );
  }
}

class _GymStatsCard extends StatelessWidget {
  const _GymStatsCard({required this.gymId});
  final String gymId;

  @override
  Widget build(BuildContext context) {
    final gymService = GymService();
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.tr('Statistics'),
                style: Theme.of(context).textTheme.titleMedium),
            Divider(height: 24),
            FutureBuilder<List<int>>(
              future: Future.wait([
                gymService.getMemberCount(gymId),
                gymService.getClassCount(gymId),
              ]),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                final memberCount = snap.data?[0] ?? 0;
                final classCount = snap.data?[1] ?? 0;
                return Row(
                  children: [
                    _StatTile(
                        icon: Icons.people,
                        label: context.l10n.tr('Members'),
                        value: '$memberCount'),
                    SizedBox(width: 24),
                    _StatTile(
                        icon: Icons.event,
                        label: context.l10n.tr('Classes'),
                        value: '$classCount'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, this.value, this.child});
  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style:
                    TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: child ??
                Text(value ?? '',
                    style: TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

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
