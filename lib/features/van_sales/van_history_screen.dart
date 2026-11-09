import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/database.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/product_readings_input.dart' show formatQuantity;
import '../orders/orders.dart';
import '../outlets/outlet_models.dart';
import '../outlets/outlets_controller.dart' show pendingOutletsProvider;
import 'transfers.dart';
import 'van_history.dart';
import 'van_sell_screen.dart' show vanClientsProvider;

/// Historique du camion : un onglet par type d'opération, une période commune à tous les
/// onglets, des filtres propres à chacun et les totaux de la période en tête.
class VanHistoryScreen extends StatefulWidget {
  const VanHistoryScreen({super.key, this.initialTab = VanHistoryTab.sales});

  final VanHistoryTab initialTab;

  @override
  State<VanHistoryScreen> createState() => _VanHistoryScreenState();
}

class _VanHistoryScreenState extends State<VanHistoryScreen> {
  HistoryPeriod _period = HistoryPeriod.week();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: VanHistoryTab.values.length,
      initialIndex: widget.initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Historique du camion'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in VanHistoryTab.values) Tab(text: t.label)],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in VanHistoryTab.values)
              _HistoryTab(
                tab: t,
                period: _period,
                onPeriod: (p) => setState(() => _period = p),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab({
    required this.tab,
    required this.period,
    required this.onPeriod,
  });

  final VanHistoryTab tab;
  final HistoryPeriod period;
  final ValueChanged<HistoryPeriod> onPeriod;

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab>
    with AutomaticKeepAliveClientMixin {
  HistoryFilters _filters = const HistoryFilters();
  int _limit = HistoryQuery.pageSize;

  /// Dernière page affichée : gardée pendant le chargement de la suite (pas de saut).
  HistoryPage? _last;
  HistoryQuery? _lastQuery;

  @override
  bool get wantKeepAlive => true;

  void _setFilters(HistoryFilters f) => setState(() {
    _filters = f;
    _limit = HistoryQuery.pageSize;
  });

  @override
  void didUpdateWidget(covariant _HistoryTab old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) _limit = HistoryQuery.pageSize;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = HistoryQuery(
      tab: widget.tab,
      period: widget.period,
      filters: _filters,
      limit: _limit,
    );
    final async = ref.watch(vanHistoryProvider(query));
    if (async.value != null) {
      _last = async.value;
      _lastQuery = query;
    }
    // Pendant « Voir plus », la page précédente (mêmes filtres) reste affichée.
    final sameFilters =
        _lastQuery != null &&
        _lastQuery!.period == query.period &&
        _lastQuery!.filters == query.filters;
    final page = async.value ?? (sameFilters ? _last : null);
    final queued = _queued(ref.watch(pendingOutletsProvider).value ?? const []);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(vanHistoryProvider);
        await ref
            .read(vanHistoryProvider(query).future)
            .catchError(
              (_) => const HistoryPage(total: 0, summary: HistorySummary()),
            );
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          Space.md,
          Space.page,
          Space.xxl,
        ),
        children: [
          _FilterBar(
            tab: widget.tab,
            period: widget.period,
            filters: _filters,
            onPeriod: widget.onPeriod,
            onFilters: _setFilters,
          ),
          const SizedBox(height: Space.md),
          if (queued.isNotEmpty) ...[
            _QueuedCard(rows: queued),
            const SizedBox(height: Space.md),
          ],
          if (page == null)
            switch (async) {
              AsyncError(:final error) => InfoBanner(
                icon: Icons.wifi_off_rounded,
                message: ApiException.from(error).message,
              ),
              _ => const Padding(
                padding: EdgeInsets.all(Space.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            }
          else ...[
            _SummaryCard(tab: widget.tab, summary: page.summary),
            const SizedBox(height: Space.lg),
            if (page.loaded == 0)
              _Empty(tab: widget.tab, filtered: _filters.isActive)
            else ...[
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _rows(context, page),
                ),
              ),
              if (page.loaded < page.total) ...[
                const SizedBox(height: Space.md),
                Center(
                  child: async.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(Space.sm),
                          child: CircularProgressIndicator(),
                        )
                      : TextButton(
                          onPressed: () => setState(
                            () => _limit = (_limit + HistoryQuery.pageSize)
                                .clamp(0, 200),
                          ),
                          child: Text(
                            'Voir plus (${page.total - page.loaded} de plus)',
                          ),
                        ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  /// Opérations de cet onglet faites sans réseau, pas encore envoyées.
  List<PendingOutlet> _queued(List<PendingOutlet> all) {
    final kind = widget.tab.queueKind;
    if (kind == null) return const [];
    return all.where((r) => r.kind == kind && r.error == null).toList();
  }

  List<Widget> _rows(BuildContext context, HistoryPage page) {
    final tiles = <Widget>[
      for (final s in page.sales) _SaleTile(sale: s),
      for (final m in page.movements) _MovementTile(movement: m),
      for (final t in page.transfers)
        _TransferTile(transfer: t.transfer, given: t.given),
    ];
    return [
      for (final (i, t) in tiles.indexed) ...[
        if (i > 0) const Divider(height: 1, indent: Space.lg),
        t,
      ],
    ];
  }
}

// ---------------------------------------------------------------- filtres

class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.tab,
    required this.period,
    required this.filters,
    required this.onPeriod,
    required this.onFilters,
  });

  final VanHistoryTab tab;
  final HistoryPeriod period;
  final HistoryFilters filters;
  final ValueChanged<HistoryPeriod> onPeriod;
  final ValueChanged<HistoryFilters> onFilters;

  static const _pill = 40.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> choose<T>(
      String title,
      T selected,
      Map<T, String> options,
      void Function(T) apply,
    ) async {
      final picked = await pickOption<T>(
        context,
        title: title,
        selected: selected,
        options: options,
      );
      if (picked != null) apply(picked.value);
    }

    final pills = <Widget>[
      FilterPill(
        icon: Icons.calendar_today_rounded,
        label: period.label,
        active: period.kind != 'week',
        minHeight: _pill,
        onTap: () => _pickPeriod(context),
      ),
      FilterPill(
        icon: Icons.inventory_2_outlined,
        label: filters.productName ?? 'Tous les produits',
        active: filters.productId != null,
        minHeight: _pill,
        onTap: () async {
          final products = await ref
              .read(ownProductsProvider.future)
              .catchError((_) => <CatalogProduct>[]);
          if (!context.mounted) return;
          await choose<String?>(
            'Produit',
            filters.productId,
            {
              null: 'Tous les produits',
              for (final p in products) p.id: p.label,
            },
            (id) {
              final name = products.where((p) => p.id == id).firstOrNull?.label;
              onFilters(filters.copyWith(product: (id, name)));
            },
          );
        },
      ),
      if (tab == VanHistoryTab.sales) ...[
        FilterPill(
          icon: Icons.storefront_outlined,
          label: filters.outletName ?? 'Tous les clients',
          active: filters.outletId != null,
          minHeight: _pill,
          onTap: () async {
            final picked =
                await showModalBottomSheet<({String? id, String? name})>(
                  context: context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  builder: (_) => const _ClientPicker(),
                );
            if (picked != null) {
              onFilters(filters.copyWith(outlet: (picked.id, picked.name)));
            }
          },
        ),
        _option(
          context,
          icon: Icons.payments_outlined,
          title: 'Paiement',
          value: filters.payment,
          options: const {
            null: 'Tous les paiements',
            'paid': 'Payées',
            'credit': 'À crédit',
            'cancelled': 'Annulées',
          },
          apply: (v) => onFilters(filters.copyWith(payment: (v,))),
          choose: choose,
        ),
      ],
      if (tab == VanHistoryTab.loads)
        _option(
          context,
          icon: Icons.task_alt_rounded,
          title: 'Statut',
          value: filters.status,
          options: const {
            null: 'Tous les statuts',
            'pending': 'À confirmer',
            'done': 'Confirmés',
            'cancelled': 'Annulés',
          },
          apply: (v) => onFilters(filters.copyWith(status: (v,))),
          choose: choose,
        ),
      if (tab == VanHistoryTab.unloads)
        _option(
          context,
          icon: Icons.task_alt_rounded,
          title: 'Statut',
          value: filters.status,
          options: const {
            null: 'Tous les statuts',
            'pending': 'En attente',
            'done': 'Validés',
            'cancelled': 'Annulés',
          },
          apply: (v) => onFilters(filters.copyWith(status: (v,))),
          choose: choose,
        ),
      if (tab == VanHistoryTab.transfers) ...[
        _option(
          context,
          icon: Icons.swap_horiz_rounded,
          title: 'Sens',
          value: filters.direction,
          options: const {
            null: 'Reçus et donnés',
            'received': 'Reçus (mes demandes)',
            'given': 'Donnés (aux collègues)',
          },
          apply: (v) => onFilters(filters.copyWith(direction: (v,))),
          choose: choose,
        ),
        _option(
          context,
          icon: Icons.task_alt_rounded,
          title: 'État',
          value: filters.status,
          options: const {
            null: 'Tous les états',
            'open': 'En cours',
            'finished': 'Terminés',
          },
          apply: (v) => onFilters(filters.copyWith(status: (v,))),
          choose: choose,
        ),
      ],
      if (filters.isActive)
        TextButton(
          onPressed: () => onFilters(const HistoryFilters()),
          child: const Text('Effacer'),
        ),
    ];
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: pills,
    );
  }

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String? value,
    required Map<String?, String> options,
    required void Function(String?) apply,
    required Future<void> Function<T>(
      String title,
      T selected,
      Map<T, String> options,
      void Function(T) apply,
    )
    choose,
  }) => FilterPill(
    icon: icon,
    label: options[value]!,
    active: value != null,
    minHeight: _pill,
    onTap: () => choose<String?>(title, value, options, apply),
  );

  Future<void> _pickPeriod(BuildContext context) async {
    final picked = await pickOption<String>(
      context,
      title: 'Période',
      selected: period.kind,
      options: const {
        'today': 'Aujourd’hui',
        'week': '7 derniers jours',
        'month': '30 derniers jours',
        'custom': 'Choisir les dates…',
      },
    );
    if (picked == null || !context.mounted) return;
    switch (picked.value) {
      case 'today':
        onPeriod(HistoryPeriod.today());
      case 'week':
        onPeriod(HistoryPeriod.week());
      case 'month':
        onPeriod(HistoryPeriod.month());
      default:
        final now = DateTime.now();
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 2),
          lastDate: now,
          initialDateRange: DateTimeRange(start: period.from, end: period.to),
          helpText: 'Période',
          saveText: 'Valider',
        );
        if (range != null) {
          onPeriod(HistoryPeriod.custom(range.start, range.end));
        }
    }
  }
}

