import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/app_localizations.dart';

/// Reusable tap-to-pick location map used in admin gym forms (create/edit).
/// Renders an OpenStreetMap view; tapping anywhere drops a pin and reports
/// the new coordinates via [onChanged]. No API key required.
class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    required this.onChanged,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final ValueChanged<LatLng> onChanged;

  /// Default map center when no location has been picked yet (Tunis).
  static const defaultCenter = LatLng(36.8065, 10.1815);

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  LatLng? _selected;
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selected = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
  }

  void _onTap(LatLng point) {
    setState(() => _selected = point);
    widget.onChanged(point);
  }

  void _clear() {
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
            ),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _selected ?? LocationPickerMap.defaultCenter,
                initialZoom: _selected != null ? 14 : 6,
                onTap: (_, point) => _onTap(point),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fitflow.app',
                ),
                if (_selected != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _selected!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_pin,
                          color: Colors.red, size: 40),
                    ),
                  ]),
                const RichAttributionWidget(attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _selected == null
                    ? context.l10n.tr('Tap the map to set the gym location')
                    : '${_selected!.latitude.toStringAsFixed(5)}, '
                        '${_selected!.longitude.toStringAsFixed(5)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_selected != null)
              TextButton(
                onPressed: _clear,
                child: Text(context.l10n.tr('Clear')),
              ),
          ],
        ),
      ],
    );
  }
}
