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

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Période des `days` derniers jours, aujourd'hui compris.
({String from, String to}) lastDays(int days) {
  final now = DateTime.now();
  return (from: _day(now.subtract(Duration(days: days - 1))), to: _day(now));
}

/// Formulaire rempli sur la période.
class FormUsage {
  FormUsage(this.id, this.name, this.submissions);

  final String id;
  final String name;
  final int submissions;
}

/// Formulaires remplis sur les `days` derniers jours, les plus utilisés d'abord.
final formUsageProvider = FutureProvider.autoDispose
    .family<List<FormUsage>, int>((ref, days) async {
      final p = lastDays(days);
      final json = await ref
          .read(repositoryProvider)
          .formStats(from: p.from, to: p.to);
      return [
        for (final f in json['forms'] as List)
          FormUsage(
            (f as Map)['id'] as String,
            f['name'] as String,
            (f['submissions'] as num).toInt(),
          ),
      ];
    });

/// Statistiques d'un formulaire sur les `days` derniers jours.
final formStatsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String typeId, int days})>((ref, key) {
      final p = lastDays(key.days);
      return ref
          .read(repositoryProvider)
          .formFieldStats(key.typeId, from: p.from, to: p.to);
    });

/// Les formulaires créés par la structure, en chiffres : l'agent choisit un formulaire, et
/// chaque champ est résumé selon son type (total d'un nombre, part de « Oui », répartition
/// d'une liste, photos prises, relevé produit par produit).
class FormStatsSection extends ConsumerStatefulWidget {
  const FormStatsSection({super.key, required this.days});

  final int days;

  @override
  ConsumerState<FormStatsSection> createState() => _FormStatsSectionState();
}

class _FormStatsSectionState extends ConsumerState<FormStatsSection> {
  String? _typeId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final usage = ref.watch(formUsageProvider(widget.days));
    final forms = usage.value;
    final leader = ref.watch(meProvider).isTeamLead;
    // Le formulaire choisi, sinon le plus utilisé de la période.
    final selected =
        forms?.where((f) => f.id == _typeId).firstOrNull ?? forms?.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(leader ? 'Formulaires de l’équipe' : 'Mes formulaires'),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Text(
            'D’après les formulaires remplis (visites et missions), champ par champ.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (usage.hasError && forms == null)
          InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: ApiException.from(usage.error!).message,
          )
        else if (forms == null)
          const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (forms.isEmpty)
          const InfoBanner(
            icon: Icons.info_outline_rounded,
            tone: Tone.info,
            message:
                'Aucun formulaire envoyé sur la période. Les chiffres apparaissent dès les premières visites ou missions.',
          )
        else ...[
          // Tous les formulaires visibles (pas de défilement caché).
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in forms)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text('${f.name} (${f.submissions})'),
                  selected: f.id == selected!.id,
                  onSelected: (_) => setState(() => _typeId = f.id),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          _FormStats(typeId: selected!.id, days: widget.days),
        ],
        const SizedBox(height: Space.xs),
        Text(
          'Formulaires acceptés seulement : un formulaire rejeté ne compte pas.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _FormStats extends ConsumerStatefulWidget {
  const _FormStats({required this.typeId, required this.days});

  final String typeId;
  final int days;

  @override
  ConsumerState<_FormStats> createState() => _FormStatsState();
}

class _FormStatsState extends ConsumerState<_FormStats> {
  /// Questions montrées d'abord ; les autres se déplient.
  static const _shown = 4;
  bool _all = false;

  String get typeId => widget.typeId;
  int get days => widget.days;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(formStatsProvider((typeId: typeId, days: days)));
    final s = stats.value;
    if (s == null) {
      return stats.hasError
          ? InfoBanner(
              icon: Icons.wifi_off_rounded,
              message: ApiException.from(stats.error!).message,
            )
          : const Padding(
              padding: EdgeInsets.all(Space.lg),
              child: Center(child: CircularProgressIndicator()),
            );
    }
    final text = Theme.of(context).textTheme;
    final n = (s['submissions'] as num).toInt();
    final outlets = (s['outlets'] as num).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          [
            '$n formulaire${n > 1 ? 's' : ''}',
            if (outlets > 0) '$outlets point${outlets > 1 ? 's' : ''} de vente',
          ].join(' · '),
          style: text.bodyMedium,
        ),
        const SizedBox(height: Space.sm),
        for (final f in (s['fields'] as List).cast<Map<String, dynamic>>().take(
          _all ? 1 << 20 : _shown,
        )) ...[
          _FieldCard(field: f, total: n),
          const SizedBox(height: Space.sm),
        ],
        if ((s['fields'] as List).length > _shown)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(
              _all
                  ? 'Voir moins'
                  : 'Voir les ${(s['fields'] as List).length} questions',
            ),
          ),
      ],
    );
  }
}

