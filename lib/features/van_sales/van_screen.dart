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
import 'transfers.dart' show refreshTransfers;
import 'van_sales.dart';

/// « Mon camion », pensé pour la tournée : en haut ce qui attend l'agent (chargement à
/// confirmer, retour, dépannages), puis « Vendre à un client », la journée (argent à remettre
/// en évidence), le stock (ventes faites sans réseau déjà déduites) et les autres déclarations
/// (dépannage, casse, retour au dépôt).
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
                  onRefresh: () async => refreshTransfers(ref),
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

  /// D'abord ce qui attend l'agent (chargement, retour, dépannages), puis vendre, la
  /// journée, le stock, et enfin les autres déclarations.
  List<Widget> _content(BuildContext context, MyVan v) {
    final loads = v.pending.where((m) => m.isLoad).toList();
    final unloads = v.pending.where((m) => !m.isLoad).toList();
    final hasStock = v.stock.any((s) => s.quantity > 0);
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
        _LoadCard(movement: m),
        const SizedBox(height: Space.md),
      ],
      for (final m in unloads) ...[
        InfoBanner(
          icon: Icons.hourglass_top_rounded,
          tone: Tone.info,
          message:
              'Retour vers ${m.toName ?? 'le dépôt'} déclaré à ${formatTime(m.at)} : en attente de confirmation par votre responsable.',
        ),
        const SizedBox(height: Space.md),
      ],
      // Demande d'un collègue proche, ma demande (mon code), ma part à remettre.
      const DayTransfersCard(),
      const SizedBox(height: Space.lg),
      PillButton(
        label: 'Vendre à un client',
        icon: Icons.point_of_sale_rounded,
        onPressed: hasStock ? () => context.push('/van/sell') : null,
      ),
      Center(
        child: TextButton.icon(
          onPressed: hasStock ? () => context.push('/van/out-of-zone') : null,
          icon: const Icon(Icons.wrong_location_outlined, size: 18),
          label: const Text('Vente hors zone'),
        ),
      ),
      const SizedBox(height: Space.sm),
      _DayCard(day: v.today),
      const SizedBox(height: Space.sm),
      // Tout ce qui s'est passé avant aujourd'hui : ventes, chargements, dépannages…
      SurfaceCard(
        padding: EdgeInsets.zero,
        child: ListRow(
          leading: IconSquircle(
            icon: Icons.history_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
            solid: true,
          ),
          title: 'Historique',
          subtitle: 'Ventes, approvisionnements, dépannages, casse, retours',
          onTap: () => context.push('/van/history'),
        ),
      ),
      const SizedBox(height: Space.lg),
      _StockSection(stock: v.stock),
      const SizedBox(height: Space.lg),
      const SectionHeader('Autres actions'),
      PillButton(
        label: 'Demander un dépannage',
        icon: Icons.handshake_outlined,
        style: PillStyle.tonal,
        onPressed: () => context.push('/van/transfer/new'),
      ),
      const SizedBox(height: Space.sm),
      Row(
        children: [
          Expanded(
            child: PillButton(
              label: 'Casse ou perte',
              icon: Icons.heart_broken_outlined,
              style: PillStyle.tonal,
              onPressed: hasStock ? () => context.push('/van/loss') : null,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: PillButton(
              label: 'Retour au dépôt',
              icon: Icons.warehouse_outlined,
              style: PillStyle.tonal,
              onPressed: !hasStock || v.depots.isEmpty
                  ? null
                  : () => context.push('/van/unload'),
            ),
          ),
        ],
      ),
    ];
  }
}

/// Chargement préparé au dépôt, à compter puis confirmer.
class _LoadCard extends StatelessWidget {
  const _LoadCard({required this.movement});

  final PendingMovement movement;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final m = movement;
    return SurfaceCard(
      border: BorderSide(color: toneColor(context, Tone.warning)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: toneColor(context, Tone.warning),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Chargement à confirmer',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
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
    );
  }
}

