import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/product_readings_input.dart' show formatQuantity;
import '../outlets/outlet_widgets.dart' show FicheSection, openOutlet;
import '../outlets/outlets_controller.dart' show outletProvider;
import 'order_editor_screen.dart';
import 'orders.dart';

/// Pastille du statut d'une commande : icône et libellé.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusChip(label: status.label, icon: status.icon, tone: status.tone);
}

/// « Commander à nouveau » : l'éditeur de commande pré-rempli avec les lignes de [id].
class ReorderScreen extends ConsumerWidget {
  const ReorderScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(orderProvider(id));
    // La saisie en cours survit à un rechargement de la commande d'origine.
    return switch (detail) {
      AsyncValue(:final value?) => OrderEditorScreen(
        key: ValueKey(id),
        outletId: value.order.outletId,
        copyOf: value,
      ),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(title: const Text('Commande')),
        body: Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: ApiException.from(error).message,
          ),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// Détail d'une commande : lignes aux prix figés, total, historique ; l'agent qui l'a prise la
/// marque livrée ou payée, ou l'annule tant qu'elle n'est pas livrée (motif obligatoire). Son
/// chef fait de même, et peut aussi annuler une commande livrée.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  OrderStatus? _busy;

  Future<void> _advance(OrderDetail d, OrderStatus next) async {
    String? reason;
    if (next == OrderStatus.cancelled) {
      reason = await _askReason();
      if (reason == null || !mounted) return;
    }
    tapFeedback();
    setState(() => _busy = next);
    try {
      await ref
          .read(repositoryProvider)
          .changeOrderStatus(d.order.id, next.code, reason);
      ref.invalidate(orderProvider(widget.id));
      ref.invalidate(outletOrdersProvider(d.order.outletId));
      if (mounted) {
        showMessage(context, 'Commande ${next.label.toLowerCase()}.');
      }
    } catch (error) {
      final e = ApiException.from(error);
      HapticFeedback.heavyImpact();
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<String?> _askReason() => showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ReasonSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(orderProvider(widget.id));
    final me = ref.watch(meProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final d = detail.value;
    // L'agent qui a pris la commande la fait avancer ; son chef aussi (le serveur ne lui montre
    // que les commandes de son équipe).
    final next = d == null
        ? const <OrderStatus>[]
        : !me.isAgent
        ? d.order.status.managerNext
        : d.order.agentId == me.id
        ? d.order.status.agentNext
        : const <OrderStatus>[];
    return Scaffold(
      appBar: AppBar(title: Text(d?.order.reference ?? 'Commande')),
      body: switch (detail) {
        AsyncError(:final error) when d == null => Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: ApiException.from(error).message,
          ),
        ),
        _ when d == null => const Center(child: CircularProgressIndicator()),
        _ => RefreshIndicator(
          onRefresh: () => ref.refresh(orderProvider(widget.id).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.page,
              Space.sm,
              Space.page,
              Space.xxxl,
            ),
            children: [
              Row(
                children: [
                  OrderStatusChip(d.order.status),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      '${formatShortDate(d.order.takenAt)} à ${formatTime(d.order.takenAt)}',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              InkWell(
                onTap: () => openOutlet(context, d.order.outletId),
                child: Text(d.order.outletName, style: text.titleLarge),
              ),
              Text(
                [
                  if (d.order.priceListName != null)
                    'Tarif ${d.order.priceListName}',
                  d.order.agentName,
                ].join(' · '),
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (d.order.cancelReason != null) ...[
                const SizedBox(height: Space.md),
                InfoBanner(
                  icon: Icons.block_rounded,
                  tone: Tone.danger,
                  message: 'Annulée : ${d.order.cancelReason}',
                ),
              ],
              const SizedBox(height: Space.lg),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, l) in d.lines.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        title: Text(l.name),
                        subtitle: Text(
                          '${formatQuantity(l.quantity, l.product)} × ${formatMoney(l.unitPrice, d.order.currency)}',
                        ),
                        trailing: Text(
                          formatMoney(l.amount, d.order.currency),
                          style: text.titleSmall,
                        ),
                      ),
                    ],
                    const Divider(height: 1),
                    ListTile(
                      title: Text('Total', style: text.titleMedium),
                      trailing: Text(
                        formatMoney(d.order.total, d.order.currency),
                        style: text.titleMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (d.order.note != null) ...[
                const SizedBox(height: Space.md),
                SurfaceCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.sticky_note_2_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(child: Text(d.order.note!)),
                    ],
                  ),
                ),
              ],
              for (final s in next) ...[
                const SizedBox(height: Space.sm),
                PillButton(
                  label: switch (s) {
                    OrderStatus.delivered => 'Marquer livrée',
                    OrderStatus.paid =>
                      d.order.status == OrderStatus.taken
                          ? 'Livrée et payée'
                          : 'Marquer payée',
                    _ => 'Annuler la commande',
                  },
                  icon: s.icon,
                  style: switch (s) {
                    OrderStatus.cancelled => PillStyle.outline,
                    OrderStatus.paid when d.order.status == OrderStatus.taken =>
                      PillStyle.tonal,
                    _ => PillStyle.primary,
                  },
                  loading: _busy == s,
                  onPressed: _busy == null ? () => _advance(d, s) : null,
                ),
              ],
              // Gain de temps : l'agent repart de cette commande, quel que soit son statut.
              if (me.isAgent) ...[
                const SizedBox(height: Space.sm),
                PillButton(
                  label: 'Commander à nouveau',
                  icon: Icons.replay_rounded,
                  style: PillStyle.outline,
                  onPressed: () => context.push('/orders/${d.order.id}/again'),
                ),
              ],
              const SizedBox(height: Space.xl),
              const SectionHeader('Historique'),
              for (final e in d.events)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        e.status.icon,
                        size: 18,
                        color: toneColor(context, e.status.tone),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.status.label, style: text.bodyMedium),
                            if (e.comment != null) Text('« ${e.comment} »'),
                            Text(
                              [
                                '${formatShortDate(e.at)} à ${formatTime(e.at)}',
                                ?e.user,
                              ].join(' · '),
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
          ),
        ),
      },
    );
  }
}