/// Un champ du formulaire, résumé selon son type.
class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.field, required this.total});

  final Map<String, dynamic> field;

  /// Formulaires de la période (pour « 12 réponses sur 15 »).
  final int total;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = (field['stats'] as Map).cast<String, dynamic>();
    final answered = (s['answered'] as num).toInt();
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final big = text.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    final replies = '$answered réponse${answered > 1 ? 's' : ''} sur $total';

    final List<Widget> body = switch (s['kind']) {
      'number' => [
        Text(formatNumber(s['sum'] as num), style: big),
        Text(
          s['avg'] == null
              ? replies
              : [
                  'moyenne ${formatNumber(s['avg'] as num)}',
                  'de ${formatNumber(s['min'] as num)} à ${formatNumber(s['max'] as num)}',
                  replies,
                ].join(' · '),
          style: muted,
        ),
      ],
      'boolean' => [
        Text(
          s['yesRate'] == null ? '—' : '${s['yesRate']} % de Oui',
          style: big,
        ),
        if (s['yesRate'] != null) ...[
          const SizedBox(height: 4),
          ThinProgress(value: (s['yesRate'] as num) / 100),
        ],
        const SizedBox(height: 4),
        Text('Oui ${s['yes']} · Non ${s['no']}', style: muted),
      ],
      'select' => [
        for (final o
            in (s['options'] as List).cast<Map<String, dynamic>>()) ...[
          Row(
            children: [
              Expanded(child: Text(o['value'] as String)),
              Text(
                answered == 0
                    ? '${o['count']}'
                    : '${o['count']} · ${((o['count'] as num) * 100 / answered).round()} %',
                style: text.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ThinProgress(
            value: answered == 0 ? 0 : (o['count'] as num) / answered,
          ),
          const SizedBox(height: Space.sm),
        ],
        Text(replies, style: muted),
      ],
      'photo' => [
        Text('$answered photo${answered > 1 ? 's' : ''}', style: big),
        Text(
          'prises sur $total formulaire${total > 1 ? 's' : ''}',
          style: muted,
        ),
      ],
      'products' => [
        for (final p in (s['products'] as List).cast<Map<String, dynamic>>())
          _ProductLine(product: p),
        if ((s['products'] as List).isEmpty)
          Text('Aucun produit relevé.', style: muted),
      ],
      _ => [
        Text(replies, style: muted),
        Text(
          'Réponses libres : à lire dans l’historique des visites.',
          style: muted,
        ),
      ],
    };

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(field['label'] as String, style: text.titleSmall),
          const SizedBox(height: Space.xs),
          ...body,
        ],
      ),
    );
  }
}

/// Un produit d'un relevé : ruptures, stock moyen, prix moyen, ventes.
class _ProductLine extends StatelessWidget {
  const _ProductLine({required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = product;
    final catalog = CatalogProduct.fromJson({
      'id': p['productId'],
      'name': p['name'],
      'format': p['format'],
      'own': p['own'],
      'unit': p['unit'],
      'packagings': p['packagings'],
    });
    final checked = (p['checked'] as num).toInt();
    final stockouts = (p['stockouts'] as num).toInt();
    final details = [
      if (checked > 0) 'rupture $stockouts/$checked',
      if (p['avgStock'] != null)
        'stock moyen ${formatQuantity(p['avgStock'] as num, catalog)}',
      if (p['avgPrice'] != null)
        'prix moyen ${formatMoney(p['avgPrice'] as num)}',
      if ((p['sold'] as num) > 0)
        'vendu ${formatQuantity(p['sold'] as num, catalog)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  catalog.label,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!catalog.own) ...[
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
            details.isEmpty ? '—' : details.join(' · '),
            style: text.bodySmall?.copyWith(
              color: stockouts > 0
                  ? toneColor(context, Tone.danger)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
