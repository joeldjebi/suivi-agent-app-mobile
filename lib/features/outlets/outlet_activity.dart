import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/product_readings_input.dart' show formatQuantity;
import 'outlet_widgets.dart' show FicheSection, PhotoThumb;
import 'outlets_controller.dart' show outletProvider;
import 'visit_forms.dart';

/// Visite d'un point de vente (mission ou visite libre), la plus récente d'abord.
class OutletVisitEntry {
  OutletVisitEntry({
    required this.id,
    required this.title,
    required this.formName,
    required this.agent,
    required this.at,
    required this.status,
    this.missionId,
    this.photoId,
  });

  final String id;

  /// Première photo de la visite (miniature).
  final String? photoId;

  /// null : visite libre (sans mission).
  final String? missionId;
  final String title;
  final String formName;
  final String agent;
  final DateTime at;
  final String status;

  bool get rejected => status == 'rejected';

  factory OutletVisitEntry.fromJson(Map<String, dynamic> j) => OutletVisitEntry(
    id: j['id'] as String,
    missionId: j['missionId'] as String?,
    title: j['missionTitle'] as String? ?? '',
    formName: j['formName'] as String? ?? '',
    agent: j['agent'] as String? ?? '',
    at: DateTime.parse(j['submittedAt'] as String).toLocal(),
    status: j['status'] as String? ?? 'accepted',
    photoId: j['photoId'] as String?,
  );
}

/// Dernier relevé d'un produit dans un point de vente.
class ProductReading {
  ProductReading({
    required this.product,
    required this.at,
    this.presence,
    this.stock,
    this.price,
    this.stockHistory = const [],
  });

  final CatalogProduct product;
  final DateTime at;
  final bool? presence;
  final num? stock;
  final num? price;

  /// Stocks relevés, du plus ancien au plus récent.
  final List<num> stockHistory;

  factory ProductReading.fromJson(Map<String, dynamic> j) {
    final last = (j['last'] as Map).cast<String, dynamic>();
    return ProductReading(
      product: CatalogProduct.fromJson({
        'id': j['productId'],
        'name': j['name'],
        'format': j['format'],
        'own': j['own'],
        'unit': j['unit'],
        'packagings': j['packagings'],
      }),
      at: DateTime.parse(last['at'] as String).toLocal(),
      presence: last['presence'] as bool?,
      stock: last['stock'] as num?,
      price: last['price'] as num?,
      stockHistory: [
        for (final h in j['stockHistory'] as List? ?? const [])
          (h as Map)['stock'] as num,
      ],
    );
  }
}

/// Derniers relevés produits d'un point de vente (formule avec les relevés).
final outletReadingsProvider = FutureProvider.autoDispose
    .family<List<ProductReading>, String>(
      (ref, id) async => [
        for (final r in await ref.read(repositoryProvider).outletReadings(id))
          ProductReading.fromJson(r as Map<String, dynamic>),
      ],
    );

/// Ruptures d'abord, puis nos produits, puis la concurrence.
List<ProductReading> _ordered(List<ProductReading> list) =>
    [...list]..sort((a, b) {
      final out = (a.presence == false ? 0 : 1) - (b.presence == false ? 0 : 1);
      if (out != 0) return out;
      final own = (a.product.own ? 0 : 1) - (b.product.own ? 0 : 1);
      return own != 0 ? own : a.product.label.compareTo(b.product.label);
    });

/// « 18 produits · 12 en rupture · relevé le 16 oct. »
String readingsHeadline(List<ProductReading> list) {
  final out = list.where((r) => r.presence == false).length;
  final last = list.map((r) => r.at).reduce((a, b) => a.isAfter(b) ? a : b);
  return [
    '${list.length} produit${list.length > 1 ? 's' : ''}',
    if (out > 0) '$out en rupture' else 'aucune rupture',
    'relevé le ${formatShortDate(last)}',
  ].join(' · ');
}

/// Fiche : le dernier relevé de chaque produit. Résumé, les 5 premiers (ruptures d'abord), et
/// « Voir tout » vers la page des relevés.
class OutletProductsSection extends ConsumerWidget {
  const OutletProductsSection({super.key, required this.outletId});

  final String outletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(outletReadingsProvider(outletId));
    final list = readings.value;
    if (list == null) {
      return FicheSection(
        title: 'Produits relevés',
        rows: const [],
        empty: readings.isLoading
            ? 'Chargement…'
            : 'Relevés indisponibles hors connexion.',
      );
    }
    final ordered = _ordered(list);
    return FicheSection(
      title: 'Produits relevés',
      summary: list.isEmpty ? null : readingsHeadline(list),
      empty:
          'Aucun relevé pour le moment : faites une visite avec un formulaire de relevé pour noter la présence, le stock et le prix des produits.',
      rows: [
        for (final r in ordered.take(FicheSection.shown))
          _ReadingRow(reading: r),
      ],
      seeAllLabel: 'Voir les ${list.length} produits',
      onSeeAll: list.length > FicheSection.shown
          ? () => context.push('/outlets/$outletId/products')
          : null,
    );
  }
}

enum _ReadingFilter { all, out, own, competitor }

/// Tous les produits relevés d'un point de vente, avec un filtre : en rupture, nos produits,
/// la concurrence.
class OutletReadingsScreen extends ConsumerStatefulWidget {
  const OutletReadingsScreen({super.key, required this.outletId});

  final String outletId;

  @override
  ConsumerState<OutletReadingsScreen> createState() =>
      _OutletReadingsScreenState();
}

