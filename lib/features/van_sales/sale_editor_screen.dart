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
import '../missions/product_readings_input.dart'
    show UnitQuantityField, formatQuantity;
import '../orders/orders.dart';
import '../outlets/outlets_controller.dart';
import 'transfers.dart';
import 'van_sales.dart';

/// Vente directe depuis le camion : les produits aux prix du client, dans la limite du stock
/// du camion ; payée sur place en tout ou partie, le reste à crédit si le client y a droit
/// (dans la limite de son plafond). Fonctionne sans réseau.
class SaleEditorScreen extends ConsumerStatefulWidget {
  const SaleEditorScreen({
    super.key,
    required this.outletId,
    this.outOfZone = false,
  });

  final String outletId;

  /// Client hors de la zone de l'agent (vente d'urgence) : motif obligatoire, vendu sur place.
  final bool outOfZone;

  @override
  ConsumerState<SaleEditorScreen> createState() => _SaleEditorScreenState();
}

class _SaleEditorScreenState extends ConsumerState<SaleEditorScreen> {
  final _quantities = <String, num>{};
  final _paid = TextEditingController();
  final _search = TextEditingController();
  final _reason = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  /// L'agent a modifié le montant payé : il ne suit plus le total.
  bool _paidEdited = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _paid.dispose();
    _search.dispose();
    _reason.dispose();
    super.dispose();
  }

  num _total(OrderCatalog c) => c.products.fold<num>(
    0,
    (s, p) => s + (_quantities[p.product.id] ?? 0) * p.price,
  );

  num get _paidAmount =>
      num.tryParse(_paid.text.replaceAll(RegExp(r'[\s  ]'), '')) ?? 0;

  /// Montant payé = total, tant que l'agent ne l'a pas changé.
  void _syncPaid(OrderCatalog c) {
    if (_paidEdited) return;
    final total = _total(c);
    _paid.text = total == 0 ? '' : total.round().toString();
  }

  /// Ce qui empêche la vente, ou null.
  String? _problem(OrderCatalog c, MyVan van, OutletBalance? balance) {
    final total = _total(c);
    if (total == 0) return null;
    for (final p in c.products) {
      final q = _quantities[p.product.id] ?? 0;
      if (q > van.quantityOf(p.product.id)) {
        return 'Pas assez de « ${p.product.label} » dans le camion : ${formatQuantity(van.quantityOf(p.product.id), p.product)}.';
      }
    }
    final paid = _paidAmount;
    if (paid > total) return 'Le montant payé dépasse le total.';
    final credit = total - paid;
    if (credit > 0 && balance != null) {
      if (!balance.creditAllowed) {
        return 'Ce client n’a pas droit au crédit : la vente doit être payée en entier.';
      }
      if (credit > balance.available) {
        return 'Crédit possible pour ce client : ${formatMoney(balance.available, c.currency)} au plus.';
      }
    }
    return null;
  }

  Future<void> _submit(
    OrderCatalog catalog,
    MyVan van,
    OutletBalance? balance,
    String outletName,
  ) async {
    final offered = {for (final p in catalog.products) p.product.id};
    final lines = {
      for (final e in _quantities.entries)
        if (e.value > 0 && offered.contains(e.key)) e.key: e.value,
    };
    if (lines.isEmpty) {
      setState(() => _error = 'Saisissez la quantité d’au moins un produit.');
      return;
    }
    if (widget.outOfZone && _reason.text.trim().length < 3) {
      setState(() => _error = 'Indiquez le motif de cette vente hors zone.');
      return;
    }
    final problem = _problem(catalog, van, balance);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final total = _total(catalog);
    final paid = _paidAmount;
    final credit = total - paid;
    final ok = await confirmSheet(
      context,
      title: 'Valider la vente ?',
      message: [
        '${formatMoney(total, catalog.currency)} chez $outletName.',
        if (paid > 0)
          'Payé : ${formatMoney(paid, catalog.currency)} (${_method.label.toLowerCase()}).',
        if (credit > 0) 'À crédit : ${formatMoney(credit, catalog.currency)}.',
      ].join(' '),
      confirmLabel: 'Valider la vente',
    );
    if (!ok || !mounted) return;
    tapFeedback();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final (outcome, order) = await sendSale(
        ref,
        outletId: widget.outletId,
        outletName: outletName,
        quantities: lines,
        total: total,
        paidAmount: paid,
        method: paid > 0 ? _method : null,
        outOfZoneReason: widget.outOfZone ? _reason.text.trim() : null,
      );
      if (!mounted) return;
      if (outcome == SubmitOutcome.queued || order == null) {
        context.pop();
        showMessage(
          context,
          'Vente enregistrée sur le téléphone : elle sera envoyée au retour du réseau.',
        );
      } else {
        context.pushReplacement('/orders/${order.id}');
        showMessage(context, 'Vente ${order.reference} enregistrée.');
      }
    } catch (error) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = ApiException.from(error).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Hors zone : client, prix et crédit chargés d'un bloc (client hors du secteur).
    final context0 = widget.outOfZone
        ? ref.watch(outOfZoneContextProvider(widget.outletId))
        : null;
    final AsyncValue<OrderCatalog> catalog = context0 != null
        ? context0.whenData((c) => c.catalog)
        : ref.watch(orderCatalogProvider(widget.outletId));
    final vanState = ref.watch(myVanProvider);
    final balance = widget.outOfZone
        ? context0?.value?.balance
        : ref.watch(outletBalanceProvider(widget.outletId)).value;
    final outletName = widget.outOfZone
        ? context0?.value?.name
        : ref.watch(outletProvider(widget.outletId)).value?.outlet.name;
    final c = catalog.value;
    final van = vanState.value;
    final error = catalog.error ?? vanState.error;
    // Seulement ce que le camion transporte (ou ce que l'agent a déjà saisi).
    final needle = _search.text.trim().toLowerCase();
    final shown = [
      for (final p in c?.products ?? const <PricedProduct>[])
        if (van != null &&
            (van.quantityOf(p.product.id) > 0 ||
                (_quantities[p.product.id] ?? 0) > 0) &&
            (needle.isEmpty || p.product.label.toLowerCase().contains(needle)))
          p,
    ];
    final total = c == null ? 0 : _total(c);
    final problem = c == null || van == null ? null : _problem(c, van, balance);

    return Scaffold(
      appBar: AppBar(title: Text(outletName ?? 'Vente')),
      body: switch ((c, van)) {
        _ when error != null && (c == null || van == null) => Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: ApiException.from(error).message,
          ),
        ),
        (null, _) ||
        (_, null) => const Center(child: CircularProgressIndicator()),
        (_, final MyVan v) when v.van == null => const Padding(
          padding: EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.local_shipping_outlined,
            tone: Tone.info,
            message:
                'Aucun camion ne vous est affecté : vous ne pouvez pas vendre directement. Demandez à votre responsable.',
          ),
        ),
        (final OrderCatalog cat, _) when cat.products.isEmpty => Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.sell_outlined,
            tone: Tone.info,
            message: cat.priceList == null
                ? 'Aucun type de client n’est défini : demandez à votre administrateur de fixer les prix.'
                : 'Aucun produit n’a de prix pour le type « ${cat.priceList} ».',
          ),
        ),
        (final OrderCatalog cat, final MyVan v) => ListView(
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
            if (widget.outOfZone) ...[
              InfoBanner(
                icon: Icons.wrong_location_outlined,
                tone: Tone.warning,
                message:
                    'Client hors de votre secteur${context0?.value?.zoneName == null ? '' : ' (zone ${context0!.value!.zoneName})'} : vente possible seulement sur place, avec un motif. Vos chefs sont prévenus.',
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: _reason,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motif de la vente hors zone *',
                  hintText: 'Ex. : rupture urgente, son commercial est absent',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: Space.sm),
            ],
            Text(
              'Tarif ${cat.priceList} · ${v.van!.name}. Saisissez les quantités vendues.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (shown.length > 6 || needle.isNotEmpty) ...[
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
            if (shown.isEmpty)
              const InfoBanner(
                icon: Icons.inventory_2_outlined,
                tone: Tone.info,
                message:
                    'Votre camion ne contient aucun produit proposé à ce client.',
              ),
            for (final p in shown) ...[
              _SaleLine(
                key: ValueKey(p.product.id),
                item: p,
                currency: cat.currency,
                inVan: v.quantityOf(p.product.id),
                quantity: _quantities[p.product.id],
                onChanged: (q) => setState(() {
                  if (q == null || q == 0) {
                    _quantities.remove(p.product.id);
                  } else {
                    _quantities[p.product.id] = q;
                  }
                  _error = null;
                  _syncPaid(cat);
                }),
              ),
              const SizedBox(height: Space.sm),
            ],
            if (total > 0) ...[
              const SizedBox(height: Space.md),
              _Payment(
                currency: cat.currency,
                total: total,
                paid: _paid,
                method: _method,
                balance: balance,
                onMethod: (m) => setState(() => _method = m),
                onPaidChanged: () => setState(() {
                  _paidEdited = true;
                  _error = null;
                }),
              ),
            ],
            if (problem != null && _error == null) ...[
              const SizedBox(height: Space.md),
              InfoBanner(
                icon: Icons.info_outline_rounded,
                tone: Tone.warning,
                message: problem,
              ),
            ],
          ],
        ),
      },
      bottomNavigationBar: c == null || van?.van == null || c.products.isEmpty
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
                  // Le crédit est détaillé juste au-dessus (carte « Paiement »).
                  label: total == 0
                      ? 'Valider la vente'
                      : 'Valider · ${formatMoney(total, c.currency)}',
                  icon: Icons.point_of_sale_rounded,
                  loading: _saving,
                  onPressed: _saving || problem != null
                      ? null
                      : () => _submit(
                          c,
                          van!,
                          balance,
                          outletName ?? 'ce point de vente',
                        ),
                ),
              ),
            ),
    );
  }
}

