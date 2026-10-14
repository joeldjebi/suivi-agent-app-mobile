import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'outlet_models.dart';
import 'outlet_widgets.dart';
import 'outlets_controller.dart';

/// Fiche d'un point de vente : informations, statut (avec commentaire) et historique.
class OutletScreen extends ConsumerWidget {
  const OutletScreen({super.key, required this.id});

  final String id;

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
          onRefresh: () => ref.refresh(outletProvider(id).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.page,
              Space.sm,
              Space.page,
              Space.xxxl,
            ),
            children: [
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
      const SizedBox(height: Space.lg),
      PillButton(
        label: 'Changer le statut',
        icon: Icons.swap_horiz_rounded,
        onPressed: () => _changeStatus(context, ref, o),
      ),
      if (!o.located) ...[
        const SizedBox(height: Space.sm),
        PillButton(
          label: 'Je suis devant : enregistrer la position',
          icon: Icons.my_location_rounded,
          style: PillStyle.tonal,
          onPressed: () => _locate(context, ref, o),
        ),
      ],
      if (o.phone != null) ...[
        const SizedBox(height: Space.sm),
        PillButton(
          label: 'Appeler ${o.managerName ?? 'le gérant'}',
          icon: Icons.call_rounded,
          style: PillStyle.outline,
          onPressed: () => launchUrl(Uri.parse('tel:${o.phone}')),
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
      const SizedBox(height: Space.xl),
      Text('Historique', style: text.titleMedium),
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