/// Choix d'un client : les plus proches, ou par nom.
class _ClientPicker extends ConsumerStatefulWidget {
  const _ClientPicker();

  @override
  ConsumerState<_ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends ConsumerState<_ClientPicker> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(vanClientsProvider(_q));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          0,
          Space.page,
          Space.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Client', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Space.md),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Nom du client',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 350),
                  () => setState(() => _q = v.trim()),
                );
              },
            ),
            const SizedBox(height: Space.md),
            GroupedList(
              indent: Space.lg,
              children: [
                ListRow(
                  title: 'Tous les clients',
                  chevron: false,
                  onTap: () => Navigator.pop(context, (id: null, name: null)),
                ),
                for (final o in clients.value ?? const <Outlet>[])
                  ListRow(
                    title: o.name,
                    subtitle: o.landmark,
                    chevron: false,
                    onTap: () =>
                        Navigator.pop(context, (id: o.id, name: o.name)),
                  ),
              ],
            ),
            if (clients.isLoading)
              const Padding(
                padding: EdgeInsets.all(Space.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- totaux

class _SummaryCard extends StatefulWidget {
  const _SummaryCard({required this.tab, required this.summary});

  final VanHistoryTab tab;
  final HistorySummary summary;

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  static const _shown = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = widget.summary;
    final muted = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final warning = toneColor(context, Tone.warning);

    final (
      String title,
      String headline,
      List<(String, Color?)> facts,
    ) = switch (widget.tab) {
      VanHistoryTab.sales => (
        'Vendu sur la période',
        formatMoney(s.amount, s.currency),
        [
          (_plural(s.count, 'vente', 'ventes'), null),
          ('Encaissé ${formatMoney(s.paid, s.currency)}', null),
          if (s.credit > 0)
            ('À crédit ${formatMoney(s.credit, s.currency)}', warning),
          if (s.cancelled > 0)
            (_plural(s.cancelled, 'annulée', 'annulées'), null),
        ],
      ),
      VanHistoryTab.loads => (
        'Reçu sur la période',
        _plural(s.count, 'chargement', 'chargements'),
        const [],
      ),
      VanHistoryTab.losses => (
        'Sorti du camion',
        _plural(s.count, 'déclaration', 'déclarations'),
        const [],
      ),
      VanHistoryTab.unloads => (
        'Rendu au dépôt',
        _plural(s.count, 'retour', 'retours'),
        const [],
      ),
      VanHistoryTab.transfers => (
        'Dépannages de la période',
        _plural(s.requested, 'demande', 'demandes'),
        [(_plural(s.helped, 'collègue aidé', 'collègues aidés'), null)],
      ),
    };

    final products = s.products;
    final visible = _all ? products : products.take(_shown).toList();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: muted),
          const SizedBox(height: Space.xs),
          Text(
            headline,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.md,
              runSpacing: Space.xs,
              children: [
                for (final (label, color) in facts)
                  Text(
                    label,
                    style: muted?.copyWith(
                      color: color,
                      fontWeight: color == null ? null : FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
          if (visible.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            const Divider(height: 1),
            for (final p in visible)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: _ProductTotal(tab: widget.tab, product: p),
              ),
            if (products.length > _shown)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _all = !_all),
                  child: Text(
                    _all
                        ? 'Moins de produits'
                        : 'Voir les ${products.length} produits',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Un produit des totaux : son nom, puis la quantité (reçue et donnée pour un dépannage).
class _ProductTotal extends StatelessWidget {
  const _ProductTotal({required this.tab, required this.product});

  final VanHistoryTab tab;
  final HistoryProduct product;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = product.product;
    final amount = tab == VanHistoryTab.transfers
        ? [
            if (product.received > 0)
              'Reçu ${formatQuantity(product.received, p)}',
            if (product.given > 0) 'Donné ${formatQuantity(product.given, p)}',
          ].join(' · ')
        : formatQuantity(product.quantity, p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.label,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          amount,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

String _plural(int n, String one, String many) =>
    '${formatNumber(n)} ${n > 1 ? many : one}';

// ---------------------------------------------------------------- lignes

/// Ligne d'historique : titre, montant ou statut à droite (dessous en grande police),
/// détails, et une pastille d'état.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.details,
    required this.onTap,
    this.trailing,
    this.tag,
    this.tagTone = Tone.neutral,
  });

  final String title;
  final String? trailing;
  final List<String> details;
  final String? tag;
  final Tone tagTone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final titleText = Text(
      title,
      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
    final trailingText = trailing == null
        ? null
        : Text(
            trailing!,
            style: text.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trailingText == null)
              titleText
            else if (largeText(context)) ...[
              titleText,
              trailingText,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleText),
                  const SizedBox(width: Space.md),
                  trailingText,
                ],
              ),
            for (final d in details)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  d,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (tag != null) ...[
              const SizedBox(height: Space.xs),
              _Tag(label: tag!, color: toneColor(context, tagTone)),
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
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
    ),
  );
}

/// « Lundi 9 novembre · 14:05 »
String _when(DateTime d) => '${formatDay(d)} · ${formatTime(d)}';

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale});

  final OrderItem sale;

  @override
  Widget build(BuildContext context) {
    final cancelled = sale.status == OrderStatus.cancelled;
    final (String tag, Tone tone) = cancelled
        ? ('Annulée', Tone.neutral)
        : sale.due > 0
        ? (
            'À crédit : reste ${formatMoney(sale.due, sale.currency)}',
            Tone.warning,
          )
        : ('Payée', Tone.success);
    return _Tile(
      title: sale.outletName,
      trailing: formatMoney(sale.total, sale.currency),
      details: [
        '${_when(sale.takenAt)} · ${sale.reference}',
        if (cancelled && sale.cancelReason != null)
          'Motif : ${sale.cancelReason}',
      ],
      tag: tag,
      tagTone: tone,
      onTap: () => context.push('/orders/${sale.id}'),
    );
  }
}

