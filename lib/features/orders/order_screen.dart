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
import 'orders.dart';

/// Pastille du statut d'une commande : icône et libellé.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusChip(label: status.label, icon: status.icon, tone: status.tone);
}

/// Détail d'une commande : lignes aux prix figés, total, historique ; l'agent qui l'a prise la
/// marque livrée ou payée, ou l'annule tant qu'elle n'est pas livrée (motif obligatoire).
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
    } on ApiException catch (e) {
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
    final next = d != null && d.order.agentId == me.id
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
                onTap: () => context.push('/outlets/${d.order.outletId}'),
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

/// Fiche d'un point de vente : prendre une commande, et les dernières commandes.
class OutletOrdersSection extends ConsumerWidget {
  const OutletOrdersSection({super.key, required this.outletId});

  final String outletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final orders = ref.watch(outletOrdersProvider(outletId)).value;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Commandes',
          trailing: orders != null && orders.total > orders.items.length
              ? Text('${orders.total} au total', style: text.bodySmall)
              : null,
        ),
        if (!me.isTeamLead) ...[
          PillButton(
            label: 'Prendre une commande',
            icon: Icons.add_shopping_cart_rounded,
            style: PillStyle.tonal,
            onPressed: () => context.push('/outlets/$outletId/order'),
          ),
          const SizedBox(height: Space.sm),
        ],
        if (orders != null && orders.items.isEmpty)
          Text(
            'Pas encore de commande.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else if (orders != null)
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, o) in orders.items.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      '${o.reference} · ${formatMoney(o.total, o.currency)}',
                    ),
                    subtitle: Text(
                      '${formatShortDate(o.takenAt)} · ${o.agentName}',
                    ),
                    trailing: OrderStatusChip(o.status),
                    onTap: () => context.push('/orders/${o.id}'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