/// Motif de l'annulation (obligatoire).
class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet();

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      Space.page,
      0,
      Space.page,
      Space.xxl + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Annuler la commande',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _reason,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Motif',
            hintText: 'Ex. : le client a changé d’avis',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Space.lg),
        PillButton(
          label: 'Annuler la commande',
          icon: Icons.block_rounded,
          style: PillStyle.danger,
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
        ),
      ],
    ),
  );
}

/// Ligne d'une commande : référence, montant, date, agent, statut ; s'ouvre au toucher.
class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order});

  final OrderItem order;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(
      '${order.reference} · ${formatMoney(order.total, order.currency)}',
    ),
    subtitle: Text('${formatShortDate(order.takenAt)} · ${order.agentName}'),
    trailing: OrderStatusChip(order.status),
    onTap: () => context.push('/orders/${order.id}'),
  );
}

/// Fiche d'un point de vente : les 5 dernières commandes (« Commander » est en tête de fiche),
/// et « Voir tout » vers toutes ses commandes.
class OutletOrdersSection extends ConsumerWidget {
  const OutletOrdersSection({super.key, required this.outletId});

  final String outletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final orders = ref.watch(outletOrdersProvider(outletId)).value;
    final items = orders?.items ?? const <OrderItem>[];
    final open = items.where((o) => o.status == OrderStatus.taken).length;
    return FicheSection(
      title: 'Commandes',
      summary: orders == null || orders.total == 0
          ? null
          : [
              '${orders.total} commande${orders.total > 1 ? 's' : ''}',
              if (open > 0) '$open à livrer',
              'dernière le ${formatShortDate(items.first.takenAt)}',
            ].join(' · '),
      empty: orders == null
          ? 'Chargement…'
          : me.isTeamLead
          ? 'Pas encore de commande.'
          : 'Pas encore de commande : touchez « Commander » en haut de la fiche.',
      rows: [
        for (final o in items.take(FicheSection.shown)) OrderTile(order: o),
      ],
      seeAllLabel: 'Voir les ${orders?.total ?? 0} commandes',
      onSeeAll: (orders?.total ?? 0) > FicheSection.shown
          ? () => context.push('/outlets/$outletId/orders')
          : null,
    );
  }
}

/// Toutes les commandes d'un point de vente (100 dernières), les plus récentes d'abord.
final allOutletOrdersProvider = FutureProvider.autoDispose
    .family<List<OrderItem>, String>((ref, outletId) async {
      final json = await ref
          .read(repositoryProvider)
          .orders(outletId: outletId, limit: 100);
      return [
        for (final o in json['items'] as List)
          OrderItem.fromJson(o as Map<String, dynamic>),
      ];
    });

class OutletOrdersScreen extends ConsumerWidget {
  const OutletOrdersScreen({super.key, required this.outletId});

  final String outletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(allOutletOrdersProvider(outletId));
    final list = orders.value;
    final name = ref.watch(outletProvider(outletId)).value?.outlet.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(name == null ? 'Commandes' : 'Commandes · $name'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(allOutletOrdersProvider(outletId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.xxxl,
          ),
          children: [
            if (orders.hasError && list == null)
              InfoBanner(
                icon: Icons.wifi_off_rounded,
                message: ApiException.from(orders.error!).message,
              )
            else if (list == null)
              const Padding(
                padding: EdgeInsets.all(Space.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, o) in list.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      OrderTile(order: o),
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
