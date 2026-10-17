import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/sync.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/product_readings_input.dart' show UnitQuantityField;
import '../outlets/outlets_controller.dart';
import 'orders.dart';

/// Prise de commande chez un point de vente : les produits aux prix de son type de client,
/// la quantité en unités (casiers, packs… calculés d'eux-mêmes), le total en direct.
/// Fonctionne sans réseau. Peut repartir d'une commande précédente (« Commander à nouveau ») :
/// mêmes produits et quantités, aux prix du jour, modifiables avant de valider.
class OrderEditorScreen extends ConsumerStatefulWidget {
  const OrderEditorScreen({super.key, required this.outletId, this.copyOf});

  final String outletId;

  /// Commande reprise : ses lignes pré-remplissent les quantités.
  final OrderDetail? copyOf;

  @override
  ConsumerState<OrderEditorScreen> createState() => _OrderEditorScreenState();
}

class _OrderEditorScreenState extends ConsumerState<OrderEditorScreen> {
  final _quantities = <String, num>{};
  final _note = TextEditingController();
  final _search = TextEditingController();
  bool _saving = false;
  String? _error;

  /// Produits de la commande reprise, en tête de liste.
  late final Set<String> _copied = {
    for (final l in widget.copyOf?.lines ?? const <OrderLine>[]) l.product.id,
  };

