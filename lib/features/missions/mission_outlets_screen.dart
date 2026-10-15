import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../outlets/outlet_models.dart';
import '../outlets/outlet_widgets.dart';
import '../team/map_options.dart';
import '../team/team_map_screen.dart' show mapTilesProvider;
import 'mission_screen.dart' show visitBlocker;
import 'missions_controller.dart';

enum _Tab { todo, done }

enum _View { list, map }

/// Mission de visites : les points de vente à visiter (les plus proches d'abord) et ceux déjà
/// visités. L'agent touche un point de vente pour enregistrer sa visite.
class MissionOutletsScreen extends ConsumerStatefulWidget {
  const MissionOutletsScreen({super.key, required this.missionId});

  final String missionId;

  @override
  ConsumerState<MissionOutletsScreen> createState() =>
      _MissionOutletsScreenState();
}

class _MissionOutletsScreenState extends ConsumerState<MissionOutletsScreen> {
  _Tab _tab = _Tab.todo;
  _View _view = _View.list;

  @override
  Widget build(BuildContext context) {
    final mission = ref.watch(missionProvider(widget.missionId)).value;
    final outlets = ref.watch(missionOutletsProvider(widget.missionId));
    final leader = ref.watch(meProvider).isTeamLead;
    final all = outlets.value ?? const <MissionOutlet>[];
    final todo = all.where((o) => !o.visited).toList();
    final done = all.where((o) => o.visited).toList();
    final shown = _tab == _Tab.todo ? todo : done;
    // Ce qui empêche l'agent d'enregistrer une visite (journée, zone, mission close).
    final blocker = leader || mission == null
        ? null
        : visitBlocker(ref, mission);
    final free = mission?.visitMode == 'free';

    void open(MissionOutlet o) {
      if (leader) {
        context.push('/outlets/${o.id}');
      } else if (blocker != null) {
        showMessage(context, blocker, error: true);
      } else {
        context.push('/missions/${widget.missionId}/new?outlet=${o.id}');
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(mission?.title ?? 'Points de vente')),
      floatingActionButton: !leader && free && blocker == null
          ? FloatingActionButton.extended(
              heroTag: 'mission-outlet-add',
              onPressed: () => context.push('/outlets/new'),
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Nouveau point de vente'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.page,
              Space.sm,
              Space.page,
              Space.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (blocker != null) ...[
                  InfoBanner(
                    icon: Icons.info_outline_rounded,
                    tone: Tone.info,
                    message: blocker,
                  ),
                  const SizedBox(height: Space.sm),
                ],
                if (!leader && blocker == null && todo.isNotEmpty) ...[
                  PillButton(
                    label: 'Ma tournée (${todo.length} à visiter)',
                    icon: Icons.route_rounded,
                    style: PillStyle.tonal,
                    onPressed: () =>
                        context.push('/missions/${widget.missionId}/route'),
                  ),
                  const SizedBox(height: Space.sm),
                ],
                AppSegmented<_Tab>(
                  segments: {
                    _Tab.todo:
                        '${free ? 'Pas encore visités' : 'À visiter'} (${todo.length})',
                    _Tab.done: 'Visités (${done.length})',
                  },
                  selected: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: Space.sm),
                AppSegmented<_View>(
                  segments: const {_View.list: 'Liste', _View.map: 'Carte'},
                  selected: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (outlets) {
              AsyncError(:final error) when outlets.value == null => Padding(
                padding: const EdgeInsets.all(Space.page),
                child: InfoBanner(
                  icon: Icons.wifi_off_rounded,
                  message: ApiException.from(error).message,
                ),
              ),
              _ when outlets.value == null => const Center(
                child: CircularProgressIndicator(),
              ),
              _ when _view == _View.map => _Map(outlets: shown, onTap: open),
              _ => RefreshIndicator(
                onRefresh: () => ref.refresh(
                  missionOutletsProvider(widget.missionId).future,
                ),
                child: shown.isEmpty
                    ? ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(Space.xxl),
                            child: Text(
                              _tab == _Tab.done
                                  ? 'Aucune visite pour le moment.'
                                  : 'Tous les points de vente ont été visités. Bravo !',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          Space.page,
                          0,
                          Space.page,
                          96,
                        ),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (_, i) =>
                            _Row(outlet: shown[i], onTap: () => open(shown[i])),
                      ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.outlet, required this.onTap});

  final MissionOutlet outlet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final o = outlet;
    final status = OutletStatus.from(o.status);
    final details = o.visited
        ? [
            '${o.visits} visite${o.visits > 1 ? 's' : ''}',
            if (o.lastVisitAt != null)
              '${formatShortDate(o.lastVisitAt!)} à ${formatTime(o.lastVisitAt!)}',
            ?o.lastVisitBy,
          ]
        : [
            ?o.category,
            if (o.distance != null)
              formatDistance(o.distance!)
            else if (o.position == null)
              'À localiser',
          ];
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              o.visited
                  ? Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                      ),
                    )
                  : OutletAvatar(category: o.category, status: status),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.name,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      details.join(' · '),
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                o.visited ? Icons.chevron_right_rounded : Icons.login_rounded,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Map extends ConsumerWidget {
  const _Map({required this.outlets, required this.onTap});

  final List<MissionOutlet> outlets;
  final ValueChanged<MissionOutlet> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final style = ref
        .watch(mapPrefsProvider)
        .styleFor(Theme.of(context).brightness);
    final located = outlets.where((o) => o.position != null).toList();
    final points = [for (final o in located) o.position!];
    return FlutterMap(
      key: ValueKey(points.length),
      options: MapOptions(
        initialCenter: points.isEmpty
            ? const LatLng(5.345, -4.02)
            : points.first,
        initialZoom: 15,
        initialCameraFit: points.length > 1
            ? CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.all(48),
                maxZoom: 17,
              )
            : null,
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
        MarkerLayer(
          markers: [
            for (final o in located)
              Marker(
                point: o.position!,
                width: OutletPin.width,
                height: OutletPin.height,
                alignment: Alignment.topCenter,
                child: Semantics(
                  button: true,
                  label: o.name,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => onTap(o),
                    child: o.visited
                        ? const Align(
                            alignment: Alignment.bottomCenter,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Color(0xFF16A34A),
                              child: Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : OutletPin(
                            category: o.category,
                            status: OutletStatus.from(o.status),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
