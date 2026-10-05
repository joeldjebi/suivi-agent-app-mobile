import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import 'alerts_screen.dart' show alertLabelOf;
import 'map_options.dart';
import 'team_controller.dart';

/// Fonds de carte chargés depuis Internet (désactivés dans les tests).
final mapTilesProvider = Provider<bool>((ref) => true);

/// Itinéraire d'une journée, chargé à la demande.
final trackProvider = FutureProvider.autoDispose
    .family<List<TrackPoint>, String>(
      (ref, dayId) => ref.read(repositoryProvider).track(dayId),
    );

const _abidjan = LatLng(5.345, -4.024);

/// OpenStreetMap fournit les tuiles jusqu'au niveau 19.
const _minZoom = 4.0;
const _maxZoom = 19.0;

/// Couleur d'un agent sur la carte : alerte, pause ou en journée.
Color agentColor(BuildContext context, LiveAgent a) => a.hasAlert
    ? toneColor(context, Tone.danger)
    : a.status == DayStatus.paused
    ? toneColor(context, Tone.warning)
    : toneColor(context, Tone.success);

String agentAlert(LiveAgent a) => a.isMocked
    ? 'Position simulée'
    : a.signalLost
    ? 'Signal perdu'
    : a.outsideZone
    ? outsideLabel(a)
    : a.alerts.isNotEmpty
    ? alertLabelOf(a.alerts.first)
    : a.status == DayStatus.paused
    ? 'En pause'
    : 'En journée';

String _initials(String name) => name
    .split(' ')
    .where((p) => p.isNotEmpty)
    .take(2)
    .map((p) => p[0].toUpperCase())
    .join();

/// Chef d'équipe : ses agents en direct sur la carte, ses zones, l'itinéraire du jour.
class TeamMapScreen extends ConsumerStatefulWidget {
  const TeamMapScreen({super.key, this.agentId});

  /// Agent à sélectionner à l'ouverture (depuis la fiche de l'équipe).
  final String? agentId;

  @override
  ConsumerState<TeamMapScreen> createState() => _TeamMapScreenState();
}

