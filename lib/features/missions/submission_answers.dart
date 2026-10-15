import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../outlets/outlet_widgets.dart' show RemotePhoto;
import 'field_display.dart';
import 'product_readings_input.dart' show formatQuantity;

/// Tout un formulaire envoyé : les réponses, les photos en image (pas seulement « Photo
/// jointe ») et le relevé produit par produit.
class SubmissionAnswers extends StatelessWidget {
  const SubmissionAnswers({
    super.key,
    required this.fields,
    required this.data,
    this.products = const {},
  });

  final List<MissionField> fields;
  final Map<String, dynamic> data;

  /// Produits des champs « Relevé par produit », par clé de champ (leurs noms et unités).
  final Map<String, List<CatalogProduct>> products;

  bool _empty(Object? v) => v == null || v == '' || (v is Map && v.isEmpty);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final simple = [
      for (final f in fields)
        if (f.type != FieldType.photo && f.type != FieldType.products) f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (simple.isNotEmpty)
          GroupedList(
            header: 'Réponses',
            indent: Space.lg,
            children: [
              for (final f in simple)
                ListRow(
                  title: f.label,
                  value: _empty(data[f.key])
                      ? '—'
                      : fieldDisplay(f, data[f.key]),
                ),
            ],
          ),
        for (final f in fields)
          if (f.type == FieldType.photo) ...[
            SectionHeader(f.label),
            if (data[f.key] is String)
              RemotePhoto(
                id: data[f.key] as String,
                label: f.label,
                height: 220,
              )
            else
              Text(
                'Pas de photo.',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ] else if (f.type == FieldType.products) ...[
            SectionHeader(f.label),
            if (data[f.key] is Map && (data[f.key] as Map).isNotEmpty)
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, e)
                        in (data[f.key] as Map).entries.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 52),
                      ReadingRow(
                        product:
                            products[f.key]
                                ?.where((p) => p.id == e.key)
                                .firstOrNull ??
                            CatalogProduct(
                              id: e.key as String,
                              name: 'Produit',
                              own: true,
                              unit: 'Unité',
                            ),
                        values: (e.value as Map).cast<String, dynamic>(),
                      ),
                    ],
                  ],
                ),
              )
            else
              Text(
                'Aucun produit relevé.',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
      ],
    );
  }
}

/// Relevé d'un produit : présent ou en rupture, stock (en conditionnements), prix, ventes,
/// pertes, commandé ; « concurrent » pour les produits de la concurrence.
class ReadingRow extends StatelessWidget {
  const ReadingRow({super.key, required this.product, required this.values});

  final CatalogProduct product;

  /// presence, stock, price, sold, losses, ordered (quantités en unités de base).
  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final presence = values['presence'] as bool?;
    num? n(String k) => values[k] as num?;
    final out = presence == false;
    final danger = toneColor(context, Tone.danger);
    final details = [
      if (out) 'Rupture',
      if (!out && n('stock') != null)
        'Stock ${formatQuantity(n('stock')!, product)}',
      if (n('price') != null) formatMoney(n('price')!),
      if (n('sold') != null) 'Vendu ${formatQuantity(n('sold')!, product)}',
      if ((n('losses') ?? 0) > 0)
        'Pertes ${formatQuantity(n('losses')!, product)}',
      if ((n('ordered') ?? 0) > 0)
        'Commandé ${formatQuantity(n('ordered')!, product)}',
    ];
    return ListTile(
      leading: Icon(
        out
            ? Icons.cancel_rounded
            : presence == true
            ? Icons.check_circle_rounded
            : Icons.inventory_2_outlined,
        color: out
            ? danger
            : presence == true
            ? toneColor(context, Tone.success)
            : scheme.onSurfaceVariant,
        semanticLabel: out
            ? 'En rupture'
            : presence == true
            ? 'Présent'
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              product.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!product.own) ...[
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
