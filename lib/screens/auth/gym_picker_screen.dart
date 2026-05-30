import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/gym.dart';
import '../../services/gym_service.dart';
import '../../services/member_service.dart';
import '../../l10n/app_localizations.dart';

class GymPickerScreen extends StatefulWidget {
  const GymPickerScreen({super.key});

  @override
  State<GymPickerScreen> createState() => _GymPickerScreenState();
}

class _GymPickerScreenState extends State<GymPickerScreen> {
  final _gymService = GymService();
  final _memberService = MemberService();

  late final Stream<List<Gym>> _gymsStream = _gymService.streamActiveGyms();

  String? _joiningGymId;

  Future<void> _join(Gym gym) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _joiningGymId = gym.id);
    try {
      await _memberService.joinGym(userId: user.uid, gymId: gym.id);
      // AuthGate will automatically re-route to HomeShell once gymId is set.
    } catch (e) {
      if (mounted) {
        setState(() => _joiningGymId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.tr('Could not join gym')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(context.l10n.tr('Choose Your Gym')),
        centerTitle: false,
        titleTextStyle: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            child: Text(context.l10n.tr('Sign out')),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              context.l10n.tr('Select the gym you want to join'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Gym>>(
              stream: _gymsStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: cs.error),
                          SizedBox(height: 12),
                          Text(context.l10n.tr('Failed to load gyms'),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: cs.error)),
                          SizedBox(height: 8),
                          Text(
                            snap.error.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final gyms = snap.data ?? [];

                if (gyms.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fitness_center_outlined,
                            size: 56,
                            color: cs.onSurface.withValues(alpha: 0.3)),
                        SizedBox(height: 16),
                        Text(
                          context.l10n.tr('No gyms available yet.'),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        SizedBox(height: 8),
                        Text(
                          context.l10n
                              .tr('Please contact support or try again later.'),
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: gyms.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (context, i) => _GymTile(
                    gym: gyms[i],
                    isJoining: _joiningGymId == gyms[i].id,
                    disabled: _joiningGymId != null,
                    onJoin: () => _join(gyms[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GymTile extends StatelessWidget {
  const _GymTile({
    required this.gym,
    required this.isJoining,
    required this.disabled,
    required this.onJoin,
  });

  final Gym gym;
  final bool isJoining;
  final bool disabled;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: cs.primaryContainer,
              child: Text(
                gym.name.isNotEmpty ? gym.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gym.name,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  if (gym.address.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 13,
                            color: cs.onSurface.withValues(alpha: 0.5)),
                        SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            gym.address,
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.6)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (gym.description.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(
                      gym.description,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.55)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 12),
            isJoining
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : FilledButton(
                    onPressed: disabled ? null : onJoin,
                    style: FilledButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(context.l10n.tr('Join')),
                  ),
          ],
        ),
      ),
    );
  }
}