class _TeamMapScreenState extends ConsumerState<TeamMapScreen> {
  final _map = MapController();
  final _sheet = DraggableScrollableController();
  String? _selected;
  bool _route = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.agentId;
  }

  @override
  void didUpdateWidget(TeamMapScreen old) {
    super.didUpdateWidget(old);
    if (widget.agentId != null && widget.agentId != old.agentId) {
      final team = ref.read(teamProvider).value;
      final agent = team?.live
          .where((a) => a.agentId == widget.agentId)
          .firstOrNull;
      if (agent != null) _select(agent);
    }
  }

  @override
  void dispose() {
    _map.dispose();
    _sheet.dispose();
    super.dispose();
  }

  List<LatLng> _allPoints(TeamOverview t) => [
    for (final z in t.zones) ...z.area.expand((r) => r),
    for (final a in t.live)
      if (a.position != null) a.position!,
  ];

  CameraFit? _fit(List<LatLng> points) {
    if (points.isEmpty) return null;
    if (points.length == 1) return null;
    return CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(36, 120, 36, 290),
      maxZoom: 16,
    );
  }

  void _recenter(TeamOverview t) {
    if (!_ready) return;
    HapticFeedback.selectionClick();
    final fit = _fit(_allPoints(t));
    if (fit != null) {
      _map.fitCamera(fit);
    } else {
      _map.move(_allPoints(t).firstOrNull ?? _abidjan, 14);
    }
  }

  /// Boutons + et − : un niveau de zoom, autour du centre de la carte.
  void _zoom(double delta) {
    if (!_ready) return;
    HapticFeedback.selectionClick();
    final camera = _map.camera;
    _map.move(
      camera.center,
      (camera.zoom + delta).clamp(_minZoom, _maxZoom).toDouble(),
    );
  }

  void _select(LiveAgent a) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = a.agentId;
      _route = false;
    });
    if (_ready && a.position != null) {
      _map.move(a.position!, 16);
    }
    if (_sheet.isAttached) {
      _sheet.animateTo(
        0.34,
        duration: Motion.of(context, Motion.medium),
        curve: Motion.curve,
      );
    }
  }

  void _close() => setState(() {
    _selected = null;
    _route = false;
  });

  void _showRoute(List<TrackPoint> track) {
    if (!_ready || track.isEmpty) return;
    final points = [for (final p in track) p.position];
    if (points.length > 1) {
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(48, 140, 48, 320),
          maxZoom: 17,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamProvider);
    final prefs = ref.watch(mapPrefsProvider);
    final style = prefs.styleFor(Theme.of(context).brightness);
    final scheme = Theme.of(context).colorScheme;

    // Heure et icônes du téléphone lisibles sur la carte : claires sur le style sombre.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style == MapStyle.sombre
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: team.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.page),
              child: InfoBanner(
                icon: Icons.wifi_off_rounded,
                message: ApiException.from(e).message,
                action: TextButton(
                  onPressed: () => ref.invalidate(teamProvider),
                  child: const Text('Réessayer'),
                ),
              ),
            ),
          ),
          data: (t) {
            final selected = t.live
                .where((a) => a.agentId == _selected)
                .firstOrNull;
            final track = selected != null && _route
                ? ref.watch(trackProvider(selected.dayId))
                : null;
            final points = _allPoints(t);
            final fit = _fit(points);
            // « Alertes seulement » : l'agent sélectionné reste visible.
            final shown = prefs.alertsOnly
                ? t.live
                      .where((a) => a.hasAlert || a.agentId == _selected)
                      .toList()
                : t.live;

            return Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter:
                        selected?.position ?? points.firstOrNull ?? _abidjan,
                    initialZoom: selected != null || points.length == 1
                        ? 15
                        : 12,
                    minZoom: _minZoom,
                    maxZoom: _maxZoom,
                    initialCameraFit: selected == null ? fit : null,
                    backgroundColor: scheme.surfaceContainerHighest,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onMapReady: () => _ready = true,
                    onTap: (_, _) {
                      if (_selected != null) _close();
                    },
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
                    if (prefs.showZones) ...[
                      PolygonLayer(
                        polygons: [
                          for (final z in t.zones)
                            for (final ring in z.area)
                              Polygon(
                                points: ring,
                                color: scheme.primary.withValues(alpha: 0.08),
                                borderColor: scheme.primary.withValues(
                                  alpha: 0.7,
                                ),
                                borderStrokeWidth: 1.5,
                              ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          for (final z in t.zones)
                            if (z.top != null)
                              Marker(
                                point: z.top!,
                                width: 120,
                                height: 26,
                                alignment: Alignment.topCenter,
                                child: IgnorePointer(child: _ZoneLabel(z.name)),
                              ),
                        ],
                      ),
                    ],
                    if (track?.value case final points?
                        when points.length > 1) ...[
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [for (final p in points) p.position],
                            color: scheme.primary,
                            strokeWidth: 4,
                            borderColor: Colors.white,
                            borderStrokeWidth: 1.5,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: points.first.position,
                            width: 16,
                            height: 16,
                            child: const _StartDot(),
                          ),
                        ],
                      ),
                    ],
                    if (prefs.showNames)
                      MarkerLayer(
                        markers: [
                          for (final a in shown)
                            if (a.position != null)
                              Marker(
                                point: a.position!,
                                width: 130,
                                height: 50,
                                // Sous la pastille : le haut de l'étiquette est au point.
                                alignment: Alignment.bottomCenter,
                                child: IgnorePointer(
                                  child: _NameLabel(a.name.split(' ').first),
                                ),
                              ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final a in shown)
                          if (a.position != null)
                            Marker(
                              point: a.position!,
                              width: 52,
                              height: 52,
                              child: _AgentPin(
                                agent: a,
                                selected: a.agentId == _selected,
                                onTap: () => _select(a),
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
                _TopBar(
                  team: t,
                  attribution: style.attribution,
                  onRecenter: () => _recenter(t),
                  onZoom: _zoom,
                  onOptions: () => showMapOptions(context),
                ),
                DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: selected != null ? 0.34 : 0.3,
                  minChildSize: 0.12,
                  maxChildSize: 0.85,
                  snap: true,
                  snapSizes: const [0.3, 0.6],
                  builder: (context, scroll) => _Sheet(
                    scroll: scroll,
                    child: selected == null
                        ? _AgentList(
                            team: t,
                            alertsOnly: prefs.alertsOnly,
                            onSelect: _select,
                          )
                        : _AgentDetail(
                            agent: selected,
                            team: t,
                            showRoute: _route,
                            track: track,
                            onClose: _close,
                            onToggleRoute: () {
                              setState(() => _route = !_route);
                              if (_route) {
                                // Recadrage sur le trajet dès qu'il est chargé.
                                ref
                                    .read(trackProvider(selected.dayId).future)
                                    .then((track) {
                                      if (mounted && _route) _showRoute(track);
                                    }, onError: (_) {});
                              } else if (selected.position != null && _ready) {
                                _map.move(selected.position!, 16);
                              }
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// En haut : nombre d'agents en journée, alertes, bouton pour tout voir.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.team,
    required this.attribution,
    required this.onRecenter,
    required this.onZoom,
    required this.onOptions,
  });

  final TeamOverview team;
  final String attribution;
  final VoidCallback onRecenter;
  final ValueChanged<double> onZoom;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final alerts = team.alerts.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SurfaceCard(
                    radius: Radii.pill,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LiveDot(color: toneColor(context, Tone.success)),
                        const SizedBox(width: Space.sm),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              text: '${team.live.length} en journée',
                              children: [
                                if (alerts > 0) ...[
                                  TextSpan(
                                    text: '  ·  ',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        '$alerts alerte${alerts > 1 ? 's' : ''}',
                                    style: TextStyle(
                                      color: toneColor(context, Tone.danger),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            style: text.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: Space.sm),
                    child: Text(
                      attribution,
                      style: text.labelSmall?.copyWith(
                        fontSize: 9.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.md),
            Column(
              children: [
                MapRoundButton(
                  icon: Icons.zoom_out_map_rounded,
                  label: 'Voir toute l’équipe',
                  onTap: onRecenter,
                ),
                const SizedBox(height: Space.sm),
                MapZoomControls(onZoom: onZoom),
                const SizedBox(height: Space.sm),
                MapRoundButton(
                  icon: Icons.layers_outlined,
                  label: 'Style et options de la carte',
                  onTap: onOptions,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Feuille du bas : poignée, coins arrondis, contenu défilant.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.scroll, required this.child});

  final ScrollController scroll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          Space.sm,
          Space.page,
          Space.xxl,
        ),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          child,
        ],
      ),
    );
  }
}

class _AgentList extends StatelessWidget {
  const _AgentList({
    required this.team,
    required this.alertsOnly,
    required this.onSelect,
  });

  final TeamOverview team;
  final bool alertsOnly;
  final ValueChanged<LiveAgent> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final agents = [...team.alerts, if (!alertsOnly) ...team.working];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          child: Text(
            alertsOnly ? 'Alertes' : 'Agents en journée',
            style: text.titleLarge,
          ),
        ),
        const SizedBox(height: Space.md),
        if (agents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            child: Text(
              alertsOnly
                  ? 'Aucune alerte : tout va bien.'
                  : 'Aucun agent en journée pour le moment.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          GroupedList(
            indent: 64,
            children: [
              for (final a in agents)
                ListRow(
                  leading: StatusAvatar(
                    initials: _initials(a.name),
                    ringColor: agentColor(context, a),
                    size: 38,
                  ),
                  title: a.name,
                  subtitle: [
                    team.zoneName(a.zoneId),
                    if (a.lastPositionAt != null) formatAgo(a.lastPositionAt!),
                  ].join(' · '),
                  trailing: a.hasAlert
                      ? Text(
                          agentAlert(a),
                          style: text.labelMedium?.copyWith(
                            color: toneColor(context, Tone.danger),
                          ),
                        )
                      : null,
                  onTap: () => onSelect(a),
                ),
            ],
          ),
      ],
    );
  }
}

class _AgentDetail extends ConsumerWidget {
  const _AgentDetail({
    required this.agent,
    required this.team,
    required this.showRoute,
    required this.track,
    required this.onClose,
    required this.onToggleRoute,
  });

  final LiveAgent agent;
  final TeamOverview team;
  final bool showRoute;
  final AsyncValue<List<TrackPoint>>? track;
  final VoidCallback onClose;
  final VoidCallback onToggleRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = agentColor(context, agent);
    final phone = team.members[agent.agentId]?.phone;

    final points = track?.value;
    final distance = points == null ? null : _distanceKm(points);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StatusAvatar(
              initials: _initials(agent.name),
              ringColor: color,
              size: 44,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(agent.name, style: text.titleLarge),
                  Text(
                    team.zoneName(agent.zoneId),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Fermer',
              excludeSemantics: true,
              child: Material(
                color: scheme.onSurface.withValues(alpha: 0.07),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClose,
                  child: SizedBox.square(
                    dimension: 30,
                    child: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        Align(
          alignment: Alignment.centerLeft,
          child: StatusPill(label: agentAlert(agent), color: color),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: showRoute ? 'Masquer le trajet' : 'Itinéraire du jour',
                icon: Icons.route_rounded,
                style: PillStyle.tonal,
                loading: showRoute && (track?.isLoading ?? false),
                onPressed: onToggleRoute,
              ),
            ),
            if (phone != null) ...[
              const SizedBox(width: Space.sm),
              Expanded(
                child: PillButton(
                  label: 'Appeler',
                  icon: Icons.call_rounded,
                  style: PillStyle.outline,
                  onPressed: () => launchUrl(
                    Uri(
                      scheme: 'tel',
                      path: phone.replaceAll(RegExp(r'[^0-9+]'), ''),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        GroupedList(
          header: 'Aujourd’hui',
          indent: Space.lg,
          children: [
            ListRow(title: 'Début', value: formatTime(agent.startedAt)),
            ListRow(
              title: 'Dernière position',
              value: agent.lastPositionAt == null
                  ? 'Aucune'
                  : formatAgo(agent.lastPositionAt!),
            ),
            if (agent.batteryLevel != null)
              ListRow(
                title: 'Batterie',
                value: '${(agent.batteryLevel! * 100).round()} %',
              ),
            if (showRoute && points != null) ...[
              ListRow(
                title: 'Distance parcourue',
                value:
                    '${distance!.toStringAsFixed(1).replaceAll('.', ',')} km',
              ),
              ListRow(title: 'Points enregistrés', value: '${points.length}'),
            ],
          ],
        ),
        if (showRoute && track?.hasError == true)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: InfoBanner(
              icon: Icons.error_outline_rounded,
              message: ApiException.from(track!.error!).message,
              tone: Tone.danger,
            ),
          ),
      ],
    );
  }
}

double _distanceKm(List<TrackPoint> points) {
  const d = Distance();
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += d.as(LengthUnit.Meter, points[i - 1].position, points[i].position);
  }
  return total / 1000;
}

/// Pastille d'un agent : initiales sur sa couleur de statut, bord blanc.
class _AgentPin extends StatelessWidget {
  const _AgentPin({
    required this.agent,
    required this.selected,
    required this.onTap,
  });

  final LiveAgent agent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 46.0 : 36.0;
    return Semantics(
      button: true,
      label: '${agent.name}, ${agentAlert(agent)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            curve: Motion.curve,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: agentColor(context, agent),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            child: Text(
              _initials(agent.name),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontSize: selected ? 15 : 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Boutons + et − empilés, séparés par un filet (style Plans).
/// Boutons + et − d'une carte.
class MapZoomControls extends StatelessWidget {
  const MapZoomControls({super.key, required this.onZoom});

  final ValueChanged<double> onZoom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String label, double delta) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onZoom(delta),
        child: SizedBox(
          width: 42,
          height: 44,
          child: Icon(icon, size: 22, color: scheme.onSurface),
        ),
      ),
    );
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(Radii.tile),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.add_rounded, 'Zoomer', 1),
          Container(width: 26, height: 0.5, color: scheme.outlineVariant),
          button(Icons.remove_rounded, 'Dézoomer', -1),
        ],
      ),
    );
  }
}

/// Bouton rond posé sur une carte (recentrer, options).
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 42,
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}

/// Prénom de l'agent sous sa pastille.
class _NameLabel extends StatelessWidget {
  const _NameLabel(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 22),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(
          name,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurface),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ZoneLabel extends StatelessWidget {
  const _ZoneLabel(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(
          name,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.primary),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _StartDot extends StatelessWidget {
  const _StartDot();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(
        color: Theme.of(context).colorScheme.primary,
        width: 4,
      ),
    ),
  );
}
