import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/product_readings_input.dart' show formatQuantity;
import 'form_stats_section.dart';
import 'outlet_widgets.dart' show openOutlet;

/// Nos produits / la concurrence : mêmes couleurs que le site.
const _own = Color(0xFF2563EB);
const _competitor = Color(0xFFD97706);

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Période : 7 ou 30 derniers jours.
class _PeriodController extends Notifier<int> {
  @override
  int build() => 30;

  void set(int days) => state = days;
}

final _periodProvider = NotifierProvider<_PeriodController, int>(
  _PeriodController.new,
);

/// Onglet de la page : ventes, visites (formulaires), produits (relevés).
enum StatsTab { sales, visits, products }

class _TabController extends Notifier<StatsTab?> {
  @override
  StatsTab? build() => null;

  void set(StatsTab tab) => state = tab;
}

final _tabProvider = NotifierProvider<_TabController, StatsTab?>(
  _TabController.new,
);

/// Ventes : nos produits ou ceux de la concurrence.
class _OwnController extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool own) => state = own;
}

final _ownProvider = NotifierProvider<_OwnController, bool>(_OwnController.new);

/// Produits classés par ventes relevées : les plus vendus, puis les moins vendus (sans
/// répéter un produit déjà parmi les plus vendus).
({List<Map<String, dynamic>> best, List<Map<String, dynamic>> worst}) rankSales(
  List<Map<String, dynamic>> products, {
  required bool own,
  int size = 5,
}) {
  final side = [
    for (final p in products)
      if (p['own'] == own) p,
  ]..sort((a, b) => (b['sold'] as num).compareTo(a['sold'] as num));
  final best = side.where((p) => (p['sold'] as num) > 0).take(size).toList();
  final worst = side.reversed
      .where((p) => !best.contains(p))
      .take(size)
      .toList();
  return (best: best, worst: worst);
}

/// Relevés faits en visite (formule avec les relevés produits).
class ReadingsInsights {
  ReadingsInsights(this.overview, this.stockouts, this.sales, this.prices);

  final Map<String, dynamic> overview;
  final Map<String, dynamic> stockouts;
  final Map<String, dynamic> sales;
  final Map<String, dynamic> prices;
}

/// Ventes de la structure aux points de vente : commandes (formule avec la prise de commande).
class OrderInsights {
  OrderInsights(this.summary, this.products);

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> products;
}

class ProductInsights {
  ProductInsights({this.readings, this.orders});

  final ReadingsInsights? readings;
  final OrderInsights? orders;
}

/// Tableau de bord des relevés, sur la période choisie : ceux de l'équipe du chef, ou ceux de
/// l'agent (le serveur limite les chiffres à son périmètre).
final productInsightsProvider = FutureProvider.autoDispose<ProductInsights>((
  ref,
) async {
  final days = ref.watch(_periodProvider);
  final me = ref.read(meProvider);
  final repo = ref.read(repositoryProvider);
  final now = DateTime.now();
  final to = _date(now);
  final from = _date(now.subtract(Duration(days: days - 1)));
  Future<ReadingsInsights> readings() async {
    final parts = await Future.wait([
      for (final p in ['overview', 'stockouts', 'sales', 'prices'])
        repo.productInsights(p, from: from, to: to),
    ]);
    return ReadingsInsights(parts[0], parts[1], parts[2], parts[3]);
  }

  Future<OrderInsights> orders() async {
    final (summary, sold) = await (
      repo.ordersSummary(from: from, to: to),
      repo.soldProducts(from: from, to: to),
    ).wait;
    return OrderInsights(
      summary,
      (sold['products'] as List).cast<Map<String, dynamic>>(),
    );
  }

  // Chaque partie selon la formule : relevés en visite, commandes.
  final (r, o) = await (
    me.hasProductAudits ? readings() : Future.value(null),
    me.hasOrders ? orders() : Future.value(null),
  ).wait;
  return ProductInsights(readings: r, orders: o);
});

