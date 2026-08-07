import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gym.dart';
import '../../services/gym_service.dart';

/// Member-facing "Explore Gyms" map: shows every active, located gym as a
/// pin on an OpenStreetMap view. Tapping a pin (or the card list below the
/// map) opens a details sheet with a "Get Directions" action that hands off
/// to the device's default maps app.
class GymsMapScreen extends StatefulWidget {
  const GymsMapScreen({super.key});

  @override
  State<GymsMapScreen> createState() => _GymsMapScreenState();
}

class _GymsMapScreenState extends State<GymsMapScreen> {
  final _gymService = GymService();
  final _mapController = MapController();
  String? _selectedGymId;

  void _focusGym(Gym gym) {
    if (!gym.hasLocation) return;
    setState(() => _selectedGymId = gym.id);
    _mapController.move(LatLng(gym.latitude!, gym.longitude!), 15);
    _showGymSheet(gym);
  }

  Future<void> _getDirections(Gym gym) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${gym.latitude},${gym.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showGymSheet(Gym gym) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(gym.name,
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              if (gym.address.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 18,
                        color: Theme.of(sheetContext).colorScheme.outline),
                    const SizedBox(width: 6),
                    Expanded(child: Text(gym.address)),
                  ],
                ),
              ],
              if (gym.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(gym.description,
                    style: Theme.of(sheetContext).textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _getDirections(gym),
                icon: const Icon(Icons.directions_outlined),
                label: Text(sheetContext.l10n.tr('Get Directions')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('Explore Gyms'))),
      body: StreamBuilder<List<Gym>>(
        stream: _gymService.streamActiveGyms(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data ?? const <Gym>[];
          final located = all.where((g) => g.hasLocation).toList();
          final unlocated = all.length - located.length;

          if (located.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_outlined,
                        size: 56,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(l10n.tr('No gym locations available yet.'),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }

          final points =
              located.map((g) => LatLng(g.latitude!, g.longitude!)).toList();
          final center = points.length == 1
              ? points.first
              : LatLngBounds.fromPoints(points).center;

          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: points.length == 1 ? 14 : 6,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.fitflow.app',
                    ),
                    MarkerLayer(
                      markers: located.map((gym) {
                        final isSelected = gym.id == _selectedGymId;
                        return Marker(
                          point: LatLng(gym.latitude!, gym.longitude!),
                          width: 44,
                          height: 44,
                          child: GestureDetector(
                            onTap: () => _focusGym(gym),
                            child: Icon(
                              Icons.location_pin,
                              size: isSelected ? 44 : 36,
                              color: isSelected
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const RichAttributionWidget(attributions: [
                      TextSourceAttribution('OpenStreetMap contributors'),
                    ]),
                  ],
                ),
              ),
              if (unlocated > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  child: Text(
                    l10n
                        .tr('{count} gym(s) not yet shown on the map')
                        .replaceAll('{count}', '$unlocated'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: located.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final gym = located[i];
                    final isSelected = gym.id == _selectedGymId;
                    return _GymCard(
                      gym: gym,
                      selected: isSelected,
                      onTap: () => _focusGym(gym),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GymCard extends StatelessWidget {
  const _GymCard({
    required this.gym,
    required this.selected,
    required this.onTap,
  });

  final Gym gym;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                gym.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (gym.address.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  gym.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
