import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/product_readings_input.dart' show formatQuantity;
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
  });

  final String id;

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

/// Fiche : le dernier relevé de chaque produit (nos produits d'abord, puis la concurrence).
class OutletProductsSection extends ConsumerWidget {
  const OutletProductsSection({super.key, required this.outletId});

  final String outletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(outletReadingsProvider(outletId));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final list = readings.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Produits relevés'),
        if (list == null && readings.isLoading)
          const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list == null)
          Text(
            'Relevés indisponibles hors connexion.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else if (list.isEmpty)
          SurfaceCard(
            child: Text(
              'Aucun relevé pour le moment : faites une visite pour noter la présence, le stock et le prix des produits.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, r) in list.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 52),
                  _ReadingRow(reading: r),
                ],
              ],
            ),
          ),
      ],
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

/// Fiche : les dernières visites (missions et visites libres), rejetées signalées.
class OutletVisitsSection extends StatelessWidget {
  const OutletVisitsSection({super.key, required this.visits});

  final List<OutletVisitEntry> visits;

  /// Visites montrées sur la fiche.
  static const shown = 5;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Dernières visites'),
        if (visits.isEmpty)
          SurfaceCard(
            child: Text(
              'Pas encore de visite.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, v) in visits.take(shown).indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 52),
                  ListTile(
                    leading: Icon(
                      v.rejected
                          ? Icons.block_rounded
                          : Icons.assignment_turned_in_outlined,
                      color: v.rejected
                          ? toneColor(context, Tone.danger)
                          : scheme.primary,
                    ),
                    title: Text(
                      v.missionId == null
                          ? 'Visite libre · ${v.formName}'
                          : v.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        '${formatShortDate(v.at)} à ${formatTime(v.at)}',
                        if (v.agent.isNotEmpty) v.agent,
                        if (v.rejected) 'rejetée',
                      ].join(' · '),
                      style: v.rejected
                          ? TextStyle(color: toneColor(context, Tone.danger))
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
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
