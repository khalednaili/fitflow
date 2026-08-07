import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/gym.dart';
import '../../services/gym_service.dart';
import '../../services/member_service.dart';

/// Member-facing "My Gyms" screen: lists all gyms the member belongs to
/// (multi-gym membership), sorted by distance from the device's current
/// location when available, lets them switch which gym is "active"
/// (drives classes/bookings/products elsewhere in the app), join another
/// gym, or leave a gym they no longer attend.
class MyGymsScreen extends StatefulWidget {
  const MyGymsScreen({super.key});

  @override
  State<MyGymsScreen> createState() => _MyGymsScreenState();
}

class _MyGymsScreenState extends State<MyGymsScreen> {
  final _gymService = GymService();
  final _memberService = MemberService();

  Position? _position;
  bool _locationRequested = false;
  String? _busyGymId;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final pos = await _gymService.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _position = pos;
      _locationRequested = true;
    });
  }

  List<Gym> _sorted(List<Gym> gyms) {
    if (_position == null) return gyms;
    return GymService.sortByDistance(
        gyms, _position!.latitude, _position!.longitude);
  }

  String? _distanceLabel(Gym gym) {
    if (_position == null || !gym.hasLocation) return null;
    final km = GymService.distanceKm(
        _position!.latitude, _position!.longitude, gym.latitude!, gym.longitude!);
    return km < 1
        ? '${(km * 1000).round()} m'
        : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  Future<void> _switchActive(AppUser user, Gym gym) async {
    setState(() => _busyGymId = gym.id);
    try {
      await _memberService.switchActiveGym(userId: user.id, gymId: gym.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .tr('Switched active gym to {name}')
                  .replaceAll('{name}', gym.name))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyGymId = null);
    }
  }

  Future<void> _leave(AppUser user, Gym gym) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.tr('Leave Gym')),
        content: Text(dialogContext.l10n
            .tr('Are you sure you want to leave {name}?')
            .replaceAll('{name}', gym.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(dialogContext.l10n.tr('Leave')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyGymId = gym.id);
    try {
      await _memberService.leaveGym(userId: user.id, gymId: gym.id);
    } finally {
      if (mounted) setState(() => _busyGymId = null);
    }
  }

  Future<void> _joinAnotherGym(AppUser user, List<Gym> alreadyJoined) async {
    final joinedIds = alreadyJoined.map((g) => g.id).toSet();
    final all = await _gymService.streamActiveGyms().first;
    final candidates = _sorted(all.where((g) => !joinedIds.contains(g.id)).toList());

    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('No other gyms available yet.'))),
      );
      return;
    }

    final selected = await showModalBottomSheet<Gym>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(sheetContext.l10n.tr('Join Another Gym'),
                    style: Theme.of(sheetContext).textTheme.titleLarge),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final gym = candidates[i];
                    final distance = _distanceLabel(gym);
                    return ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      tileColor:
                          Theme.of(context).colorScheme.surfaceContainerLowest,
                      title: Text(gym.name),
                      subtitle: gym.address.isNotEmpty
                          ? Text(gym.address, maxLines: 1, overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: distance != null ? Text(distance) : null,
                      onTap: () => Navigator.pop(context, gym),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected == null) return;

    setState(() => _busyGymId = selected.id);
    try {
      await _memberService.joinAdditionalGym(userId: user.id, gymId: selected.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .tr('Joined {name}')
                  .replaceAll('{name}', selected.name))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyGymId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('My Gyms'))),
      body: StreamBuilder<AppUser?>(
        stream: _memberService.streamUser(uid),
        builder: (context, userSnap) {
          final user = userSnap.data;
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return FutureBuilder<List<Gym>>(
            future: _gymService.getGymsByIds(user.effectiveGymIds),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final gyms = _sorted(snap.data ?? const <Gym>[]);

              return RefreshIndicator(
                onRefresh: _loadLocation,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    if (!_locationRequested)
                      const LinearProgressIndicator(minHeight: 2),
                    if (_locationRequested && _position == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          l10n.tr(
                              'Enable location access to sort gyms by distance.'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.outline),
                        ),
                      ),
                    if (gyms.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: Text(l10n.tr("You haven't joined any gyms yet.")),
                        ),
                      )
                    else
                      ...gyms.map((gym) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _GymMembershipCard(
                              gym: gym,
                              isActive: gym.id == user.gymId,
                              isBusy: _busyGymId == gym.id,
                              distanceLabel: _distanceLabel(gym),
                              canLeave: gyms.length > 1,
                              onSwitch: () => _switchActive(user, gym),
                              onLeave: () => _leave(user, gym),
                            ),
                          )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _joinAnotherGym(user, gyms),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.tr('Join Another Gym')),
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
}

class _GymMembershipCard extends StatelessWidget {
  const _GymMembershipCard({
    required this.gym,
    required this.isActive,
    required this.isBusy,
    required this.distanceLabel,
    required this.canLeave,
    required this.onSwitch,
    required this.onLeave,
  });

  final Gym gym;
  final bool isActive;
  final bool isBusy;
  final String? distanceLabel;
  final bool canLeave;
  final VoidCallback onSwitch;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: isActive
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.6),
            width: isActive ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    gym.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l10n.tr('Active'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer),
                    ),
                  ),
              ],
            ),
            if (gym.address.isNotEmpty || distanceLabel != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      gym.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                  if (distanceLabel != null)
                    Text(distanceLabel!,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (!isActive)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isBusy ? null : onSwitch,
                      child: isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(l10n.tr('Set Active')),
                    ),
                  ),
                if (!isActive && canLeave) const SizedBox(width: 10),
                if (canLeave)
                  Expanded(
                    child: TextButton(
                      onPressed: isBusy ? null : onLeave,
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: Text(l10n.tr('Leave')),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