String _movementTitle(HistoryMovement m) => switch (m.kind) {
  'load' => 'Chargement depuis ${m.fromName ?? 'le dépôt'}',
  'unload' => 'Retour vers ${m.toName ?? 'le dépôt'}',
  _ => m.note?.isNotEmpty ?? false ? m.note! : 'Casse ou perte',
};

(String, Tone)? _movementStatus(HistoryMovement m) =>
    switch ((m.kind, m.status)) {
      ('load', 'pending') => ('À confirmer', Tone.warning),
      ('load', 'done') => (
        m.lines.any((l) => l.received != null && l.received != l.quantity)
            ? 'Reçu avec écart'
            : 'Reçu',
        Tone.success,
      ),
      ('unload', 'pending') => ('En attente du responsable', Tone.warning),
      ('unload', 'done') => ('Validé', Tone.success),
      (_, 'cancelled') => ('Annulé', Tone.neutral),
      _ => null,
    };

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final HistoryMovement movement;

  @override
  Widget build(BuildContext context) {
    final status = _movementStatus(movement);
    return _Tile(
      title: _movementTitle(movement),
      details: [_when(movement.at), movement.summary],
      tag: status?.$1,
      tagTone: status?.$2 ?? Tone.neutral,
      onTap: () => _showMovement(context, movement),
    );
  }
}