/// Un produit : prix, stock du camion, quantité vendue, montant.
class _SaleLine extends StatelessWidget {
  const _SaleLine({
    super.key,
    required this.item,
    required this.currency,
    required this.inVan,
    required this.quantity,
    required this.onChanged,
  });

  final PricedProduct item;
  final String currency;
  final num inVan;
  final num? quantity;
  final ValueChanged<num?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = item.product;
    final q = quantity ?? 0;
    final over = q > inVan;
    return SurfaceCard(
      border: over ? BorderSide(color: toneColor(context, Tone.danger)) : null,
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
            '${formatMoney(item.price, currency)} / ${p.unit.toLowerCase()} · camion : ${formatQuantity(inVan, p)}',
            style: text.bodySmall?.copyWith(
              color: over
                  ? toneColor(context, Tone.danger)
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.sm),
          UnitQuantityField(product: p, value: quantity, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Paiement sur place : montant (le total par défaut) et moyen ; le reste à crédit.
class _Payment extends StatelessWidget {
  const _Payment({
    required this.currency,
    required this.total,
    required this.paid,
    required this.method,
    required this.balance,
    required this.onMethod,
    required this.onPaidChanged,
  });

  final String currency;
  final num total;
  final TextEditingController paid;
  final PaymentMethod method;
  final OutletBalance? balance;
  final ValueChanged<PaymentMethod> onMethod;
  final VoidCallback onPaidChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final amount =
        num.tryParse(paid.text.replaceAll(RegExp(r'[\s  ]'), '')) ?? 0;
    final credit = total - amount;
    final b = balance;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Paiement · total ${formatMoney(total, currency)}',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: paid,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Payé maintenant',
              suffixText: currency == 'XOF' ? 'F CFA' : currency,
            ),
            onChanged: (_) => onPaidChanged(),
          ),
          if (amount > 0) ...[
            const SizedBox(height: Space.sm),
            AppSegmented<PaymentMethod>(
              segments: {for (final m in PaymentMethod.values) m: m.label},
              selected: method,
              onChanged: onMethod,
            ),
          ],
          const SizedBox(height: Space.sm),
          Text(
            credit > 0
                ? 'À crédit : ${formatMoney(credit, currency)}'
                : 'Payée en entier',
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (b != null)
            Text(
              !b.creditAllowed
                  ? 'Ce client n’a pas droit au crédit.'
                  : 'Crédit possible : ${formatMoney(b.available, currency)}${b.outstanding > 0 ? ' · doit déjà ${formatMoney(b.outstanding, currency)}' : ''}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
