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
import '../missions/product_readings_input.dart' show formatQuantity;

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
        title: Text(leader ? 'Tableau de bord produits' : 'Mes produits'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(productInsightsProvider.future),
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
              _ => _content(context, ref, data.value!, own: own),
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
  }) => [
    if (d.orders != null) ..._orders(context, d.orders!),
    if (d.readings != null) ...[
      if (d.orders != null) const SectionHeader('Relevés en visite'),
      ..._readings(context, ref, d.readings!, own: own),
    ],
  ];

  /// Ce que la structure a vendu : commandes livrées ou payées de la période.
  List<Widget> _orders(BuildContext context, OrderInsights o) {
    final s = o.summary;
    final by = (s['byStatus'] as Map).cast<String, dynamic>();
    num amountOf(String st) => ((by[st] as Map)['amount'] as num);
    int countOf(String st) => ((by[st] as Map)['count'] as num).toInt();
    final currency = s['currency'] as String? ?? 'XOF';
    final sold = countOf('delivered') + countOf('paid');
    final ranked = rankSales([
      for (final p in o.products) {...p, 'own': true, 'sold': p['quantity']},
    ], own: true);
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
            label: 'Ventes (commandes)',
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
      const SectionHeader('Nos produits vendus'),
      if (ranked.best.isEmpty && ranked.worst.isEmpty)
        const InfoBanner(
          icon: Icons.info_outline_rounded,
          tone: Tone.info,
          message:
              'Aucune commande livrée ou payée sur la période. Une commande compte comme vente une fois livrée.',
        )
      else ...[
        if (ranked.best.isNotEmpty)
          _SalesCard(
            title: 'Les plus commandés',
            icon: Icons.trending_up_rounded,
            products: ranked.best,
            own: true,
          ),
        if (ranked.worst.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          _SalesCard(
            title: 'Les moins commandés',
            icon: Icons.trending_down_rounded,
            products: ranked.worst,
            own: true,
          ),
        ],
      ],
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
    final ranked = rankSales(
      (d.sales['products'] as List).cast<Map<String, dynamic>>(),
      own: own,
    );
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
            label: 'Vendu (nos produits)',
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
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, r) in ruptures.take(30).indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 52),
                ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: danger.withValues(alpha: 0.12),
                    child: Icon(Icons.close_rounded, size: 18, color: danger),
                  ),
                  title: Text(
                    [r['productName'], ?r['format']].join(' '),
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
                  onTap: () => context.push('/outlets/${r['outletId']}'),
                ),
              ],
            ],
          ),
        ),
      if (byProduct.isNotEmpty) ...[
        const SectionHeader('Taux de rupture par produit'),
        SurfaceCard(
          child: Column(
            children: [
              for (final p in byProduct) ...[
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
            ],
          ),
        ),
      ],
      const SectionHeader('Ventes'),
      AppSegmented<bool>(
        segments: const {true: 'Nos produits', false: 'Concurrents'},
        selected: own,
        onChanged: (v) => ref.read(_ownProvider.notifier).set(v),
      ),
      const SizedBox(height: Space.sm),
      if (ranked.best.isEmpty && ranked.worst.isEmpty)
        InfoBanner(
          icon: Icons.info_outline_rounded,
          tone: Tone.info,
          message: own
              ? 'Aucune vente de nos produits relevée sur la période.'
              : 'Aucune vente de la concurrence relevée sur la période.',
        )
      else ...[
        if (ranked.best.isNotEmpty)
          _SalesCard(
            title: 'Les plus vendus',
            icon: Icons.trending_up_rounded,
            products: ranked.best,
            own: own,
          ),
        if (ranked.worst.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          _SalesCard(
            title: 'Les moins vendus',
            icon: Icons.trending_down_rounded,
            products: ranked.worst,
            own: own,
          ),
        ],
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
