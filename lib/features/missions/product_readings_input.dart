import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';

const _labels = {
  'stock': 'Stock',
  'price': 'Prix de vente',
  'sold': 'Vendu',
  'losses': 'Pertes',
  'ordered': 'Commandé',
};

/// « bouteille » → « bouteilles » (sauf mots invariables).
String _plural(String word, num n) {
  final w = word.toLowerCase();
  if (n <= 1 || RegExp(r'[sxz]$').hasMatch(w) || w == 'kg') return w;
  return '${w}s';
}

/// « 41 bouteilles (3 casiers + 5) ».
String formatQuantity(num units, CatalogProduct? product) {
  final unit = product?.unit ?? 'unité';
  final base = '${formatNumber(units)} ${_plural(unit, units)}';
  final packs = [...?product?.packagings]
    ..sort((a, b) => b.units.compareTo(a.units));
  final pack = packs.where((p) => p.units <= units).firstOrNull;
  if (pack == null || units != units.roundToDouble()) return base;
  final n = units ~/ pack.units;
  final rest = units - n * pack.units;
  return '$base ($n ${_plural(pack.name, n)}${rest > 0 ? ' + ${formatNumber(rest)}' : ''})';
}

/// Résumé d'un relevé envoyé : « 3 produits relevés · 1 rupture ».
String readingsSummary(Object? value) {
  if (value is! Map) return '—';
  final ruptures = value.values
      .where((r) => r is Map && r['presence'] == false)
      .length;
  final n = value.length;
  return '$n produit${n > 1 ? 's' : ''} relevé${n > 1 ? 's' : ''}'
      '${ruptures > 0 ? ' · $ruptures rupture${ruptures > 1 ? 's' : ''}' : ''}';
}

/// Relevé par produit : pour chaque produit du champ, les mesures choisies par la
/// structure. Les quantités se saisissent en conditionnements (casiers + bouteilles) et
/// sont envoyées en unités de base.
class ProductReadingsInput extends StatefulWidget {
  const ProductReadingsInput({
    super.key,
    required this.field,
    required this.products,
    required this.value,
    required this.onChanged,
  });

  final MissionField field;
  final List<CatalogProduct> products;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  State<ProductReadingsInput> createState() => _ProductReadingsInputState();
}

class _ProductReadingsInputState extends State<ProductReadingsInput> {
  late final Map<String, Map<String, Object>> _readings = {
    if (widget.value is Map)
      for (final e in (widget.value as Map).entries)
        if (e.value is Map)
          e.key as String: (e.value as Map).cast<String, Object>(),
  };
  String _search = '';

