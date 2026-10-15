import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/field_display.dart';
import '../missions/product_readings_input.dart' show formatQuantity;
import 'outlet_widgets.dart';

/// Visite d'un point de vente dans l'historique (mission ou visite libre).
class VisitSummary {
  VisitSummary({
    required this.id,
    required this.title,
    required this.formName,
    required this.agentId,
    required this.agent,
    required this.at,
    required this.status,
    this.missionId,
    this.rejectedReason,
    this.distance,
    this.readings = 0,
  });

  final String id;

  /// null : visite libre (sans mission).
  final String? missionId;
  final String title;
  final String formName;
  final String agentId;
  final String agent;
  final DateTime at;
  final String status;
  final String? rejectedReason;
  final int? distance;

  /// Produits relevés pendant la visite.
  final int readings;

  bool get rejected => status == 'rejected';

  /// « Visite libre · Audit » ou le titre de la mission.
  String get label => missionId == null ? 'Visite libre · $formName' : title;

  factory VisitSummary.fromJson(Map<String, dynamic> j) => VisitSummary(
    id: j['id'] as String,
    missionId: j['missionId'] as String?,
    title: j['title'] as String? ?? '',
    formName: j['formName'] as String? ?? '',
    agentId: j['agentId'] as String,
    agent: j['agent'] as String? ?? '',
    at: DateTime.parse(j['submittedAt'] as String).toLocal(),
    status: j['status'] as String? ?? 'accepted',
    rejectedReason: j['rejectedReason'] as String?,
    distance: (j['distance'] as num?)?.toInt(),
    // Liste : le nombre de produits relevés ; détail : les relevés eux-mêmes.
    readings: switch (j['readings']) {
      final num n => n.toInt(),
      final List l => l.length,
      _ => 0,
    },
  );
}

/// Relevé d'un produit pendant une visite.
class VisitReading {
  VisitReading({
    required this.product,
    this.presence,
    this.stock,
    this.price,
    this.sold,
    this.losses,
  });

  final CatalogProduct product;
  final bool? presence;
  final num? stock;
  final num? price;
  final num? sold;
  final num? losses;

  factory VisitReading.fromJson(Map<String, dynamic> j) => VisitReading(
    product: CatalogProduct.fromJson({...j, 'id': j['productId']}),
    presence: j['presence'] as bool?,
    stock: j['stock'] as num?,
    price: j['price'] as num?,
    sold: j['sold'] as num?,
    losses: j['losses'] as num?,
  );
}

class VisitDetail {
  VisitDetail({
    required this.visit,
    required this.outletId,
    required this.outletName,
    required this.fields,
    required this.data,
    required this.readings,
  });

  final VisitSummary visit;
  final String outletId;
  final String outletName;
  final List<MissionField> fields;
  final Map<String, dynamic> data;
  final List<VisitReading> readings;

  factory VisitDetail.fromJson(Map<String, dynamic> j) => VisitDetail(
    visit: VisitSummary.fromJson(j),
    outletId: j['outletId'] as String,
    outletName: j['outletName'] as String? ?? '',
    fields: [
      for (final f in j['fields'] as List? ?? const [])
        MissionField.fromJson(f as Map<String, dynamic>),
    ],
    data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    readings: [
      for (final r in j['readings'] as List? ?? const [])
        VisitReading.fromJson(r as Map<String, dynamic>),
    ],
  );
}

/// Visites d'un point de vente : toutes ou les miennes, les `limit` plus récentes.
final outletVisitsProvider = FutureProvider.autoDispose
    .family<
      ({List<VisitSummary> items, int total}),
      ({String outletId, bool mine, int limit})
    >((ref, key) async {
      final json = await ref
          .read(repositoryProvider)
          .outletVisits(key.outletId, mine: key.mine, limit: key.limit);
      return (
        items: [
          for (final v in json['items'] as List)
            VisitSummary.fromJson(v as Map<String, dynamic>),
        ],
        total: (json['total'] as num).toInt(),
      );
    });

