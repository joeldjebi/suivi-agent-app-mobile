import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../team/map_options.dart';
import '../team/team_map_screen.dart' show mapTilesProvider;
import 'outlet_models.dart';
import 'outlet_widgets.dart';

/// Étape de la tournée.
class RouteStop {
  RouteStop(this.outlet, this.order, this.legMeters);

  final Outlet outlet;
  final int order;

  /// Distance depuis l'étape précédente (ou le départ), à vol d'oiseau.
  final int legMeters;
}

class OutletRoute {
  OutletRoute({
    required this.start,
    required this.stops,
    required this.totalMeters,
    required this.travelMinutes,
    required this.visitMinutes,
    required this.candidates,
  });

  final LatLng start;
  final List<RouteStop> stops;
  final int totalMeters;
  final int travelMinutes;
  final int visitMinutes;

  /// Points de vente à visiter en tout (la tournée en retient les plus proches).
  final int candidates;
}

/// Pas de position : la tournée ne peut pas partir de l'agent.
class NoPositionException implements Exception {}

/// Tournée depuis la position du téléphone ; mission de visites (identifiant) ou retards ('').
final outletRouteProvider = FutureProvider.autoDispose
    .family<OutletRoute, String>((ref, missionId) async {
      final p = await ref.read(trackerProvider).freshPosition();
      if (p == null) throw NoPositionException();
      final json = await ref
          .read(repositoryProvider)
          .outletRoute(
            lat: p.latitude,
            lng: p.longitude,
            missionId: missionId.isEmpty ? null : missionId,
          );
      return OutletRoute(
        start: LatLng(p.latitude, p.longitude),
        stops: [
          for (final s in json['stops'] as List)
            RouteStop(
              Outlet.fromJson(s as Map<String, dynamic>),
              (s['order'] as num).toInt(),
              (s['legMeters'] as num).toInt(),
            ),
        ],
        totalMeters: (json['totalMeters'] as num).toInt(),
        travelMinutes: (json['travelMinutes'] as num).toInt(),
        visitMinutes: (json['visitMinutes'] as num).toInt(),
        candidates: (json['candidates'] as num).toInt(),
      );
    });

/// « 1 h 25 », « 40 min ».
String _duration(int minutes) => minutes < 60
    ? '$minutes min'
    : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

/// Google Maps : départ, 9 étapes intermédiaires au plus, arrivée (limite de Google Maps).
Uri googleMapsRoute(LatLng start, List<RouteStop> stops) {
  final shown = stops.take(10).toList();
  String at(LatLng p) => '${p.latitude},${p.longitude}';
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': at(start),
    'destination': at(shown.last.outlet.position!),
    if (shown.length > 1)
      'waypoints': shown
          .take(shown.length - 1)
          .map((s) => at(s.outlet.position!))
          .join('|'),
    'travelmode': 'walking',
  });
}

/// Ma tournée : l'ordre de visite qui raccourcit le trajet, sur la carte et en liste, avec
/// l'itinéraire à suivre dans Google Maps. Pour une mission : ce qui reste à visiter.
class RouteScreen extends ConsumerWidget {
  const RouteScreen({super.key, this.missionId});

  final String? missionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = missionId ?? '';
    final route = ref.watch(outletRouteProvider(key));
    return Scaffold(
      appBar: AppBar(title: const Text('Ma tournée')),
      body: switch (route) {
        AsyncError(:final error) => Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: error is NoPositionException
                ? Icons.location_off_outlined
                : Icons.wifi_off_rounded,
            message: error is NoPositionException
                ? 'Position introuvable : activez la localisation pour calculer la tournée.'
                : ApiException.from(error).message,
            action: TextButton(
              onPressed: () => ref.invalidate(outletRouteProvider(key)),
              child: const Text('Réessayer'),
            ),
          ),
        ),
        AsyncData(:final value) => _Route(
          route: value,
          missionId: missionId,
          onRefresh: () => ref.refresh(outletRouteProvider(key).future),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Route extends ConsumerWidget {
  const _Route({
    required this.route,
    required this.missionId,
    required this.onRefresh,
  });

  final OutletRoute route;
  final String? missionId;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (route.stops.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.page),
        child: InfoBanner(
          icon: Icons.check_circle_outline_rounded,
          tone: Tone.success,
          message: missionId == null
              ? 'Aucun point de vente en retard de visite dans vos zones. Bravo !'
              : 'Tous les points de vente de cette mission ont été visités.',
        ),
      );
    }
    final km = (route.totalMeters / 1000)
        .toStringAsFixed(1)
        .replaceAll('.', ',');
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          Space.sm,
          Space.page,
          Space.xxxl,
        ),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${route.stops.length} étape${route.stops.length > 1 ? 's' : ''} · $km km',
                  style: text.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Environ ${_duration(route.travelMinutes)} de trajet à pied et '
                  '${_duration(route.visitMinutes)} de visites',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (route.candidates > route.stops.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Les ${route.stops.length} plus proches sur ${route.candidates} à visiter.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card),
            child: SizedBox(height: 280, child: _RouteMap(route: route)),
          ),
          const SizedBox(height: Space.md),
          PillButton(
            label: 'Ouvrir l’itinéraire dans Google Maps',
            icon: Icons.navigation_rounded,
            onPressed: () => launchUrl(
              googleMapsRoute(route.start, route.stops),
              mode: LaunchMode.externalApplication,
            ),
          ),
          if (route.stops.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Google Maps affiche les 10 premières étapes.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ),
          const SizedBox(height: Space.lg),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, s) in route.stops.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 60),
                  ListTile(
                    leading: _Number(order: s.order, overdue: s.outlet.overdue),
                    title: Text(
                      s.outlet.name,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      [
                        'à ${formatDistance(s.legMeters)}',
                        ?s.outlet.category,
                        s.outlet.visitLabel,
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(
                      missionId == null
                          ? '/outlets/${s.outlet.id}'
                          : '/missions/$missionId/new?outlet=${s.outlet.id}',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Distances à vol d’oiseau : le trajet réel est un peu plus long.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Number extends StatelessWidget {
  const _Number({required this.order, required this.overdue});

  final int order;
  final bool overdue;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: overdue
          ? OutletPin.overdueColor
          : Theme.of(context).colorScheme.primary,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: Text(
      '$order',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
  );
}

class _RouteMap extends ConsumerWidget {
  const _RouteMap({required this.route});

  final OutletRoute route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final style = ref
        .watch(mapPrefsProvider)
        .styleFor(Theme.of(context).brightness);
    final path = [route.start, for (final s in route.stops) s.outlet.position!];
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: path,
          padding: const EdgeInsets.all(36),
          maxZoom: 17,
        ),
        backgroundColor: scheme.surfaceContainerHighest,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        if (ref.watch(mapTilesProvider))
          TileLayer(
            urlTemplate: style.url,
            subdomains: const ['a', 'b', 'c'],
            tileBuilder: style.tileBuilder,
            userAgentPackageName: 'ci.suiviagent.app',
          ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: path,
              strokeWidth: 4,
              color: scheme.primary.withValues(alpha: 0.75),
              pattern: StrokePattern.dashed(segments: const [10, 6]),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: route.start,
              width: 20,
              height: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
            for (final s in route.stops)
              Marker(
                point: s.outlet.position!,
                width: 30,
                height: 30,
                child: Semantics(
                  label: 'Étape ${s.order} : ${s.outlet.name}',
                  child: _Number(order: s.order, overdue: s.outlet.overdue),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
