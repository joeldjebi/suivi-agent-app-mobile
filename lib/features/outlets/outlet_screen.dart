import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/phone_format.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';
import '../../design/components.dart';
import '../../design/lucide.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../orders/order_screen.dart' show OutletOrdersSection;
import '../orders/orders.dart' show outletOrdersProvider;
import 'outlet_activity.dart';
import 'outlet_models.dart';
import 'outlet_widgets.dart';
import 'outlets_controller.dart';
import 'visit_forms.dart';

/// Le point de vente dans Google Maps (application si installée, sinon le site).
Uri googleMapsPlace(LatLng p) => Uri.https('www.google.com', '/maps/search/', {
  'api': '1',
  'query': '${p.latitude},${p.longitude}',
});

/// Fiche d'un point de vente : informations, statut (avec commentaire) et historique.
class OutletScreen extends ConsumerWidget {
  const OutletScreen({super.key, required this.id, this.justAdded = false});

  final String id;

  /// Vient d'être ajouté : proposer la première visite.
  final bool justAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(outletProvider(id));
    final form = ref.watch(outletFormProvider).value;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail.value?.outlet.name ?? 'Point de vente'),
        actions: [
          if (detail.value != null)
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(
                '/outlets/$id/edit',
                extra: detail.value!.outlet,
              ),
            ),
        ],
      ),
      body: switch (detail) {
        AsyncError(:final error) when detail.value == null => Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: ApiException.from(error).message,
          ),
        ),
        _ when detail.value == null => const Center(
          child: CircularProgressIndicator(),
        ),
        _ => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(outletReadingsProvider(id));
            ref.invalidate(outletOrdersProvider(id));
            return ref.refresh(outletProvider(id).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.page,
              Space.sm,
              Space.page,
              Space.xxxl,
            ),
            children: [
              if (justAdded) AskFirstVisit(outletId: id),
              ..._content(context, ref, detail.value!, form, text, scheme),
            ],
          ),
        ),
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    OutletDetail detail,
    OutletForm? form,
    TextTheme text,
    ColorScheme scheme,
  ) {
    final o = detail.outlet;
    final fields = form?.fields ?? const <MissionField>[];
    final me = ref.watch(meProvider);
    final canOrder = me.hasOrders && !me.isTeamLead;
    return [
      if (o.photoId != null) ...[
        RemotePhoto(id: o.photoId!, label: 'Devanture de ${o.name}'),
        const SizedBox(height: Space.md),
      ],
      Row(
        children: [
          OutletAvatar(category: o.category, status: o.status, size: 48),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.name, style: text.titleLarge),
                Text(
                  [
                    ?o.category,
                    o.zoneName == null
                        ? (o.located ? 'Hors zone' : 'À localiser')
                        : 'Zone ${o.zoneName}',
                  ].join(' · '),
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.md),
      Row(
        children: [
          OutletStatusPill(o.status),
          const SizedBox(width: Space.sm),
          Flexible(
            child: Text(
              'depuis le ${formatShortDate(o.statusChangedAt.toLocal())}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      if (o.frequencyDays > 0 || o.lastVisitAt != null) ...[
        const SizedBox(height: Space.md),
        _VisitCard(outlet: o),
      ],
      const SizedBox(height: Space.lg),
      // Ce que l'agent vient faire : visiter, commander.
      if (canVisitFreely(ref) || canOrder) ...[
        Row(
          children: [
            if (canVisitFreely(ref))
              Expanded(
                child: PillButton(
                  label: 'Visiter',
                  icon: Icons.login_rounded,
                  onPressed: () => startVisit(context, ref, o.id),
                ),
              ),
            if (canVisitFreely(ref) && canOrder)
              const SizedBox(width: Space.sm),
            if (canOrder)
              Expanded(
                child: PillButton(
                  label: 'Commander',
                  icon: Icons.add_shopping_cart_rounded,
                  style: canVisitFreely(ref)
                      ? PillStyle.tonal
                      : PillStyle.primary,
                  onPressed: () => context.push('/outlets/${o.id}/order'),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.md),
      ],
      // Raccourcis, comme sur une fiche contact.
      SurfaceCard(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            _QuickAction(
              icon: Icons.swap_horiz_rounded,
              label: 'Statut',
              onTap: () => _changeStatus(context, ref, o),
            ),
            if (o.phone != null)
              _QuickAction(
                icon: Icons.call_rounded,
                label: 'Appeler',
                onTap: () => launchUrl(Uri.parse('tel:${o.phone}')),
              ),
            if (o.position != null)
              _QuickAction(
                icon: Icons.directions_rounded,
                label: 'Itinéraire',
                onTap: () => launchUrl(
                  googleMapsPlace(o.position!),
                  mode: LaunchMode.externalApplication,
                ),
              )
            else
              _QuickAction(
                icon: Icons.my_location_rounded,
                label: 'Localiser',
                onTap: () => _locate(context, ref, o),
              ),
          ],
        ),
      ),
      if (!o.located) ...[
        const SizedBox(height: Space.sm),
        Text(
          'À localiser : devant le commerce, touchez « Localiser » pour enregistrer sa position.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
      const SizedBox(height: Space.lg),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Info('Gérant', o.managerName),
            _Info('Téléphone', o.phone == null ? null : displayPhone(o.phone!)),
            _Info('Repère', o.landmark),
            for (final f in fields.where((f) => f.type != FieldType.photo))
              _Info(f.label, _value(f, o.data[f.key])),
            _Info('Ajouté par', o.createdBy),
          ],
        ),
      ),
      for (final f in fields.where(
        (f) => f.type == FieldType.photo && o.data[f.key] is String,
      )) ...[
        const SizedBox(height: Space.md),
        Text(f.label, style: text.titleSmall),
        const SizedBox(height: Space.xs),
        RemotePhoto(id: o.data[f.key] as String, label: f.label),
      ],
      if (ref.watch(meProvider).hasOrders) ...[
        const SizedBox(height: Space.lg),
        OutletOrdersSection(outletId: o.id),
      ],
      if (ref.watch(meProvider).hasProductAudits) ...[
        const SizedBox(height: Space.lg),
        OutletProductsSection(outletId: o.id),
      ],
      const SizedBox(height: Space.lg),
      OutletVisitsSection(visits: detail.visits),
      const SizedBox(height: Space.xl),
      Text('Historique du statut', style: text.titleMedium),
      const SizedBox(height: Space.sm),
      for (final h in detail.history)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LucideIcon(h.to.icon, size: 18, color: h.to.color),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.from == null
                          ? 'Ajouté · ${h.to.label}'
                          : h.from == h.to
                          ? 'Note'
                          : '${h.from!.label} → ${h.to.label}',
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (h.comment != null) Text('« ${h.comment} »'),
                    Text(
                      [
                        '${formatShortDate(h.at)} à ${formatTime(h.at)}',
                        ?h.user,
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
    ];
  }

  static String? _value(MissionField f, Object? v) {
    if (v == null || v == '') return null;
    if (f.type == FieldType.boolean) return v == true ? 'Oui' : 'Non';
    if (f.type == FieldType.date && v is String) {
      return formatShortDate(DateTime.parse(v));
    }
    if (v is num) return formatNumber(v);
    return '$v';
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    Outlet o,
  ) async {
    final result = await showModalBottomSheet<(OutletStatus, String)>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StatusSheet(current: o.status),
    );
    if (result == null || !context.mounted) return;
    final (status, comment) = result;
    await _run(
      context,
      () => sendOutletAction(
        ref,
        kind: 'status',
        outletId: o.id,
        name: o.name,
        body: {
          'status': status.code,
          if (comment.isNotEmpty) 'comment': comment,
        },
      ),
      done: status == o.status
          ? 'Commentaire ajouté.'
          : 'Statut : ${status.label}.',
    );
  }

  Future<void> _locate(BuildContext context, WidgetRef ref, Outlet o) async {
    final p = await ref.read(trackerProvider).freshPosition();
    if (!context.mounted) return;
    if (p == null) {
      return showMessage(
        context,
        'Position introuvable : activez la localisation.',
        error: true,
      );
    }
    await _run(
      context,
      () => sendOutletAction(
        ref,
        kind: 'update',
        outletId: o.id,
        name: o.name,
        body: {'lat': p.latitude, 'lng': p.longitude, 'accuracy': p.accuracy},
      ),
      done: 'Position enregistrée.',
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<OutletSaved> Function() action, {
    required String done,
  }) async {
    tapFeedback();
    try {
      final saved = await action();
      if (!context.mounted) return;
      showMessage(
        context,
        saved.outcome == SubmitOutcome.queued
            ? 'Enregistré sur le téléphone : envoyé au retour du réseau.'
            : done,
      );
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '—',
              style: text.bodyMedium?.copyWith(
                color: value == null ? scheme.onSurfaceVariant : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Choix du nouveau statut et commentaire facultatif.
class _StatusSheet extends StatefulWidget {
  const _StatusSheet({required this.current});

  final OutletStatus current;

  @override
  State<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<_StatusSheet> {
  late OutletStatus _status = widget.current;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final changed =
        _status != widget.current || _comment.text.trim().isNotEmpty;
    return Padding(
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
          Text('Changer le statut', style: text.titleLarge),
          const SizedBox(height: Space.md),
          for (final s in OutletStatus.values)
            ListTile(
              selected: _status == s,
              onTap: () => setState(() => _status = s),
              contentPadding: EdgeInsets.zero,
              trailing: _status == s
                  ? Icon(Icons.check_circle_rounded, color: s.color)
                  : const Icon(Icons.circle_outlined),
              title: Row(
                children: [
                  LucideIcon(s.icon, color: s.color, size: 20),
                  const SizedBox(width: Space.sm),
                  Text(s.label),
                  if (s == widget.current)
                    Text('  (actuel)', style: text.bodySmall),
                ],
              ),
            ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _comment,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Commentaire (facultatif)',
              hintText: 'Ex. : première commande passée',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.lg),
          PillButton(
            label: 'Enregistrer',
            icon: Icons.check_rounded,
            onPressed: changed
                ? () => Navigator.pop(context, (_status, _comment.text.trim()))
                : null,
          ),
        ],
      ),
    );
  }
}

/// Suivi des visites : dernière visite, prochaine visite due ou retard. Le chef règle la
/// fréquence propre au point de vente.
class _VisitCard extends ConsumerWidget {
  const _VisitCard({required this.outlet});

  final Outlet outlet;

  Future<void> _frequency(BuildContext context, WidgetRef ref) async {
    final picked = await pickOption<int>(
      context,
      title: 'Visiter ce point de vente',
      selected: outlet.visitFrequencyDays ?? 0,
      options: {
        0: 'Fréquence par défaut de la structure',
        for (final d in [7, 14, 30, 60, 90]) d: 'Tous les $d jours',
      },
    );
    if (picked == null || !context.mounted) return;
    try {
      await sendOutletAction(
        ref,
        kind: 'update',
        outletId: outlet.id,
        name: outlet.name,
        body: {'visitFrequencyDays': picked.value == 0 ? null : picked.value},
      );
      if (context.mounted) {
        showMessage(context, 'Fréquence de visite enregistrée.');
      }
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final o = outlet;
    final late = o.overdue && o.dueAt != null
        ? DateTime.now().difference(o.dueAt!).inDays.clamp(1, 9999)
        : 0;
    final leader = ref.watch(meProvider).isTeamLead;
    return SurfaceCard(
      child: Row(
        children: [
          Icon(
            o.overdue ? Icons.schedule_rounded : Icons.event_available_rounded,
            color: o.overdue ? OutletPin.overdueColor : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.visitLabel, style: text.bodyLarge),
                if (o.frequencyDays > 0)
                  Text(
                    o.overdue
                        ? 'En retard de $late jour${late > 1 ? 's' : ''} (tous les ${o.frequencyDays} j)'
                        : 'Prochaine visite avant le ${formatShortDate(o.dueAt!)} (tous les ${o.frequencyDays} j)',
                    style: text.bodySmall?.copyWith(
                      color: o.overdue
                          ? OutletPin.overdueColor
                          : scheme.onSurfaceVariant,
                      fontWeight: o.overdue ? FontWeight.w600 : null,
                    ),
                  ),
              ],
            ),
          ),
          if (leader)
            IconButton(
              tooltip: 'Fréquence de visite',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => _frequency(context, ref),
            ),
        ],
      ),
    );
  }
}

/// Raccourci de la fiche : icône dans un rond, libellé dessous.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primary.withValues(alpha: 0.1),
                  child: Icon(icon, color: scheme.primary),
                ),
                const SizedBox(height: 6),
                Text(label, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
