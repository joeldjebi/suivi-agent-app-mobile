import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/sync.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/common.dart';
import '../missions/product_readings_input.dart'
    show UnitQuantityField, formatQuantity;
import 'transfer_screens.dart';
import 'van_sales.dart';

/// « Mon camion » : le stock du camion (ventes faites sans réseau déjà déduites), les
/// chargements à confirmer, la journée (ventes, encaissements, argent à remettre) et les
/// déclarations de l'agent (casse, retour au dépôt).
class VanScreen extends ConsumerWidget {
  const VanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final van = ref.watch(myVanProvider);
    final v = van.value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BrandHeader(title: 'Mon camion', subtitle: v?.van?.label),
            Expanded(
              child: switch (van) {
                AsyncError(:final error) when v == null => Padding(
                  padding: const EdgeInsets.all(Space.page),
                  child: InfoBanner(
                    icon: Icons.wifi_off_rounded,
                    message: ApiException.from(error).message,
                  ),
                ),
                _ when v == null => const Center(
                  child: CircularProgressIndicator(),
                ),
                _ => RefreshIndicator(
                  onRefresh: () async => refreshVan(ref),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      Space.page,
                      Space.sm,
                      Space.page,
                      Space.xl,
                    ),
                    children: v.van == null
                        ? const [
                            InfoBanner(
                              icon: Icons.local_shipping_outlined,
                              tone: Tone.info,
                              message:
                                  'Aucun camion ne vous est affecté. Demandez à votre responsable de vous en confier un.',
                            ),
                          ]
                        : _content(context, v),
                  ),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, MyVan v) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final loads = v.pending.where((m) => m.isLoad).toList();
    final unloads = v.pending.where((m) => !m.isLoad).toList();
    final stock = v.stock.where((s) => s.quantity != 0).toList();
    return [
      if (v.queued > 0) ...[
        InfoBanner(
          icon: Icons.cloud_upload_outlined,
          tone: Tone.info,
          message:
              '${v.queued} opération${v.queued > 1 ? 's' : ''} en attente d’envoi : le stock affiché en tient déjà compte.',
        ),
        const SizedBox(height: Space.md),
      ],
      for (final m in loads) ...[
        SurfaceCard(
          border: BorderSide(color: toneColor(context, Tone.warning)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Chargement à confirmer',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                'Depuis ${m.fromName ?? 'le dépôt'} · ${formatTime(m.at)}${m.byName == null ? '' : ' · ${m.byName}'}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Space.sm),
              for (final l in m.lines)
                Text(
                  '${l.product.label} : ${formatQuantity(l.quantity, l.product)}',
                  style: text.bodyMedium,
                ),
              const SizedBox(height: Space.md),
              PillButton(
                label: 'Vérifier et confirmer',
                icon: Icons.fact_check_outlined,
                onPressed: () => context.push('/van/load/${m.id}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
      ],
      _DayCard(day: v.today),
      const SizedBox(height: Space.lg),
      SectionHeader(
        'Dans le camion',
        trailing: Text(
          '${stock.length} produit${stock.length > 1 ? 's' : ''}',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      if (stock.isEmpty)
        Text(
          'Le camion est vide. Votre responsable prépare votre chargement depuis le dépôt.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        )
      else
        GroupedList(
          indent: 0,
          children: [
            for (final s in stock)
              ListRow(
                title: s.product.label,
                subtitle: formatQuantity(s.quantity, s.product),
                titleColor: s.quantity < 0
                    ? toneColor(context, Tone.danger)
                    : null,
              ),
          ],
        ),
      if (stock.any((s) => s.quantity < 0)) ...[
        const SizedBox(height: Space.sm),
        Text(
          'En rouge : vendu plus que le stock connu. Votre responsable vérifiera.',
          style: text.bodySmall?.copyWith(
            color: toneColor(context, Tone.danger),
          ),
        ),
      ],
      for (final m in unloads) ...[
        const SizedBox(height: Space.md),
        InfoBanner(
          icon: Icons.hourglass_top_rounded,
          tone: Tone.info,
          message:
              'Retour vers ${m.toName ?? 'le dépôt'} déclaré à ${formatTime(m.at)} : en attente de confirmation par votre responsable.',
        ),
      ],
      const SizedBox(height: Space.lg),
      Row(
        children: [
          Expanded(
            child: PillButton(
              label: 'Casse ou perte',
              icon: Icons.heart_broken_outlined,
              style: PillStyle.tonal,
              onPressed: stock.isEmpty ? null : () => context.push('/van/loss'),
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: PillButton(
              label: 'Retour au dépôt',
              icon: Icons.warehouse_outlined,
              style: PillStyle.tonal,
              onPressed: stock.isEmpty || v.depots.isEmpty
                  ? null
                  : () => context.push('/van/unload'),
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.lg),
      const TransfersSection(),
    ];
  }
}

/// Journée : ventes, encaissements, crédit accordé, argent liquide à remettre.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});

  final VanDay day;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget figure(String label, num value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Text(
            formatMoney(value),
            style: text.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
    return SurfaceCard(
      semanticLabel: 'Ma journée',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Aujourd’hui · ${day.salesCount} vente${day.salesCount > 1 ? 's' : ''}',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              figure('Ventes', day.salesAmount),
              figure('Espèces', day.cash),
              figure('Mobile money', day.mobileMoney + day.bank),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              figure('À crédit', day.dueOnSales),
              figure(
                'À remettre',
                day.cashBalance,
                color: day.cashBalance > 0
                    ? toneColor(context, Tone.warning)
                    : null,
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
          if (day.cashBalance > 0) ...[
            const SizedBox(height: Space.sm),
            Text(
              'Remettez l’argent liquide à votre responsable en fin de journée.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Réception d'un chargement : l'agent compte ce qui est arrivé et corrige s'il manque
/// quelque chose (l'écart reste visible pour le responsable).
class LoadConfirmScreen extends ConsumerStatefulWidget {
  const LoadConfirmScreen({super.key, required this.movementId});

  final String movementId;

  @override
  ConsumerState<LoadConfirmScreen> createState() => _LoadConfirmScreenState();
}

class _LoadConfirmScreenState extends ConsumerState<LoadConfirmScreen> {
  final _received = <String, num>{};
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(PendingMovement m) async {
    final gaps = [
      for (final l in m.lines)
        if ((_received[l.product.id] ?? l.quantity) != l.quantity) l,
    ];
    final ok = await confirmSheet(
      context,
      title: 'Confirmer la réception ?',
      message: gaps.isEmpty
          ? 'Tout est arrivé : ${m.lines.length} produit${m.lines.length > 1 ? 's' : ''} entrent dans votre camion.'
          : '${gaps.length} écart${gaps.length > 1 ? 's' : ''} signalé${gaps.length > 1 ? 's' : ''} à votre responsable.',
      confirmLabel: 'Confirmer',
    );
    if (!ok || !mounted) return;
    tapFeedback();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = await confirmLoad(
        ref,
        movement: m,
        received: _received,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        outcome == SubmitOutcome.queued
            ? 'Réception enregistrée : elle sera envoyée au retour du réseau.'
            : 'Chargement reçu : votre stock est à jour.',
      );
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
    final movement = ref
        .watch(myVanProvider)
        .value
        ?.pending
        .where((m) => m.id == widget.movementId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Réception du chargement')),
      body: movement == null
          ? const Padding(
              padding: EdgeInsets.all(Space.page),
              child: InfoBanner(
                icon: Icons.check_circle_outline_rounded,
                tone: Tone.success,
                message: 'Ce chargement est déjà traité.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(Space.page),
              children: [
                if (_error != null) ...[
                  InfoBanner(
                    icon: Icons.error_outline_rounded,
                    tone: Tone.danger,
                    message: _error!,
                  ),
                  const SizedBox(height: Space.md),
                ],
                Text(
                  'Depuis ${movement.fromName ?? 'le dépôt'}. Comptez ce qui est arrivé ; corrigez une quantité s’il manque quelque chose.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.md),
                for (final l in movement.lines) ...[
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.product.label,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Envoyé : ${formatQuantity(l.quantity, l.product)}',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        UnitQuantityField(
                          product: l.product,
                          value: _received[l.product.id] ?? l.quantity,
                          onChanged: (q) =>
                              setState(() => _received[l.product.id] = q ?? 0),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                ],
                TextField(
                  controller: _note,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Note (facultatif)',
                    hintText: 'Ex. : 2 bouteilles cassées',
                  ),
                ),
              ],
            ),
      bottomNavigationBar: movement == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.page),
                child: PillButton(
                  label: 'Confirmer la réception',
                  icon: Icons.check_rounded,
                  loading: _saving,
                  onPressed: _saving ? null : () => _submit(movement),
                ),
              ),
            ),
    );
  }
}

/// Ce que l'agent déclare depuis son camion : une casse (motif obligatoire) ou un retour au
/// dépôt (préparé avec tout le stock restant, pour la fin de tournée).
enum VanDeclaration { loss, unload }

class VanDeclarationScreen extends ConsumerStatefulWidget {
  const VanDeclarationScreen({super.key, required this.kind});

  final VanDeclaration kind;

  @override
  ConsumerState<VanDeclarationScreen> createState() =>
      _VanDeclarationScreenState();
}

class _VanDeclarationScreenState extends ConsumerState<VanDeclarationScreen> {
  Map<String, num>? _quantities;
  final _note = TextEditingController();
  String? _depotId;
  bool _saving = false;
  String? _error;

  bool get _loss => widget.kind == VanDeclaration.loss;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(MyVan v) async {
    final lines = {
      for (final e in (_quantities ?? const {}).entries)
        if (e.value > 0) e.key: e.value,
    };
    if (lines.isEmpty) {
      setState(() => _error = 'Saisissez la quantité d’au moins un produit.');
      return;
    }
    if (_loss && _note.text.trim().isEmpty) {
      setState(
        () => _error = 'Indiquez le motif : casse, vol, produit périmé…',
      );
      return;
    }
    final depot = _depotId ?? v.depots.firstOrNull?.id;
    if (!_loss && depot == null) return;
    final over = [
      for (final e in lines.entries)
        if (e.value > v.quantityOf(e.key)) e.key,
    ];
    if (over.isNotEmpty) {
      setState(
        () => _error = 'Vous déclarez plus que le stock du camion : vérifiez.',
      );
      return;
    }
    final ok = await confirmSheet(
      context,
      title: _loss ? 'Déclarer la casse ?' : 'Déclarer le retour ?',
      message: _loss
          ? '${lines.length} produit${lines.length > 1 ? 's' : ''} sortent de votre camion.'
          : 'Votre responsable confirmera à l’arrivée au dépôt.',
      confirmLabel: 'Déclarer',
    );
    if (!ok || !mounted) return;
    tapFeedback();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = _loss
          ? await sendLoss(ref, quantities: lines, reason: _note.text.trim())
          : await sendUnload(
              ref,
              depotId: depot!,
              quantities: lines,
              note: _note.text.trim(),
            );
      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        outcome == SubmitOutcome.queued
            ? 'Enregistré sur le téléphone : envoyé au retour du réseau.'
            : _loss
            ? 'Casse déclarée : votre stock est à jour.'
            : 'Retour déclaré : en attente de confirmation au dépôt.',
      );
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
    final v = ref.watch(myVanProvider).value;
    final stock = (v?.stock ?? const <StockLine>[])
        .where((s) => s.quantity > 0)
        .toList();
    // Fin de tournée : tout ce qui reste rentre au dépôt (modifiable).
    _quantities ??= v == null
        ? null
        : {
            if (!_loss)
              for (final s in stock) s.product.id: s.quantity,
          };
    return Scaffold(
      appBar: AppBar(title: Text(_loss ? 'Casse ou perte' : 'Retour au dépôt')),
      body: v == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Space.page),
              children: [
                if (_error != null) ...[
                  InfoBanner(
                    icon: Icons.error_outline_rounded,
                    tone: Tone.danger,
                    message: _error!,
                  ),
                  const SizedBox(height: Space.md),
                ],
                Text(
                  _loss
                      ? 'Produits cassés, perdus, volés ou périmés : ils sortent de votre stock.'
                      : 'Ce que vous rapportez au dépôt. Tout le stock restant est proposé : retirez ce que vous gardez.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (!_loss && v.depots.length > 1) ...[
                  const SizedBox(height: Space.md),
                  DropdownButtonFormField<String>(
                    initialValue: _depotId ?? v.depots.first.id,
                    decoration: const InputDecoration(labelText: 'Dépôt'),
                    items: [
                      for (final d in v.depots)
                        DropdownMenuItem(value: d.id, child: Text(d.name)),
                    ],
                    onChanged: (id) => setState(() => _depotId = id),
                  ),
                ],
                const SizedBox(height: Space.md),
                for (final s in stock) ...[
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          s.product.label,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Dans le camion : ${formatQuantity(s.quantity, s.product)}',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        UnitQuantityField(
                          product: s.product,
                          value: _quantities?[s.product.id],
                          onChanged: (q) => setState(() {
                            _quantities![s.product.id] = q ?? 0;
                            _error = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                ],
                TextField(
                  controller: _note,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _loss ? 'Motif' : 'Note (facultatif)',
                    hintText: _loss
                        ? 'Ex. : casier tombé du camion'
                        : 'Ex. : invendus du jour',
                  ),
                ),
              ],
            ),
      bottomNavigationBar: v == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.page),
                child: PillButton(
                  label: _loss ? 'Déclarer la casse' : 'Déclarer le retour',
                  icon: _loss
                      ? Icons.heart_broken_outlined
                      : Icons.warehouse_outlined,
                  loading: _saving,
                  onPressed: _saving ? null : () => _submit(v),
                ),
              ),
            ),
    );
  }
}