/// Journée : le total vendu en grand, la répartition des encaissements, et l'argent liquide
/// à remettre mis en évidence.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});

  final VanDay day;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final warning = toneColor(context, Tone.warning);
    Widget figure(String label, num value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Text(
            formatMoney(value),
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Text(
            formatMoney(day.salesAmount),
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Space.md),
          // Trois colonnes si la place le permet ; sinon (petit écran, police agrandie) une
          // ligne par montant, pour ne jamais couper un chiffre.
          LayoutBuilder(
            builder: (context, constraints) {
              final figures = [
                ('Espèces', day.cash),
                ('Mobile money', day.mobileMoney + day.bank),
                ('À crédit', day.dueOnSales),
              ];
              final scale = MediaQuery.textScalerOf(context).scale(1);
              if (constraints.maxWidth >= 290 * scale) {
                return Row(
                  children: [for (final (l, v) in figures) figure(l, v)],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (l, v) in figures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            formatMoney(v),
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          if (day.cashBalance > 0) ...[
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.payments_outlined, color: warning),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'À remettre : ${formatMoney(day.cashBalance)}',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: warning,
                          ),
                        ),
                        Text(
                          'Remettez l’argent liquide à votre responsable en fin de journée.',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stock du camion : recherche dès qu'il y a beaucoup de produits, ce qui reste de la
/// journée, « Bientôt vide », et les produits épuisés aujourd'hui repliés à la fin.
class _StockSection extends StatefulWidget {
  const _StockSection({required this.stock});

  final List<StockLine> stock;

  @override
  State<_StockSection> createState() => _StockSectionState();
}

class _StockSectionState extends State<_StockSection> {
  static const _searchFrom = 8;
  String _q = '';
  bool _showSoldOut = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final inVan = widget.stock.where((s) => s.quantity != 0).toList();
    final soldOut = widget.stock.where((s) => s.soldOut).toList();
    String plain(String s) => s.toLowerCase();
    bool match(StockLine s) =>
        _q.isEmpty || plain(s.product.label).contains(plain(_q));
    // Ce qui pose problème d'abord (vendu en trop, bientôt vide), puis par nom.
    int rank(StockLine s) => s.quantity < 0 ? 0 : (s.low ? 1 : 2);
    final shown = inVan.where(match).toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.product.label.compareTo(b.product.label);
      });
    final shownSoldOut = soldOut.where(match).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Dans le camion',
          trailing: Text(
            '${inVan.length} produit${inVan.length > 1 ? 's' : ''}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (inVan.isEmpty && soldOut.isEmpty)
          Text(
            'Le camion est vide. Votre responsable prépare votre chargement depuis le dépôt.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else ...[
          if (inVan.length + soldOut.length >= _searchFrom) ...[
            TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher un produit',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
            const SizedBox(height: Space.sm),
          ],
          if (inVan.isEmpty)
            Text(
              'Tout est vendu : bravo ! Votre responsable peut recharger le camion.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else if (shown.isEmpty)
            Text(
              'Aucun produit ne correspond.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, s) in shown.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: Space.lg),
                    _StockRow(line: s),
                  ],
                ],
              ),
            ),
          if (inVan.any((s) => s.quantity < 0)) ...[
            const SizedBox(height: Space.sm),
            Text(
              'En rouge : vendu plus que le stock connu. Votre responsable vérifiera.',
              style: text.bodySmall?.copyWith(
                color: toneColor(context, Tone.danger),
              ),
            ),
          ],
          if (shownSoldOut.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: () => setState(() => _showSoldOut = !_showSoldOut),
              icon: Icon(
                _showSoldOut
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text('Épuisés aujourd’hui (${shownSoldOut.length})'),
            ),
            if (_showSoldOut)
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, s) in shownSoldOut.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: Space.lg),
                      _StockRow(line: s),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ],
    );
  }
}

/// Un produit : nom, quantité (en conditionnements), part restante de la journée.
class _StockRow extends StatelessWidget {
  const _StockRow({required this.line});

  final StockLine line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = line;
    final danger = toneColor(context, Tone.danger);
    final warning = toneColor(context, Tone.warning);
    final color = s.quantity < 0
        ? danger
        : s.low
        ? warning
        : s.soldOut
        ? scheme.onSurfaceVariant
        : scheme.primary;
    final share = s.available > 0 ? (s.quantity / s.available).clamp(0, 1) : 0;
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  s.product.label,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: s.quantity < 0 ? danger : null,
                  ),
                ),
                if (s.low) _Tag(label: 'Bientôt vide', color: warning),
                if (s.soldOut)
                  _Tag(label: 'Épuisé', color: scheme.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              s.soldOut
                  ? 'Tout vendu aujourd’hui'
                  : formatQuantity(s.quantity, s.product),
              style: text.bodyMedium?.copyWith(
                color: s.quantity < 0 ? danger : scheme.onSurfaceVariant,
              ),
            ),
            // Part restante de ce qu'il y avait aujourd'hui (dès qu'une sortie a eu lieu).
            if (s.outToday > 0 && s.quantity > 0) ...[
              const SizedBox(height: Space.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: share.toDouble(),
                  minHeight: 6,
                  color: color,
                  backgroundColor: scheme.surfaceContainerHighest,
                  semanticsLabel: 'Reste de la journée',
                  semanticsValue:
                      'reste ${formatNumber(s.quantity)} sur ${formatNumber(s.available)}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
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
