import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../team/map_options.dart';
import '../team/team_map_screen.dart'
    show MapRoundButton, MapZoomControls, mapTilesProvider;

/// « depuis 6 min », « depuis 1 h 05 ».
String _since(DateTime since) {
  final minutes = DateTime.now().difference(since).inMinutes.clamp(1, 1 << 20);
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

/// Carte de la zone du jour : contours et position de l'agent (tuiles OpenStreetMap).
class ZoneMap extends ConsumerWidget {
  const ZoneMap({
    super.key,
    required this.zone,
    required this.position,
    required this.accuracy,
    required this.outside,
    this.interactive = false,
    this.controller,
    this.onReady,
  });

  static const minZoom = 4.0;
  static const maxZoom = 19.0;

  /// Carte prête : le zoom par boutons devient possible.

  final Zone zone;
  final LatLng? position;
  final double? accuracy;
  final bool outside;
  final bool interactive;
  final MapController? controller;
  final VoidCallback? onReady;

  /// Marge du cadrage initial.
  double get _padding => interactive ? 64 : 28;

  /// Cadre : la zone, et l'agent s'il est dehors.
  static CameraFit fitFor(Zone zone, LatLng? position, {double padding = 28}) =>
      CameraFit.coordinates(
        coordinates: [...zone.area.expand((r) => r), ?position],
        padding: EdgeInsets.all(padding),
        maxZoom: 17,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final zoneColor = outside
        ? toneColor(context, Tone.danger)
        : scheme.primary;
    // Style choisi dans « Carte » (le même que la carte de l'équipe).
    final style = ref
        .watch(mapPrefsProvider)
        .styleFor(Theme.of(context).brightness);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCameraFit: fitFor(zone, position, padding: _padding),
        minZoom: minZoom,
        maxZoom: maxZoom,
        onMapReady: onReady,
        backgroundColor: scheme.surfaceContainerHighest,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        if (ref.watch(mapTilesProvider))
          TileLayer(
            urlTemplate: style.url,
            subdomains: const ['a', 'b', 'c'],
            tileBuilder: style.tileBuilder,
            // Exigé par la politique d'usage des tuiles OpenStreetMap.
            userAgentPackageName: 'ci.suiviagent.app',
          ),
        PolygonLayer(
          polygons: [
            for (final ring in zone.area)
              Polygon(
                points: ring,
                color: zoneColor.withValues(alpha: 0.1),
                borderColor: zoneColor.withValues(alpha: 0.85),
                borderStrokeWidth: 2,
              ),
          ],
        ),
        if (position != null) ...[
          if (accuracy != null && accuracy! > 15)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: position!,
                  radius: accuracy!,
                  useRadiusInMeter: true,
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderColor: scheme.primary.withValues(alpha: 0.3),
                  borderStrokeWidth: 1,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              Marker(
                point: position!,
                width: 22,
                height: 22,
                child: const _MeDot(),
              ),
            ],
          ),
        ],
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              style.attribution,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

/// Bandeau en haut de « Ma journée » quand l'agent est hors de sa zone.
class OutsideZoneBanner extends ConsumerWidget {
  const OutsideZoneBanner({super.key, this.overMap = false});

  /// Posé sur la carte : fond opaque et ombre, sans lien vers la carte.
  final bool overMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guard = ref.watch(zoneGuardProvider);
    final since = guard.outsideSince;
    final zone = guard.zone;
    if (since == null || zone == null) return const SizedBox.shrink();
    final distance = guard.distance;
    final banner = InfoBanner(
      icon: Icons.wrong_location_rounded,
      tone: Tone.danger,
      message:
          'Hors de ${zone.name} depuis ${_since(since)}'
          '${distance == null ? '' : ', à ${formatMeters(distance)}'}. '
          '${guard.leadWarned ? 'Votre responsable a été prévenu.' : 'Votre responsable sera prévenu au-delà de ${guard.alertMinutes} min.'}',
      action: overMap
          ? null
          : TextButton(
              onPressed: () => context.push('/day/zone'),
              child: const Text('Voir'),
            ),
    );
    if (overMap) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: banner,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: banner,
    );
  }
}