class _TransferTile extends ConsumerWidget {
  const _TransferTile({required this.transfer, required this.given});

  final Transfer transfer;
  final bool given;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transfer;
    if (given) {
      // Ma part chez ce collègue : ce que j'ai pris, et où elle en est.
      final me = ref.watch(meProvider).id;
      final leg = t.legs.where((l) => l.giverId == me).lastOrNull;
      return _Tile(
        title: 'Dépannage de ${t.requesterName}',
        details: [
          _when(t.createdAt),
          if (leg != null && leg.summary.isNotEmpty) 'Ma part : ${leg.summary}',
        ],
        tag: leg?.statusLabel ?? t.statusLabel,
        tagTone: switch (leg?.status) {
          'done' => Tone.success,
          'approval' || 'accepted' => Tone.warning,
          _ => Tone.neutral,
        },
        onTap: () => _showTransfer(context, t, given),
      );
    }
    final from = t.legs
        .where((l) => l.status == 'done')
        .map((l) => l.giverName)
        .toSet();
    return _Tile(
      title: 'Ma demande de dépannage',
      details: [
        _when(t.createdAt),
        t.lines.map((l) => '${formatQty(l.requested)} × ${l.name}').join(', '),
        if (from.isNotEmpty) 'Reçu de ${from.join(', ')}',
      ],
      tag: t.statusLabel,
      tagTone: switch (t.status) {
        'done' => Tone.success,
        'open' || 'covered' => Tone.warning,
        _ => Tone.neutral,
      },
      onTap: () => _showTransfer(context, t, given),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tab, required this.filtered});

  final VanHistoryTab tab;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final what = switch (tab) {
      VanHistoryTab.sales => 'Aucune vente',
      VanHistoryTab.loads => 'Aucun approvisionnement',
      VanHistoryTab.transfers => 'Aucun dépannage',
      VanHistoryTab.losses => 'Aucune casse ni perte',
      VanHistoryTab.unloads => 'Aucun retour au dépôt',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xl),
      child: Text(
        filtered
            ? '$what avec ces filtres sur la période.'
            : '$what sur la période.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Ventes, casses ou retours faits sans réseau : envoyés dès le retour du réseau.
class _QueuedCard extends StatelessWidget {
  const _QueuedCard({required this.rows});

  final List<PendingOutlet> rows;

  @override
  Widget build(BuildContext context) {
    final info = toneColor(context, Tone.info);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: Space.lg),
            Builder(
              builder: (context) {
                final body = jsonDecode(r.bodyJson) as Map<String, dynamic>;
                final total = body['total'] as num?;
                return _Tile(
                  title: r.name,
                  trailing: total == null ? null : formatMoney(total),
                  details: [_when(r.createdAt.toLocal())],
                  tag: 'En attente d’envoi',
                  tagTone: Tone.info,
                  onTap: () {},
                );
              },
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
            child: Row(
              children: [
                Icon(Icons.cloud_upload_outlined, size: 16, color: info),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    'Envoyé dès le retour du réseau, puis compté dans les totaux.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: info),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- détails

Future<void> _sheet(BuildContext context, String title, List<Widget> body) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          0,
          Space.page,
          Space.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Space.md),
            ...body,
          ],
        ),
      ),
    );