  void _set(
    FormFieldState<Object?> state,
    String productId,
    String measure,
    Object? v,
  ) {
    setState(() {
      final row = {...?_readings[productId]};
      if (v == null) {
        row.remove(measure);
      } else {
        row[measure] = v;
      }
      if (row.isEmpty) {
        _readings.remove(productId);
      } else {
        _readings[productId] = row;
      }
    });
    final out = _readings.isEmpty
        ? null
        : {
            for (final e in _readings.entries) e.key: {...e.value},
          };
    state.didChange(out);
    widget.onChanged(out);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final products = widget.products;
    final needle = _search.trim().toLowerCase();
    final shown = needle.isEmpty
        ? products
        : products
              .where((p) => p.label.toLowerCase().contains(needle))
              .toList();
    return FormField<Object?>(
      initialValue: widget.value,
      validator: (_) => widget.field.required && _readings.isEmpty
          ? 'Relevez au moins un produit'
          : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.field.label}${widget.field.required ? ' *' : ''}',
                  style: text.titleSmall,
                ),
              ),
              Text(
                '${_readings.length}/${products.length} relevé${_readings.length > 1 ? 's' : ''}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (products.isEmpty)
            const InfoBanner(
              icon: Icons.inventory_2_outlined,
              tone: Tone.info,
              message: 'Aucun produit à relever : le catalogue est vide.',
            ),
          if (products.length > 8) ...[
            TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher un produit',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: Space.sm),
          ],
          for (final p in shown) ...[
            _ProductCard(
              product: p,
              measures: widget.field.measures,
              reading: _readings[p.id] ?? const {},
              onSet: (measure, v) => _set(state, p.id, measure, v),
            ),
            const SizedBox(height: Space.sm),
          ],
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                state.errorText!,
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.measures,
    required this.reading,
    required this.onSet,
  });

  final CatalogProduct product;
  final List<String> measures;
  final Map<String, Object> reading;
  final void Function(String measure, Object? value) onSet;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final presence = reading['presence'] as bool?;
    final rupture = presence == false;
    final done = reading.isNotEmpty;
    // En rupture : seule la commande a encore un sens.
    final quantities = measures
        .where((m) => m != 'presence')
        .where((m) => !rupture || m == 'ordered')
        .toList();
    return SurfaceCard(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: done ? toneColor(context, Tone.success) : scheme.outline,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  product.label,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (!product.own)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: toneColor(
                      context,
                      Tone.warning,
                    ).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Concurrent',
                    style: text.labelSmall?.copyWith(
                      color: toneColor(context, Tone.warning),
                    ),
                  ),
                ),
            ],
          ),
          if (measures.contains('presence')) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: _Toggle(
                    label: 'Présent',
                    icon: Icons.check_rounded,
                    selected: presence == true,
                    color: toneColor(context, Tone.success),
                    onTap: () =>
                        onSet('presence', presence == true ? null : true),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: _Toggle(
                    label: 'Rupture',
                    icon: Icons.close_rounded,
                    selected: rupture,
                    color: toneColor(context, Tone.danger),
                    onTap: () => onSet('presence', rupture ? null : false),
                  ),
                ),
              ],
            ),
          ],
          for (final m in quantities) ...[
            const SizedBox(height: Space.sm),
            m == 'price'
                ? _PriceField(
                    product: product,
                    value: reading['price'] as num?,
                    onChanged: (v) => onSet('price', v),
                  )
                : QuantityField(
                    label: _labels[m] ?? m,
                    product: product,
                    value: reading[m] as num?,
                    onChanged: (v) => onSet(m, v),
                  ),
          ],
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? color.withValues(alpha: 0.12) : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? color : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? color : scheme.outline),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? color : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quantité saisie en conditionnements et unités (« 3 casiers + 5 bouteilles »), envoyée
/// en unités de base. Avec plusieurs conditionnements, l'agent choisit celui qu'il compte.
class QuantityField extends StatefulWidget {
  const QuantityField({
    super.key,
    required this.label,
    required this.product,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final CatalogProduct product;
  final num? value;
  final ValueChanged<num?> onChanged;

  @override
  State<QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<QuantityField> {
  late final List<({String name, int units})> _packs = [
    ...widget.product.packagings,
  ]..sort((a, b) => b.units.compareTo(a.units));
  late int _pack = 0;
  late final _packCount = TextEditingController();
  late final _units = TextEditingController();

  @override
  void initState() {
    super.initState();
    final v = widget.value;
    if (v == null) return;
    if (_packs.isEmpty || v != v.roundToDouble()) {
      _units.text = formatInput(v);
      return;
    }
    final size = _packs[_pack].units;
    final n = v ~/ size;
    final rest = v - n * size;
    if (n > 0) _packCount.text = '$n';
    if (rest > 0 || n == 0) _units.text = formatInput(rest);
  }

  @override
  void dispose() {
    _packCount.dispose();
    _units.dispose();
    super.dispose();
  }

  static String formatInput(num v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v'.replaceAll('.', ',');

  static num? _parse(String s) {
    final t = s.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    final n = num.tryParse(t);
    return n == null || n < 0 ? null : n;
  }

  num? get _total {
    final packs = _packs.isEmpty ? null : _parse(_packCount.text);
    final units = _parse(_units.text);
    if (packs == null && units == null) return null;
    return (packs ?? 0) * (_packs.isEmpty ? 0 : _packs[_pack].units) +
        (units ?? 0);
  }

  void _emit() {
    setState(() {});
    widget.onChanged(_total);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = widget.product;
    final total = _total;
    final unitWord = _plural(p.unit, 2);
    Widget box(TextEditingController c, String label) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(isDense: true, labelText: label),
        onChanged: (_) => _emit(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: text.labelLarge),
        if (_packs.length > 1)
          Wrap(
            spacing: 4,
            children: [
              for (final (i, pack) in _packs.indexed)
                ChoiceChip(
                  label: Text('En ${pack.name.toLowerCase()}s'),
                  selected: _pack == i,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    _pack = i;
                    _emit();
                  },
                ),
            ],
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (_packs.isNotEmpty) ...[
              box(_packCount, _plural(_packs[_pack].name, 2)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('+'),
              ),
            ],
            box(_units, unitWord),
          ],
        ),
        if (total != null && _packs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '= ${formatQuantity(total, p)}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _PriceField extends StatefulWidget {
  const _PriceField({
    required this.product,
    required this.value,
    required this.onChanged,
  });

  final CatalogProduct product;
  final num? value;
  final ValueChanged<num?> onChanged;

  @override
  State<_PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends State<_PriceField> {
  late final _c = TextEditingController(
    text: widget.value == null
        ? ''
        : _QuantityFieldState.formatInput(widget.value!),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      isDense: true,
      labelText: 'Prix de vente',
      suffixText: 'FCFA / ${widget.product.unit.toLowerCase()}',
    ),
    onChanged: (v) => widget.onChanged(_QuantityFieldState._parse(v)),
  );
}