/// Ruptures en cours, produits les plus et les moins vendus (les nôtres et ceux de la
/// concurrence), prix face à la concurrence. Chef : relevés de son équipe ; agent (« Mes
/// produits ») : ses propres relevés. Un point de vente en rupture s'ouvre au toucher.
class ProductInsightsScreen extends ConsumerWidget {
  const ProductInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(_periodProvider);
    final data = ref.watch(productInsightsProvider);
    final leader = ref.watch(meProvider).isTeamLead;
    final own = ref.watch(_ownProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(leader ? 'Statistiques de l’équipe' : 'Mes statistiques'),
      ),
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(formUsageProvider);
          ref.invalidate(formStatsProvider);
          return ref.refresh(productInsightsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.xxxl,
          ),
          children: [
            AppSegmented<int>(
              segments: const {7: '7 derniers jours', 30: '30 derniers jours'},
              selected: days,
              onChanged: (d) => ref.read(_periodProvider.notifier).set(d),
            ),
            const SizedBox(height: Space.md),
            ...switch (data) {
              AsyncError(:final error) when data.value == null => [
                InfoBanner(
                  icon: Icons.wifi_off_rounded,
                  message: ApiException.from(error).message,
                ),
              ],
              _ when data.value == null => [
                const Padding(
                  padding: EdgeInsets.all(Space.xxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              _ => _content(context, ref, data.value!, own: own, days: days),
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    ProductInsights d, {
    required bool own,
    required int days,
  }) {
    final me = ref.watch(meProvider);
    final r = d.readings;
    // Les onglets que la formule permet, dans l'ordre de l'agent : vendre, visiter, observer.
    final tabs = {
      if (d.orders != null) StatsTab.sales: 'Ventes',
      if (me.hasMissions || me.hasOutlets) StatsTab.visits: 'Visites',
      if (r != null) StatsTab.products: 'Produits',
    };
    if (tabs.isEmpty) return const [];
    final chosen = ref.watch(_tabProvider);
    final tab = tabs.containsKey(chosen) ? chosen! : tabs.keys.first;
    final visits = ref.watch(formUsageProvider(days)).value;
    return [
      _Headline(insights: d, visits: visits, days: days),
      const SizedBox(height: Space.md),
      if (tabs.length > 1) ...[
        AppSegmented<StatsTab>(
          segments: tabs,
          selected: tab,
          onChanged: (t) => ref.read(_tabProvider.notifier).set(t),
        ),
        const SizedBox(height: Space.sm),
      ],
      ...switch (tab) {
        StatsTab.sales => [
          const _Caption('D’après les commandes livrées ou payées.'),
          ..._orders(context, d.orders!),
          const SectionHeader('Nos produits vendus'),
          ..._sales(d, own: true),
        ],
        StatsTab.visits => [FormStatsSection(days: days)],
        StatsTab.products => [
          const _Caption(
            'D’après les relevés de visite : ce que l’agent voit dans les commerces, pour nos produits et ceux des concurrents.',
          ),
          if ((r!.overview['visits'] as num? ?? 0) == 0)
            const InfoBanner(
              icon: Icons.info_outline_rounded,
              tone: Tone.info,
              message:
                  'Aucun relevé produit sur la période. Pour suivre les ruptures et les prix, faites une visite avec un formulaire qui contient un « Relevé par produit ».',
            )
          else ...[
            ..._readings(context, ref, r, own: own),
            const SectionHeader('Revendu par les commerces'),
            AppSegmented<bool>(
              segments: const {true: 'Nos produits', false: 'Concurrents'},
              selected: own,
              onChanged: (v) => ref.read(_ownProvider.notifier).set(v),
            ),
            const SizedBox(height: Space.sm),
            ..._sales(d, own: own, fromReadings: true),
          ],
        ],
      },
    ];
  }

  /// Ventes par produit. Nos produits : nos commandes livrées ou payées (à défaut, la revente
  /// relevée en visite) ; concurrents : leur revente relevée en visite.
  List<Widget> _sales(
    ProductInsights d, {
    required bool own,
    bool fromReadings = false,
  }) {
    final fromOrders = own && d.orders != null && !fromReadings;
    final products = fromOrders
        ? [
            for (final p in d.orders!.products)
              {...p, 'own': true, 'sold': p['quantity']},
          ]
        : (d.readings?.sales['products'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
    final ranked = rankSales(products, own: own);
    final source = fromOrders
        ? 'D’après les commandes livrées ou payées.'
        : 'D’après la revente constatée en visite (mesure « Vendu » des relevés).';
    if (ranked.best.isEmpty && ranked.worst.isEmpty) {
      return [
        InfoBanner(
          icon: Icons.info_outline_rounded,
          tone: Tone.info,
          message: fromOrders
              ? 'Aucune commande livrée ou payée sur la période : une commande compte comme vente une fois livrée.'
              : d.readings == null
              ? 'Les ventes des concurrents se suivent avec les relevés produits en visite.'
              : own
              ? 'Aucune revente de nos produits relevée sur la période.'
              : 'Aucune revente de la concurrence relevée sur la période (mesure « Vendu » des relevés).',
        ),
      ];
    }
    return [
      // Ventes : la source est déjà dite en tête de l'onglet.
      if (!fromOrders) _Caption(source),
      if (ranked.best.isNotEmpty)
        _SalesCard(
          title: fromOrders ? 'Les plus commandés' : 'Les plus vendus',
          icon: Icons.trending_up_rounded,
          products: ranked.best,
          own: own,
        ),
      if (ranked.worst.isNotEmpty) ...[
        const SizedBox(height: Space.sm),
        _SalesCard(
          title: fromOrders ? 'Les moins commandés' : 'Les moins vendus',
          icon: Icons.trending_down_rounded,
          products: ranked.worst,
          own: own,
        ),
      ],
    ];
  }

  /// Ce que la structure a vendu : commandes livrées ou payées de la période.
  List<Widget> _orders(BuildContext context, OrderInsights o) {
    final s = o.summary;
    final by = (s['byStatus'] as Map).cast<String, dynamic>();
    num amountOf(String st) => ((by[st] as Map)['amount'] as num);
    int countOf(String st) => ((by[st] as Map)['count'] as num).toInt();
    final currency = s['currency'] as String? ?? 'XOF';
    final sold = countOf('delivered') + countOf('paid');
    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: Space.sm,
        crossAxisSpacing: Space.sm,
        childAspectRatio: 1.45,
        children: [
          _Kpi(
            label: 'Vendu',
            value: formatMoney(
              amountOf('delivered') + amountOf('paid'),
              currency,
            ),
            hint:
                '$sold livrée${sold > 1 ? 's' : ''} ou payée${sold > 1 ? 's' : ''}',
          ),
          _Kpi(
            label: 'Encaissé',
            value: formatMoney(amountOf('paid'), currency),
            hint:
                'À encaisser : ${formatMoney(s['toCollect'] as num, currency)}',
          ),
          _Kpi(
            label: 'À livrer',
            value: formatNumber(countOf('taken')),
            hint: formatMoney(amountOf('taken'), currency),
          ),
          _Kpi(
            label: 'Annulées',
            value: formatNumber(countOf('cancelled')),
            hint: formatMoney(amountOf('cancelled'), currency),
          ),
        ],
      ),
    ];
  }

  /// Relevés faits en visite : ruptures, ventes constatées, prix face à la concurrence.
  List<Widget> _readings(
    BuildContext context,
    WidgetRef ref,
    ReadingsInsights d, {
    required bool own,
  }) {
    final text = Theme.of(context).textTheme;
    final o = d.overview;
    final rate = o['stockoutRate'] as num?;
    final byProduct = (d.stockouts['byProduct'] as List)
        .cast<Map<String, dynamic>>();
    final ruptures = (d.stockouts['outlets'] as List)
        .cast<Map<String, dynamic>>();
    final categories = (d.prices['categories'] as List)
        .cast<Map<String, dynamic>>();
    final danger = toneColor(context, Tone.danger);

    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: Space.sm,
        crossAxisSpacing: Space.sm,
        childAspectRatio: 1.45,
        children: [
          _Kpi(
            label: 'Taux de rupture',
            value: rate == null ? '—' : '$rate %',
            hint: '${o['ownStockouts']} sur ${o['ownChecked']} relevés',
            color: rate != null && rate >= 20 ? danger : null,
          ),
          _Kpi(
            label: 'Points de vente',
            value: formatNumber(o['outlets'] as num),
            hint: '${o['visits']} visites avec relevé',
          ),
          _Kpi(
            label: 'Revendu (nos produits)',
            value: formatNumber(o['ownSold'] as num),
            hint: 'Concurrence : ${formatNumber(o['competitorSold'] as num)}',
          ),
          _Kpi(
            label: 'Pertes',
            value: formatNumber(o['ownLosses'] as num),
            hint: 'unités (nos produits)',
          ),
        ],
      ),
      const SectionHeader('Ruptures en cours'),
      if (ruptures.isEmpty)
        const InfoBanner(
          icon: Icons.check_circle_outline_rounded,
          tone: Tone.success,
          message: 'Aucune rupture en cours sur la période.',
        )
      else
        _TopList(
          more: 'Voir les ${ruptures.length} ruptures',
          rows: [
            for (final r in ruptures)
              ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: danger.withValues(alpha: 0.12),
                  child: Icon(Icons.close_rounded, size: 18, color: danger),
                ),
                title: Text(
                  [r['productName'], ?r['format']].join(' '),
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    r['outletName'],
                    ?r['zone'],
                    formatShortDate(
                      DateTime.parse(r['since'] as String).toLocal(),
                    ),
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openOutlet(context, r['outletId'] as String),
              ),
          ],
        ),
      if (byProduct.isNotEmpty) ...[
        const SectionHeader('Produits les plus souvent en rupture'),
        _TopList(
          more: 'Voir les ${byProduct.length} produits',
          padded: true,
          rows: [
            for (final p in [
              ...byProduct,
            ]..sort((a, b) => (b['rate'] as num).compareTo(a['rate'] as num)))
              Column(
                children: [
                  Row(
                    children: [
                      _Dot(own: p['own'] as bool),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [p['name'], ?p['format']].join(' '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${p['rate']} % (${p['stockouts']}/${p['checked']})',
                        style: text.bodyMedium?.copyWith(
                          color: (p['rate'] as num) >= 20 ? danger : null,
                          fontWeight: (p['rate'] as num) >= 20
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ThinProgress(
                    value: (p['rate'] as num) / 100,
                    color: (p['rate'] as num) >= 20 ? danger : _own,
                  ),
                  const SizedBox(height: Space.sm),
                ],
              ),
          ],
        ),
      ],
      if (categories.isNotEmpty) ...[
        const SectionHeader('Prix face à la concurrence'),
        for (final c in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c['category'] as String, style: text.titleSmall),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: Space.lg,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const _Dot(own: true),
                      Text('Nous : ${formatNumber(c['own'] as num)} FCFA'),
                      const _Dot(own: false),
                      Text(
                        'Concurrence : ${formatNumber(c['competitor'] as num)} FCFA',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (c['gapPercent'] as num) == 0
                        ? 'Même prix moyen'
                        : 'Nous sommes ${(c['gapPercent'] as num).abs()} % '
                              '${(c['gapPercent'] as num) > 0 ? 'plus chers' : 'moins chers'}',
                    style: text.bodySmall?.copyWith(
                      color: toneColor(
                        context,
                        (c['gapPercent'] as num) > 0
                            ? Tone.warning
                            : Tone.success,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ];
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.hint,
    this.color,
  });

  final String label;
  final String value;
  final String hint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: text.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            hint,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.own});

  final bool own;

  @override
  Widget build(BuildContext context) => Semantics(
    label: own ? 'Notre produit' : 'Concurrent',
    child: Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: own ? _own : _competitor,
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// Produits classés par ventes relevées, avec une barre proportionnelle.
class _SalesCard extends StatelessWidget {
  const _SalesCard({
    required this.title,
    required this.icon,
    required this.products,
    required this.own,
  });

  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> products;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final max = products
        .map((p) => p['sold'] as num)
        .fold<num>(1, (a, b) => b > a ? b : a);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: Space.xs),
              Text(title, style: text.titleSmall),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final p in products) ...[
            Text(
              [p['name'], ?p['format']].join(' '),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            ThinProgress(
              value: (p['sold'] as num) / max,
              color: own ? _own : _competitor,
            ),
            const SizedBox(height: 2),
            Text(
              formatQuantity(
                p['sold'] as num,
                CatalogProduct.fromJson({
                  'id': p['productId'],
                  'name': p['name'],
                  'own': p['own'],
                  'unit': p['unit'],
                  'packagings': p['packagings'],
                }),
              ),
              style: text.bodySmall,
            ),
            const SizedBox(height: Space.sm),
          ],
        ],
      ),
    );
  }
}

/// Phrase d'explication sous un titre de section : d'où viennent les chiffres.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// En haut de la page : ce qu'il faut retenir de la période, en phrases courtes.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.insights,
    required this.visits,
    required this.days,
  });