  @override
  void initState() {
    super.initState();
    for (final l in widget.copyOf?.lines ?? const <OrderLine>[]) {
      _quantities[l.product.id] = (_quantities[l.product.id] ?? 0) + l.quantity;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  num _total(OrderCatalog c) => c.products.fold<num>(
    0,
    (s, p) => s + (_quantities[p.product.id] ?? 0) * p.price,
  );

  Future<void> _submit(OrderCatalog catalog, String outletName) async {
    // Seulement les produits encore au catalogue de ce point de vente.
    final offered = {for (final p in catalog.products) p.product.id};
    final lines = {
      for (final e in _quantities.entries)
        if (e.value > 0 && offered.contains(e.key)) e.key: e.value,
    };
    if (lines.isEmpty) {
      setState(() => _error = 'Saisissez la quantité d’au moins un produit.');
      return;
    }
    final total = _total(catalog);
    final ok = await confirmSheet(
      context,
      title: 'Valider la commande ?',
      message:
          '${lines.length} produit${lines.length > 1 ? 's' : ''} pour ${formatMoney(total, catalog.currency)} chez $outletName.',
      confirmLabel: 'Valider',
    );
    if (!ok || !mounted) return;
    tapFeedback();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final (outcome, order) = await sendOrder(
        ref,
        outletId: widget.outletId,
        outletName: outletName,
        quantities: lines,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      if (outcome == SubmitOutcome.queued || order == null) {
        context.pop();
        showMessage(
          context,
          'Commande enregistrée sur le téléphone : elle sera envoyée au retour du réseau.',
        );
      } else {
        context.pushReplacement('/orders/${order.id}');
        showMessage(context, 'Commande ${order.reference} enregistrée.');
      }
    } catch (error) {
      final e = ApiException.from(error);
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final catalog = ref.watch(orderCatalogProvider(widget.outletId));
    final outlet = ref.watch(outletProvider(widget.outletId)).value?.outlet;
    final c = catalog.value;
    final needle = _search.text.trim().toLowerCase();
    final shown = [
      for (final p in c?.products ?? const <PricedProduct>[])
        if (needle.isEmpty || p.product.label.toLowerCase().contains(needle)) p,
    ];
    if (_copied.isNotEmpty) {
      shown.sort(
        (a, b) =>
            (_copied.contains(a.product.id) ? 0 : 1) -
            (_copied.contains(b.product.id) ? 0 : 1),
      );
    }
    final offered = {
      for (final p in c?.products ?? const <PricedProduct>[]) p.product.id,
    };
    final count = _quantities.entries
        .where((e) => e.value > 0 && offered.contains(e.key))
        .length;
    final gone = [
      for (final l in widget.copyOf?.lines ?? const <OrderLine>[])
        if (c != null && !offered.contains(l.product.id)) l.name,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(outlet?.name ?? 'Commande')),
      body: switch (catalog) {
        AsyncError(:final error) when c == null => Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: ApiException.from(error).message,
          ),
        ),
        _ when c == null => const Center(child: CircularProgressIndicator()),
        _ when c.products.isEmpty => Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.sell_outlined,
            tone: Tone.info,
            message: c.priceList == null
                ? 'Aucun type de client n’est défini : demandez à votre administrateur de fixer les prix.'
                : 'Aucun produit n’a de prix pour le type « ${c.priceList} ». Demandez à votre administrateur de les fixer.',
          ),
        ),
        _ => ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.xs,
            Space.page,
            Space.xl,
          ),
          children: [
            if (_error != null) ...[
              InfoBanner(
                icon: Icons.error_outline_rounded,
                tone: Tone.danger,
                message: _error!,
              ),
              const SizedBox(height: Space.md),
            ],
            if (widget.copyOf case final o?) ...[
              InfoBanner(
                icon: Icons.replay_rounded,
                tone: Tone.info,
                message:
                    'Reprise de ${o.order.reference} : vérifiez les quantités. Les prix sont ceux du jour.',
              ),
              const SizedBox(height: Space.sm),
            ],
            if (gone.isNotEmpty) ...[
              InfoBanner(
                icon: Icons.info_outline_rounded,
                tone: Tone.warning,
                message:
                    'Plus proposé${gone.length > 1 ? 's' : ''} à ce point de vente, retiré${gone.length > 1 ? 's' : ''} : ${gone.join(', ')}.',
              ),
              const SizedBox(height: Space.sm),
            ],
            Text(
              'Tarif ${c.priceList} · saisissez les quantités commandées.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (c.products.length > 6) ...[
              const SizedBox(height: Space.sm),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Chercher un produit',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: Space.md),
            for (final p in shown) ...[
              _ProductLine(
                key: ValueKey(p.product.id),
                item: p,
                currency: c.currency,
                quantity: _quantities[p.product.id],
                onChanged: (q) => setState(() {
                  if (q == null || q == 0) {
                    _quantities.remove(p.product.id);
                  } else {
                    _quantities[p.product.id] = q;
                  }
                  _error = null;
                }),
              ),
              const SizedBox(height: Space.sm),
            ],
            const SizedBox(height: Space.sm),
            TextField(
              controller: _note,
              maxLines: 2,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (facultatif)',
                hintText: 'Ex. : livrer avant midi',
              ),
            ),
          ],
        ),
      },
      bottomNavigationBar: c == null || c.products.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.sm,
                  Space.page,
                  Space.sm,
                ),
                child: PillButton(
                  label: count == 0
                      ? 'Valider la commande'
                      : 'Valider · ${formatMoney(_total(c), c.currency)}',
                  icon: Icons.shopping_cart_checkout_rounded,
                  loading: _saving,
                  onPressed: _saving
                      ? null
                      : () => _submit(c, outlet?.name ?? 'ce point de vente'),
                ),
              ),
            ),
    );
  }
}

/// Un produit : prix (à l'unité et au plus grand conditionnement), quantité, montant.
class _ProductLine extends StatelessWidget {
  const _ProductLine({
    super.key,
    required this.item,
    required this.currency,
    required this.quantity,
    required this.onChanged,
  });

  final PricedProduct item;
  final String currency;
  final num? quantity;
  final ValueChanged<num?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = item.product;
    final packs = [...p.packagings]..sort((a, b) => b.units.compareTo(a.units));
    final pack = packs.firstOrNull;
    final q = quantity ?? 0;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.label,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (q > 0)
                Text(
                  formatMoney(q * item.price, currency),
                  style: text.titleSmall?.copyWith(color: scheme.primary),
                ),
            ],
          ),
          Text(
            [
              '${formatMoney(item.price, currency)} / ${p.unit.toLowerCase()}',
              if (pack != null)
                '${formatMoney(item.price * pack.units, currency)} / ${pack.name.toLowerCase()}',
            ].join(' · '),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.sm),
          UnitQuantityField(product: p, value: quantity, onChanged: onChanged),
        ],
      ),
    );
  }
}