class _OutletReadingsScreenState extends ConsumerState<OutletReadingsScreen> {
  _ReadingFilter _filter = _ReadingFilter.all;

  @override
  Widget build(BuildContext context) {
    final readings = ref.watch(outletReadingsProvider(widget.outletId));
    final list = readings.value ?? const <ProductReading>[];
    final name = ref.watch(outletProvider(widget.outletId)).value?.outlet.name;
    final text = Theme.of(context).textTheme;
    final shown = _ordered(list).where(
      (r) => switch (_filter) {
        _ReadingFilter.all => true,
        _ReadingFilter.out => r.presence == false,
        _ReadingFilter.own => r.product.own,
        _ReadingFilter.competitor => !r.product.own,
      },
    );
    return Scaffold(
      appBar: AppBar(title: Text(name ?? 'Produits relevés')),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.refresh(outletReadingsProvider(widget.outletId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.xxxl,
          ),
          children: [
            if (list.isNotEmpty) ...[
              Text(readingsHeadline(list), style: text.bodyMedium),
              const SizedBox(height: Space.sm),
            ],
            // Toutes les pastilles visibles (pas de défilement caché).
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (f, label) in [
                  (_ReadingFilter.all, 'Tous (${list.length})'),
                  (
                    _ReadingFilter.out,
                    'En rupture (${list.where((r) => r.presence == false).length})',
                  ),
                  (
                    _ReadingFilter.own,
                    'Nos produits (${list.where((r) => r.product.own).length})',
                  ),
                  (
                    _ReadingFilter.competitor,
                    'Concurrents (${list.where((r) => !r.product.own).length})',
                  ),
                ])
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(
                  readings.isLoading ? 'Chargement…' : 'Aucun produit ici.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, r) in shown.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 52),
                      _ReadingRow(reading: r),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.reading});

  final ProductReading reading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final r = reading;
    final out = r.presence == false;
    final danger = toneColor(context, Tone.danger);
    final details = [
      if (out)
        'Rupture'
      else if (r.stock != null)
        'Stock ${formatQuantity(r.stock!, r.product)}',
      if (r.price != null) formatMoney(r.price!),
      formatShortDate(r.at),
    ];
    // Évolution du stock : en hausse, en baisse ou stable depuis le relevé précédent.
    final h = r.stockHistory;
    final trend = h.length < 2
        ? null
        : h.last > h[h.length - 2]
        ? Icons.trending_up_rounded
        : h.last < h[h.length - 2]
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      child: Row(
        children: [
          Icon(
            out ? Icons.cancel_rounded : Icons.check_circle_rounded,
            size: 22,
            color: out
                ? danger
                : r.presence == true
                ? toneColor(context, Tone.success)
                : scheme.onSurfaceVariant,
            semanticLabel: out ? 'En rupture' : 'Présent',
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r.product.label,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
                Text(
                  details.join(' · '),
                  style: text.bodySmall?.copyWith(
                    color: out ? danger : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trend != null)
            Icon(trend, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Fiche : les 5 dernières visites (missions et visites libres), rejetées signalées ; chacune
/// s'ouvre, et « Voir tout » mène à l'historique complet.
class OutletVisitsSection extends StatelessWidget {
  const OutletVisitsSection({
    super.key,
    required this.outletId,
    required this.visits,
  });

  final String outletId;
  final List<OutletVisitEntry> visits;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = toneColor(context, Tone.danger);
    final n = visits.length;
    return FicheSection(
      title: 'Dernières visites',
      summary: n == 0
          ? null
          : '${n >= 30 ? '30+' : n} visite${n > 1 ? 's' : ''} · dernière le ${formatShortDate(visits.first.at)}',
      empty: 'Pas encore de visite : touchez « Visiter » en haut de la fiche.',
      rows: [
        for (final v in visits.take(FicheSection.shown))
          ListTile(
            leading: v.photoId != null && !v.rejected
                ? PhotoThumb(id: v.photoId!, label: 'Photo de la visite')
                : Icon(
                    v.rejected
                        ? Icons.block_rounded
                        : Icons.assignment_turned_in_outlined,
                    color: v.rejected ? danger : scheme.primary,
                  ),
            title: Text(
              v.missionId == null ? v.formName : v.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                '${formatShortDate(v.at)} à ${formatTime(v.at)}',
                if (v.agent.isNotEmpty) v.agent,
                if (v.rejected) 'rejetée',
              ].join(' · '),
              style: v.rejected ? TextStyle(color: danger) : null,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/visits/${v.id}'),
          ),
      ],
      seeAllLabel: 'Voir toutes les visites',
      onSeeAll: n > 0 ? () => context.push('/outlets/$outletId/visits') : null,
    );
  }
}

/// Juste après l'ajout d'un point de vente : proposer d'enchaîner sur la première visite.
class AskFirstVisit extends ConsumerStatefulWidget {
  const AskFirstVisit({super.key, required this.outletId});

  final String outletId;

  @override
  ConsumerState<AskFirstVisit> createState() => _AskFirstVisitState();
}

class _AskFirstVisitState extends ConsumerState<AskFirstVisit> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_ask()));
  }

  Future<void> _ask() async {
    final forms = await ref
        .read(visitFormsProvider.future)
        .catchError((Object _) => const <VisitForm>[]);
    if (!mounted || forms.isEmpty) return;
    final ok = await confirmSheet(
      context,
      title: 'Faire la première visite maintenant ?',
      message:
          'Vous êtes devant le commerce : relevez dès maintenant les produits, le stock et les prix.',
      confirmLabel: 'Visiter',
    );
    if (ok && mounted) await startVisit(context, ref, widget.outletId);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