final visitDetailProvider = FutureProvider.autoDispose
    .family<VisitDetail, String>(
      (ref, id) async => VisitDetail.fromJson(
        await ref.read(repositoryProvider).visitDetail(id),
      ),
    );

/// Historique des visites d'un point de vente. L'agent voit d'abord les siennes, et peut
/// afficher celles de toute l'équipe ; le chef voit celles de son équipe.
class OutletVisitsScreen extends ConsumerStatefulWidget {
  const OutletVisitsScreen({super.key, required this.outletId});

  final String outletId;

  @override
  ConsumerState<OutletVisitsScreen> createState() => _OutletVisitsScreenState();
}

class _OutletVisitsScreenState extends ConsumerState<OutletVisitsScreen> {
  static const _page = 30;
  late bool _mine = !ref.read(meProvider).isTeamLead;
  int _limit = _page;

  @override
  Widget build(BuildContext context) {
    final leader = ref.watch(meProvider).isTeamLead;
    final key = (outletId: widget.outletId, mine: _mine, limit: _limit);
    final visits = ref.watch(outletVisitsProvider(key));
    final data = visits.value;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des visites')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(outletVisitsProvider(key).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.xxxl,
          ),
          children: [
            if (!leader) ...[
              AppSegmented<bool>(
                segments: const {true: 'Mes visites', false: 'Toute l’équipe'},
                selected: _mine,
                onChanged: (v) => setState(() {
                  _mine = v;
                  _limit = _page;
                }),
              ),
              const SizedBox(height: Space.md),
            ],
            ...switch (visits) {
              AsyncError(:final error) when data == null => [
                InfoBanner(
                  icon: Icons.wifi_off_rounded,
                  message: ApiException.from(error).message,
                ),
              ],
              _ when data == null => [
                const Padding(
                  padding: EdgeInsets.all(Space.xxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              _ when data.items.isEmpty => [
                Padding(
                  padding: const EdgeInsets.all(Space.xxl),
                  child: Text(
                    _mine
                        ? 'Vous n’avez pas encore visité ce point de vente.'
                        : 'Pas encore de visite.',
                    textAlign: TextAlign.center,
                    style: text.bodyLarge,
                  ),
                ),
              ],
              _ => [
                Text(
                  '${data.total} visite${data.total > 1 ? 's' : ''}',
                  style: text.bodySmall,
                ),
                const SizedBox(height: Space.sm),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, v) in data.items.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        VisitTile(visit: v, showAgent: !_mine),
                      ],
                    ],
                  ),
                ),
                if (data.total > data.items.length) ...[
                  const SizedBox(height: Space.md),
                  PillButton(
                    label: 'Voir plus',
                    style: PillStyle.outline,
                    loading: visits.isLoading,
                    onPressed: () => setState(() => _limit += _page),
                  ),
                ],
              ],
            },
          ],
        ),
      ),
    );
  }
}

/// Ligne d'une visite : formulaire ou mission, date, agent, produits relevés ; rejetée en
/// rouge. Le toucher ouvre son détail.
class VisitTile extends StatelessWidget {
  const VisitTile({super.key, required this.visit, this.showAgent = true});

  final VisitSummary visit;
  final bool showAgent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = toneColor(context, Tone.danger);
    final v = visit;
    return ListTile(
      leading: Icon(
        v.rejected ? Icons.block_rounded : Icons.assignment_turned_in_outlined,
        color: v.rejected ? danger : scheme.primary,
      ),
      title: Text(v.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          '${formatShortDate(v.at)} à ${formatTime(v.at)}',
          if (showAgent && v.agent.isNotEmpty) v.agent,
          if (v.readings > 0)
            '${v.readings} produit${v.readings > 1 ? 's' : ''} relevé${v.readings > 1 ? 's' : ''}',
          if (v.rejected) 'rejetée',
        ].join(' · '),
        style: v.rejected ? TextStyle(color: danger) : null,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push('/visits/${v.id}'),
    );
  }
}