Future<void> _showMovement(BuildContext context, HistoryMovement m) {
  final status = _movementStatus(m);
  return _sheet(context, _movementTitle(m), [
    Text(_when(m.at)),
    if (status != null) ...[
      const SizedBox(height: Space.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: _Tag(label: status.$1, color: toneColor(context, status.$2)),
      ),
    ],
    const SizedBox(height: Space.md),
    GroupedList(
      indent: Space.lg,
      children: [
        for (final l in m.lines)
          ListRow(
            title: l.product.label,
            subtitle: l.received != null && l.received != l.quantity
                ? 'Annoncé ${formatQuantity(l.quantity, l.product)} · reçu ${formatQuantity(l.received!, l.product)}'
                : formatQuantity(HistoryMovement.counted(l), l.product),
          ),
      ],
    ),
    if (m.kind != 'loss' && (m.note?.isNotEmpty ?? false)) ...[
      const SizedBox(height: Space.md),
      Text('Note : ${m.note}'),
    ],
    if (m.confirmedByName != null && m.confirmedAt != null) ...[
      const SizedBox(height: Space.md),
      Text(
        m.kind == 'load'
            ? 'Confirmé le ${formatShortDate(m.confirmedAt!)} à ${formatTime(m.confirmedAt!)}'
            : 'Validé par ${m.confirmedByName} le ${formatShortDate(m.confirmedAt!)}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  ]);
}

Future<void> _showTransfer(
  BuildContext context,
  Transfer t,
  bool given,
) => _sheet(
  context,
  given ? 'Dépannage de ${t.requesterName}' : 'Ma demande de dépannage',
  [
    Text(_when(t.createdAt)),
    const SizedBox(height: Space.sm),
    Align(
      alignment: Alignment.centerLeft,
      child: _Tag(
        label: t.statusLabel,
        color: toneColor(context, t.isOpen ? Tone.warning : Tone.neutral),
      ),
    ),
    const SizedBox(height: Space.md),
    GroupedList(
      header: 'Demandé',
      indent: Space.lg,
      children: [
        for (final l in t.lines)
          ListRow(
            title: l.name,
            subtitle:
                'Demandé ${formatQty(l.requested)} · remis ${formatQty(l.given)}',
          ),
      ],
    ),
    if (t.legs.isNotEmpty) ...[
      const SizedBox(height: Space.md),
      GroupedList(
        header: 'Collègues',
        indent: Space.lg,
        children: [
          for (final l in t.legs)
            ListRow(
              title: l.giverName,
              subtitle: [
                l.statusLabel,
                if (l.summary.isNotEmpty) l.summary,
              ].join(' · '),
            ),
        ],
      ),
    ],
    if (t.note?.isNotEmpty ?? false) ...[
      const SizedBox(height: Space.md),
      Text('Note : ${t.note}'),
    ],
  ],
);
