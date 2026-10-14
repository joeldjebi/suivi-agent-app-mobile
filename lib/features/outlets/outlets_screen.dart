import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/database.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/common.dart';
import '../team/map_options.dart';
import '../team/team_map_screen.dart' show mapTilesProvider;
import 'outlet_models.dart';
import 'outlet_widgets.dart';
import 'outlets_controller.dart';

enum _View { list, map }

/// Onglet « Points de vente » : ceux des zones de l'agent (ou de l'équipe du chef), les plus
/// proches d'abord, en liste ou sur la carte ; ajout sur place.
class OutletsScreen extends ConsumerStatefulWidget {
  const OutletsScreen({super.key});

  @override
  ConsumerState<OutletsScreen> createState() => _OutletsScreenState();
}

class _OutletsScreenState extends ConsumerState<OutletsScreen> {
  _View _view = _View.list;
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(herePositionProvider);
    ref.invalidate(outletsProvider);
    await ref.read(outletsProvider.future).catchError((Object _) {
      return OutletList(
        items: const [],
        total: 0,
        counts: const {},
        here: null,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(outletsProvider);
    final filter = ref.watch(outletFilterProvider);
    final pending = ref.watch(pendingOutletsProvider).value ?? const [];
    final data = list.value;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'outlet-add',
        onPressed: () => context.push('/outlets/new'),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Ajouter'),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BrandHeader(
              title: 'Points de vente',
              subtitle: data == null
                  ? null
                  : '${data.total} point${data.total > 1 ? 's' : ''} de vente',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                0,
                Space.page,
                Space.sm,
              ),
              child: Column(
                children: [
                  AppSegmented<_View>(
                    segments: const {_View.list: 'Liste', _View.map: 'Carte'},
                    selected: _view,
                    onChanged: (v) => setState(() => _view = v),
                  ),
                  const SizedBox(height: Space.sm),
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Nom, gérant, téléphone, repère',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      suffixIcon: filter.q.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                ref
                                    .read(outletFilterProvider.notifier)
                                    .search('');
                              },
                            ),
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 350),
                        () => ref.read(outletFilterProvider.notifier).search(v),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.page),
                children: [
                  _StatusChip(
                    label: 'Tous',
                    selected: filter.status == null,
                    onTap: () =>
                        ref.read(outletFilterProvider.notifier).status(null),
                  ),
                  for (final s in OutletStatus.values)
                    _StatusChip(
                      label: s.label,
                      color: s.color,
                      count: data?.counts[s],
                      selected: filter.status == s,
                      onTap: () => ref
                          .read(outletFilterProvider.notifier)
                          .status(filter.status == s ? null : s),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _view == _View.map
                  ? _OutletsMap(list: data)
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          Space.page,
                          Space.sm,
                          Space.page,
                          96,
                        ),
                        children: [
                          if (pending.isNotEmpty) ...[
                            _PendingCard(rows: pending),
                            const SizedBox(height: Space.md),
                          ],
                          ...switch (list) {
                            AsyncError(:final error) when data == null => [
                              InfoBanner(
                                icon: Icons.wifi_off_rounded,
                                message: ApiException.from(error).message,
                              ),
                            ],
                            _ when data == null => [
                              const Padding(
                                padding: EdgeInsets.all(Space.xxl),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ],
                            _ when data.items.isEmpty => [
                              _Empty(
                                filtered:
                                    filter.q.isNotEmpty ||
                                    filter.status != null,
                              ),
                            ],
                            _ => [
                              SurfaceCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (final (i, o)
                                        in data.items.indexed) ...[
                                      if (i > 0)
                                        const Divider(height: 1, indent: 64),
                                      _OutletRow(outlet: o),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          },
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: FilterChip(
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      avatar: color == null
          ? null
          : Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
      label: Text(count == null || count == 0 ? label : '$label $count'),
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _OutletRow extends StatelessWidget {
  const _OutletRow({required this.outlet});

  final Outlet outlet;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final details = [
      ?outlet.category,
      if (outlet.distance != null)
        formatDistance(outlet.distance!)
      else if (!outlet.located)
        'À localiser',
      ?outlet.zoneName,
    ];
    return InkWell(
      onTap: () => context.push('/outlets/${outlet.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
        child: Row(
          children: [
            OutletAvatar(category: outlet.category, status: outlet.status),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    outlet.name,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (details.isNotEmpty)
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
            const SizedBox(width: Space.sm),
            OutletStatusPill(outlet.status, dense: true),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xxl),
    child: Column(
      children: [
        Icon(
          Icons.storefront_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: Space.md),
        Text(
          filtered
              ? 'Aucun point de vente ne correspond'
              : 'Aucun point de vente',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Space.xs),
        Text(
          filtered
              ? 'Changez la recherche ou le filtre.'
              : 'Touchez « Ajouter » devant un commerce pour l’enregistrer avec sa position.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

/// Ajouts et changements saisis sans réseau ; ceux refusés attendent une décision.
class _PendingCard extends ConsumerWidget {
  const _PendingCard({required this.rows});

  final List<PendingOutlet> rows;

  Future<void> _sendAnyway(WidgetRef ref, PendingOutlet row) async {
    final db = ref.read(databaseProvider);
    final body = jsonDecode(row.bodyJson) as Map<String, dynamic>;
    await (db.update(
      db.pendingOutlets,
    )..where((o) => o.clientId.equals(row.clientId))).write(
      PendingOutletsCompanion(
        bodyJson: Value(jsonEncode({...body, 'force': true})),
        error: const Value(null),
        errorCode: const Value(null),
      ),
    );
    await ref.read(syncProvider).flush();
    ref.invalidate(outletsProvider);
  }

  Future<void> _remove(WidgetRef ref, PendingOutlet row) async {
    final db = ref.read(databaseProvider);
    await (db.delete(
      db.pendingOutlets,
    )..where((o) => o.clientId.equals(row.clientId))).go();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final waiting = rows.where((r) => r.error == null).length;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (waiting > 0)
            Row(
              children: [
                const Icon(Icons.cloud_upload_outlined, size: 20),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    '$waiting enregistrement${waiting > 1 ? 's' : ''} en attente d’envoi : '
                    'ils partiront au retour du réseau.',
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          for (final row in rows.where((r) => r.error != null)) ...[
            if (waiting > 0) const SizedBox(height: Space.md),
            Text(
              '« ${row.name} » n’a pas été enregistré',
              style: text.titleSmall,
            ),
            Text(row.error!, style: text.bodySmall),
            Wrap(
              spacing: Space.sm,
              children: [
                if (row.errorCode == 'OUTLET_DUPLICATE')
                  TextButton(
                    onPressed: () => _sendAnyway(ref, row),
                    child: const Text('C’est un autre commerce : envoyer'),
                  ),
                TextButton(
                  onPressed: () => _remove(ref, row),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Carte des points de vente avec la position de l'utilisateur.
class _OutletsMap extends ConsumerWidget {
  const _OutletsMap({required this.list});

  final OutletList? list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final style = ref
        .watch(mapPrefsProvider)
        .styleFor(Theme.of(context).brightness);
    final located = list?.items.where((o) => o.located).toList() ?? const [];
    final here = list?.here;
    final points = [for (final o in located) o.position!, ?here];
    return FlutterMap(
      key: ValueKey(points.length),
      options: MapOptions(
        initialCenter: here ?? const LatLng(5.345, -4.02),
        initialZoom: 14,
        initialCameraFit: points.length > 1
            ? CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.all(48),
                maxZoom: 17,
              )
            : null,
        minZoom: 4,
        maxZoom: 19,
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
            if (here != null)
              Marker(
                point: here,
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
            for (final o in located)
              Marker(
                point: o.position!,
                width: OutletPin.width,
                height: OutletPin.height,
                alignment: Alignment.topCenter,
                child: Semantics(
                  button: true,
                  label: '${o.name}, ${o.status.label}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => context.push('/outlets/${o.id}'),
                    child: OutletPin(category: o.category, status: o.status),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