/// Détail d'une visite : qui, quand, où ; réponses du formulaire, photos, et relevé de chaque
/// produit (présence, stock, prix, ventes, pertes).
class VisitDetailScreen extends ConsumerWidget {
  const VisitDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(visitDetailProvider(id));
    final d = detail.value;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Visite')),
      body: switch (detail) {
        AsyncError(:final error) when d == null => Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: ApiException.from(error).message,
          ),
        ),
        _ when d == null => const Center(child: CircularProgressIndicator()),
        _ => ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.xxxl,
          ),
          children: [
            Text(d.visit.label, style: text.titleLarge),
            const SizedBox(height: 2),
            Text(
              [
                '${formatShortDate(d.visit.at)} à ${formatTime(d.visit.at)}',
                d.visit.agent,
                if (d.visit.distance != null)
                  'à ${formatDistance(d.visit.distance!)}',
              ].join(' · '),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.sm),
            InkWell(
              onTap: () => context.push('/outlets/${d.outletId}'),
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: Space.xs),
                  Text(
                    d.outletName,
                    style: text.bodyMedium?.copyWith(color: scheme.primary),
                  ),
                ],
              ),
            ),
            if (d.visit.rejected) ...[
              const SizedBox(height: Space.md),
              InfoBanner(
                icon: Icons.block_rounded,
                tone: Tone.danger,
                message: 'Visite rejetée : ${d.visit.rejectedReason ?? ''}',
              ),
            ],
            if (d.readings.isNotEmpty) ...[
              const SectionHeader('Produits relevés'),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, r) in d.readings.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 52),
                      _ReadingTile(reading: r),
                    ],
                  ],
                ),
              ),
            ],
            if (d.fields.any((f) => f.type != FieldType.products)) ...[
              const SectionHeader('Réponses'),
              GroupedList(
                indent: Space.lg,
                children: [
                  for (final f in d.fields)
                    if (f.type != FieldType.products &&
                        f.type != FieldType.photo)
                      ListRow(
                        title: f.label,
                        value: d.data[f.key] == null || d.data[f.key] == ''
                            ? '—'
                            : fieldDisplay(f, d.data[f.key]),
                      ),
                ],
              ),
              for (final f in d.fields)
                if (f.type == FieldType.photo && d.data[f.key] is String) ...[
                  const SizedBox(height: Space.md),
                  Text(f.label, style: text.titleSmall),
                  const SizedBox(height: Space.xs),
                  RemotePhoto(id: d.data[f.key] as String, label: f.label),
                ],
            ],
          ],
        ),
      },
    );
  }
}

class _ReadingTile extends StatelessWidget {
  const _ReadingTile({required this.reading});

  final VisitReading reading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final r = reading;
    final out = r.presence == false;
    final danger = toneColor(context, Tone.danger);
    final details = [
      if (out) 'Rupture',
      if (!out && r.stock != null)
        'Stock ${formatQuantity(r.stock!, r.product)}',
      if (r.price != null) formatMoney(r.price!),
      if (r.sold != null) 'Vendu ${formatQuantity(r.sold!, r.product)}',
      if (r.losses != null && r.losses! > 0)
        'Pertes ${formatQuantity(r.losses!, r.product)}',
    ];
    return ListTile(
      leading: Icon(
        out
            ? Icons.cancel_rounded
            : r.presence == true
            ? Icons.check_circle_rounded
            : Icons.inventory_2_outlined,
        color: out
            ? danger
            : r.presence == true
            ? toneColor(context, Tone.success)
            : scheme.onSurfaceVariant,
        semanticLabel: out ? 'En rupture' : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              r.product.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!r.product.own) ...[
            const SizedBox(width: Space.xs),
            Text(
              'concurrent',
              style: text.labelSmall?.copyWith(
                color: toneColor(context, Tone.warning),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        details.isEmpty ? '—' : details.join(' · '),
        style: out ? TextStyle(color: danger) : null,
      ),
    );
  }
}