  final ProductInsights insights;

  /// Formulaires remplis sur la période (null : en cours de chargement).
  final List<FormUsage>? visits;
  final int days;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final o = insights.orders?.summary;
    num paid = 0, sold = 0;
    if (o != null) {
      final by = (o['byStatus'] as Map).cast<String, dynamic>();
      paid = (by['paid'] as Map)['amount'] as num;
      sold = paid + ((by['delivered'] as Map)['amount'] as num);
    }
    final currency = o?['currency'] as String? ?? 'XOF';
    final forms = visits?.fold<int>(0, (n, f) => n + f.submissions);
    final r = insights.readings;
    final ruptures = r == null ? null : (r.stockouts['outlets'] as List).length;
    final lines = <(IconData, String)>[
      if (o != null)
        (
          Icons.payments_outlined,
          sold == 0
              ? 'Aucune vente livrée ou payée'
              : '${formatMoney(sold, currency)} vendus, dont ${formatMoney(paid, currency)} encaissés',
        ),
      if (forms != null)
        (
          Icons.assignment_turned_in_outlined,
          forms == 0
              ? 'Aucun formulaire envoyé'
              : '$forms formulaire${forms > 1 ? 's' : ''} envoyé${forms > 1 ? 's' : ''}',
        ),
      if (ruptures != null)
        (
          Icons.remove_shopping_cart_outlined,
          ruptures == 0
              ? 'Aucune rupture repérée'
              : '$ruptures rupture${ruptures > 1 ? 's' : ''} repérée${ruptures > 1 ? 's' : ''} en rayon',
        ),
    ];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'En bref, sur $days jours',
            style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.xs),
          for (final (icon, line) in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(line, style: text.bodyLarge)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Une liste courte : les 5 premières lignes, puis « Voir les N … » déplie le reste sur place.
class _TopList extends StatefulWidget {
  const _TopList({required this.rows, required this.more, this.padded = false});

  final List<Widget> rows;

  /// « Voir les 12 ruptures »
  final String more;

  /// Lignes sans marge propre (barres) : la carte en ajoute une.
  final bool padded;

  @override
  State<_TopList> createState() => _TopListState();
}

class _TopListState extends State<_TopList> {
  static const _shown = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rows = _all ? widget.rows : widget.rows.take(_shown).toList();
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0 && !widget.padded) const Divider(height: 1, indent: 52),
            if (widget.padded)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  i == 0 ? Space.md : 0,
                  Space.md,
                  0,
                ),
                child: r,
              )
            else
              r,
          ],
          if (widget.rows.length > _shown) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _all ? 'Voir moins' : widget.more,
                  textAlign: TextAlign.center,
                  style: text.titleSmall?.copyWith(color: scheme.primary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