/// « Ma zone » : mini-carte et état, sur l'écran de la journée.
class ZoneCard extends ConsumerStatefulWidget {
  const ZoneCard({super.key});

  @override
  ConsumerState<ZoneCard> createState() => _ZoneCardState();
}

class _ZoneCardState extends ConsumerState<ZoneCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // « depuis X min » avance sans nouvelle position.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guard = ref.watch(zoneGuardProvider);
    final zone = guard.zone;
    if (zone == null || zone.area.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (String label, Tone tone, IconData icon) = guard.position == null
        ? (
            'Position en attente',
            Tone.neutral,
            Icons.location_searching_rounded,
          )
        : guard.isOutside
        ? (
            'Hors zone depuis ${_since(guard.outsideSince!)}',
            Tone.danger,
            Icons.wrong_location_rounded,
          )
        : ('Dans votre zone', Tone.success, Icons.where_to_vote_rounded);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Ma zone'),
        SurfaceCard(
          padding: EdgeInsets.zero,
          onTap: () => context.push('/day/zone'),
          semanticLabel: 'Ma zone, ${zone.name} : $label. Ouvrir la carte',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 170,
                child: IgnorePointer(
                  child: ZoneMap(
                    // Recadre quand l'agent sort ou revient.
                    key: ValueKey(guard.isOutside),
                    zone: zone,
                    position: guard.position,
                    accuracy: guard.accuracy,
                    outside: guard.isOutside,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.md,
                  Space.md,
                  Space.md,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: toneColor(context, tone)),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(zone.name, style: text.bodyLarge?.medium),
                          Text(
                            label,
                            style: text.bodySmall?.copyWith(
                              color: tone == Tone.neutral
                                  ? scheme.onSurfaceVariant
                                  : toneColor(context, tone),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Carte plein écran de la zone du jour, avec recentrage.
class MyZoneScreen extends ConsumerStatefulWidget {
  const MyZoneScreen({super.key});

  @override
  ConsumerState<MyZoneScreen> createState() => _MyZoneScreenState();
}

class _MyZoneScreenState extends ConsumerState<MyZoneScreen> {
  final _map = MapController();
  var _ready = false;

  /// Boutons + et − : un niveau de zoom, autour du centre de la carte.
  void _zoom(double delta) {
    if (!_ready) return;
    HapticFeedback.selectionClick();
    final camera = _map.camera;
    _map.move(
      camera.center,
      (camera.zoom + delta).clamp(ZoneMap.minZoom, ZoneMap.maxZoom).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guard = ref.watch(zoneGuardProvider);
    final zone = guard.zone;
    return Scaffold(
      appBar: AppBar(title: Text(zone?.name ?? 'Ma zone')),
      body: zone == null || zone.area.isEmpty
          ? const Center(child: Text('Aucune zone pour aujourd’hui'))
          : Stack(
              children: [
                ZoneMap(
                  controller: _map,
                  zone: zone,
                  position: guard.position,
                  accuracy: guard.accuracy,
                  outside: guard.isOutside,
                  interactive: true,
                  onReady: () => _ready = true,
                ),
                Positioned(
                  left: Space.page,
                  right: Space.page,
                  top: Space.md,
                  child: const OutsideZoneBanner(overMap: true),
                ),
                Positioned(
                  right: Space.page,
                  bottom: Space.xxl + MediaQuery.paddingOf(context).bottom,
                  child: Column(
                    children: [
                      MapRoundButton(
                        icon: Icons.my_location_rounded,
                        label: 'Recentrer',
                        onTap: () => _map.fitCamera(
                          ZoneMap.fitFor(zone, guard.position, padding: 64),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      MapZoomControls(onZoom: _zoom),
                      const SizedBox(height: Space.sm),
                      MapRoundButton(
                        icon: Icons.layers_outlined,
                        label: 'Style de la carte',
                        onTap: () => showMapOptions(context, layers: false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
