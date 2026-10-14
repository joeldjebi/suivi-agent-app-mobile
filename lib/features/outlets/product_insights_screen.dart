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

class ProductInsights {
  ProductInsights(this.overview, this.stockouts, this.sales, this.prices);

  final Map<String, dynamic> overview;
  final Map<String, dynamic> stockouts;
  final Map<String, dynamic> sales;
  final Map<String, dynamic> prices;
}

/// Tableau de bord des relevés de l'équipe du chef, sur la période choisie.
final productInsightsProvider = FutureProvider.autoDispose<ProductInsights>((
  ref,
) async {
  final days = ref.watch(_periodProvider);
  final repo = ref.read(repositoryProvider);
  final now = DateTime.now();
  final to = _date(now);
  final from = _date(now.subtract(Duration(days: days - 1)));
  final parts = await Future.wait([
    for (final p in ['overview', 'stockouts', 'sales', 'prices'])
      repo.productInsights(p, from: from, to: to),
  ]);
  return ProductInsights(parts[0], parts[1], parts[2], parts[3]);
});

/// Chef : ruptures en cours, meilleures ventes et prix face à la concurrence relevés par son
/// équipe ; un point de vente en rupture s'ouvre pour l'appeler ou le faire visiter.
class ProductInsightsScreen extends ConsumerWidget {
  const ProductInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(_periodProvider);
    final data = ref.watch(productInsightsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tableau de bord produits')),
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
              _ => _content(context, data.value!),
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, ProductInsights d) {
    final text = Theme.of(context).textTheme;
    final o = d.overview;
    final rate = o['stockoutRate'] as num?;
    final byProduct = (d.stockouts['byProduct'] as List)
        .cast<Map<String, dynamic>>();
    final ruptures = (d.stockouts['outlets'] as List)
        .cast<Map<String, dynamic>>();
    final sales = (d.sales['products'] as List)
        .cast<Map<String, dynamic>>()
        .where((p) => (p['sold'] as num) > 0)
        .take(8)
        .toList();
    final categories = (d.prices['categories'] as List)
        .cast<Map<String, dynamic>>();
    final maxSold = sales.isEmpty
        ? 1
        : sales.map((p) => p['sold'] as num).reduce((a, b) => a > b ? a : b);
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
      const SectionHeader('Meilleures ventes', trailing: _Legend()),
      if (sales.isEmpty)
        const InfoBanner(
          icon: Icons.info_outline_rounded,
          tone: Tone.info,
          message: 'Aucune vente relevée sur la période.',
        )
      else
        SurfaceCard(
          child: Column(
            children: [
              for (final p in sales) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    [p['name'], ?p['format']].join(' '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                ThinProgress(
                  value: (p['sold'] as num) / maxSold,
                  color: (p['own'] as bool) ? _own : _competitor,
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
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
                ),
                const SizedBox(height: Space.sm),
              ],
            ],
          ),
        ),
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

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Dot(own: true),
        const SizedBox(width: 4),
        Text('Nous', style: style),
        const SizedBox(width: 10),
        const _Dot(own: false),
        const SizedBox(width: 4),
        Text('Concurrents', style: style),
      ],
    );
  }
}
