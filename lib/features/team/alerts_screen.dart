import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import 'team_controller.dart';

/// Libellé et icône de chaque type d'alerte.
const alertMeta = <String, (String, IconData)>{
  'signal_lost': ('Signal perdu', Icons.wifi_off_rounded),
  'immobile': ('Immobile', Icons.do_not_step_rounded),
  'low_battery': ('Batterie faible', Icons.battery_alert_rounded),
  'mocked': ('Position simulée', Icons.gpp_maybe_outlined),
  'out_of_zone': ('Hors zone', Icons.wrong_location_rounded),
  'late_start': ('Journée pas démarrée', Icons.wb_twilight_rounded),
  'sos': ('Alerte sécurité', Icons.sos_rounded),
};

String alertLabelOf(String type) => alertMeta[type]?.$1 ?? 'Alerte';

/// Libellé court d'une pastille : « Batterie 12 % », « Hors zone · 2,6 km ».
String _chipLabel(AgentAlert a) => switch (a.type) {
  'low_battery' => 'Batterie ${a.data['percent']} %',
  'out_of_zone' =>
    'Hors zone · ${formatMeters((a.data['maxDistanceM'] as num? ?? 0).toDouble())}',
  'sos' => 'Alerte sécurité',
  'late_start' => 'Pas démarrée',
  _ => alertLabelOf(a.type),
};

/// Alertes d'un même agent, la plus ancienne d'abord.
class _AgentAlerts {
  _AgentAlerts(this.alerts);

  final List<AgentAlert> alerts;

  AgentAlert get first => alerts.first;
  String get agentId => first.agentId;
  String get name => first.agentName;
  String get initials => name
      .split(' ')
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase())
      .join();
  DateTime get since =>
      alerts.map((a) => a.startedAt).reduce((a, b) => a.isBefore(b) ? a : b);
  AgentAlert? get acknowledged =>
      alerts.where((a) => a.acknowledgedAt != null).firstOrNull;
  List<AgentAlert> get toAcknowledge =>
      alerts.where((a) => a.isOpen && a.acknowledgedAt == null).toList();
  String? get dayId => alerts.map((a) => a.dayId).nonNulls.firstOrNull;
}

List<_AgentAlerts> _byAgent(List<AgentAlert> alerts) {
  final groups = <String, List<AgentAlert>>{};
  for (final a in alerts) {
    (groups[a.agentId] ??= []).add(a);
  }
  final list = [
    for (final g in groups.values)
      _AgentAlerts(g..sort((a, b) => a.startedAt.compareTo(b.startedAt))),
  ];
  // Alertes sécurité d'abord, puis à prendre en charge, puis les plus anciennes.
  list.sort((a, b) {
    final sos = (b.alerts.any((x) => x.isSos && x.isOpen) ? 1 : 0).compareTo(
      a.alerts.any((x) => x.isSos && x.isOpen) ? 1 : 0,
    );
    if (sos != 0) return sos;
    final todo = (b.toAcknowledge.isNotEmpty ? 1 : 0).compareTo(
      a.toAcknowledge.isNotEmpty ? 1 : 0,
    );
    return todo != 0 ? todo : a.since.compareTo(b.since);
  });
  return list;
}

/// « 12 min », « 1 h 05 ».
String _duration(DateTime from, [DateTime? to]) {
  final minutes = (to ?? DateTime.now())
      .difference(from)
      .inMinutes
      .clamp(1, 1 << 20);
  return minutes < 60
      ? '$minutes min'
      : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

/// Détail lisible, selon le type.
String alertDetail(AgentAlert a) {
  final d = a.data;
  return switch (a.type) {
    'signal_lost' =>
      d['lastPositionAt'] == null
          ? 'Aucune position reçue'
          : 'Dernière position à ${formatTime(DateTime.parse(d['lastPositionAt'] as String).toLocal())}',
    'immobile' =>
      'Dans un rayon de ${d['radiusM']} m depuis ${formatTime(DateTime.parse(d['since'] as String).toLocal())}',
    'low_battery' => 'Batterie à ${d['percent']} %',
    'mocked' => 'Application de fausse position GPS',
    'out_of_zone' =>
      'Hors de ${d['zoneName'] ?? 'sa zone'}, jusqu’à ${formatMeters((d['maxDistanceM'] as num? ?? 0).toDouble())}',
    'late_start' => 'Début attendu à ${d['expectedAt']}',
    'sos' => [
      if (d['message'] is String && (d['message'] as String).isNotEmpty)
        '« ${d['message']} »'
      else
        'Demande d’aide',
      if (a.position == null) 'position indisponible',
      if (d['cancelled'] == true) 'annulée par l’agent',
      if (d['closingNote'] is String) 'close : « ${d['closingNote']} »',
    ].join(' · '),
    _ => '',
  };
}

/// Alertes en cours, relues régulièrement (elles se ferment d'elles-mêmes).
class OpenAlertsController extends AsyncNotifier<List<AgentAlert>> {
  Timer? _timer;

  @override
  Future<List<AgentAlert>> build() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
    ref.onDispose(() => _timer?.cancel());
    return ref.read(repositoryProvider).alerts();
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(
      () => ref.read(repositoryProvider).alerts(),
    );
    if (next.hasValue || !state.hasValue) state = next;
  }

  /// « Je m'en occupe » sur toutes les alertes en cours d'un agent, avec la même note.
  Future<void> acknowledge(Iterable<String> ids, String? note) async {
    for (final id in ids) {
      await ref.read(repositoryProvider).acknowledgeAlert(id, note: note);
    }
    await refresh();
  }
}

final openAlertsProvider =
    AsyncNotifierProvider<OpenAlertsController, List<AgentAlert>>(
      OpenAlertsController.new,
    );

final resolvedAlertsProvider = FutureProvider.autoDispose<List<AgentAlert>>(
  (ref) => ref.read(repositoryProvider).alerts(status: 'resolved'),
);

/// Centre d'alertes du chef : une carte par agent, ses alertes en pastilles.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  var _open = true;

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(openAlertsProvider);
    final query = _open ? open : ref.watch(resolvedAlertsProvider);
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Alertes')),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_open) {
            await ref.read(openAlertsProvider.notifier).refresh();
          } else {
            ref.invalidate(resolvedAlertsProvider);
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            0,
            Space.page,
            Space.xxxl,
          ),
          children: [
            AppSegmented<bool>(
              selected: _open,
              segments: {
                true:
                    'En cours${open.value == null ? '' : ' (${open.value!.length})'}',
                false: 'Refermées',
              },
              onChanged: (v) => setState(() => _open = v),
            ),
            ...query.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.only(top: Space.xxxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => [
                const SizedBox(height: Space.md),
                InfoBanner(
                  icon: Icons.wifi_off_rounded,
                  message: ApiException.from(e).message,
                ),
              ],
              data: (items) {
                if (items.isEmpty) return [_Empty(open: _open)];
                final groups = _byAgent(items);
                final taken = groups
                    .where((g) => g.acknowledged != null)
                    .length;
                return [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xs,
                      Space.lg,
                      Space.xs,
                      Space.sm,
                    ),
                    child: Text(
                      _open
                          ? '${groups.length} agent${groups.length > 1 ? 's' : ''} à surveiller'
                                '${taken > 0 ? ' · $taken pris en charge' : ''}'
                          : 'Les 7 derniers jours',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                  for (final g in groups) _AgentCard(group: g, open: _open),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxxl * 2),
      child: Column(
        children: [
          Icon(
            open ? Icons.verified_outlined : Icons.history_rounded,
            size: 44,
            color: open
                ? toneColor(context, Tone.success)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: Space.md),
          Text(
            open ? 'Aucune alerte en cours' : 'Aucune alerte refermée',
            style: text.titleMedium,
          ),
          const SizedBox(height: Space.xs),
          Text(
            open
                ? 'Tout va bien sur le terrain.'
                : 'Rien sur les 7 derniers jours.',
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille d'une alerte : icône et libellé court.
class _AlertChip extends StatelessWidget {
  const _AlertChip({required this.alert, required this.active});

  final AgentAlert alert;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? toneColor(context, Tone.danger)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            alertMeta[alert.type]?.$2 ?? Icons.warning_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            _chipLabel(alert),
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Une carte par agent : avatar, depuis quand, pastilles, prise en charge.
class _AgentCard extends ConsumerWidget {
  const _AgentCard({required this.group, required this.open});

  final _AgentAlerts group;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = group;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ack = g.acknowledged;
    final pending = open && g.toAcknowledge.isNotEmpty;
    final subtitle = open
        ? 'Depuis ${_duration(g.since)}'
        : '${formatShortDate(g.since)} à ${formatTime(g.since)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: SurfaceCard(
        onTap: () => _showAgentAlerts(context, g, open: open),
        semanticLabel:
            '${g.name} : ${g.alerts.map(_chipLabel).join(', ')}. Ouvrir le détail',
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.sm,
          Space.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusAvatar(
                  initials: g.initials,
                  ringColor: pending
                      ? toneColor(context, Tone.danger)
                      : open
                      ? toneColor(context, Tone.warning)
                      : scheme.outline,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name, style: text.titleSmall),
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in g.alerts)
                  _AlertChip(alert: a, active: a.isOpen),
              ],
            ),
            if (ack != null) ...[
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Icon(
                    Icons.pan_tool_alt_outlined,
                    size: 15,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      '${ack.acknowledgedBy} s’en occupe · ${formatTime(ack.acknowledgedAt!)}',
                      style: text.bodySmall?.copyWith(color: scheme.primary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _showAgentAlerts(
  BuildContext context,
  _AgentAlerts group, {
  required bool open,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  builder: (_) => _AgentAlertsSheet(group: group, open: open),
);

/// Détail des alertes d'un agent et actions : je m'en occupe, carte, appel.
class _AgentAlertsSheet extends ConsumerStatefulWidget {
  const _AgentAlertsSheet({required this.group, required this.open});

  final _AgentAlerts group;
  final bool open;

  @override
  ConsumerState<_AgentAlertsSheet> createState() => _AgentAlertsSheetState();
}

class _AgentAlertsSheetState extends ConsumerState<_AgentAlertsSheet> {
  final _note = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _acknowledge() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(openAlertsProvider.notifier)
          .acknowledge(widget.group.toAcknowledge.map((a) => a.id), _note.text);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'Alertes prises en charge');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, e.message, error: true);
      }
    }
  }

  Future<void> _close(AgentAlert alert) async {
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).closeAlert(alert.id, note: _note.text);
      await ref.read(openAlertsProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'Alerte close : l’agent est informé');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final phone =
        ref.watch(teamProvider).value?.members[g.agentId]?.phone ??
        g.first.agentPhone;
    final sos = g.alerts.where((a) => a.isSos && a.isOpen).firstOrNull;
    final todo = widget.open && g.toAcknowledge.isNotEmpty;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.page,
        0,
        Space.page,
        Space.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusAvatar(
                initials: g.initials,
                ringColor: todo
                    ? toneColor(context, Tone.danger)
                    : scheme.outline,
                size: 44,
              ),
              const SizedBox(width: Space.md),
              Expanded(child: Text(g.name, style: text.headlineSmall)),
            ],
          ),
          GroupedList(
            header: widget.open ? 'En cours' : 'Refermées',
            indent: Space.lg,
            children: [
              for (final a in g.alerts)
                ListRow(
                  leading: IconSquircle(
                    icon: alertMeta[a.type]?.$2 ?? Icons.warning_rounded,
                    color: a.isOpen
                        ? toneColor(context, Tone.danger)
                        : scheme.onSurfaceVariant,
                    size: 28,
                    solid: true,
                  ),
                  title: alertLabelOf(a.type),
                  subtitle: alertDetail(a),
                  value: a.isOpen
                      ? _duration(a.startedAt)
                      : _duration(a.startedAt, a.resolvedAt),
                ),
            ],
          ),
          if (g.acknowledged case final ack?)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: InfoBanner(
                icon: Icons.pan_tool_alt_outlined,
                tone: Tone.info,
                message:
                    '${ack.acknowledgedBy} s’en occupe depuis ${formatTime(ack.acknowledgedAt!)}'
                    '${ack.note == null ? '' : ' : « ${ack.note} »'}',
              ),
            ),
          if (todo) ...[
            const SizedBox(height: Space.lg),
            TextField(
              controller: _note,
              maxLength: 300,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Ce que vous avez fait (facultatif)',
                hintText: 'Ex. Appelé : en rendez-vous client',
              ),
            ),
            const SizedBox(height: Space.sm),
            PillButton(
              label: 'Je m’en occupe',
              icon: Icons.pan_tool_alt_outlined,
              loading: _saving,
              onPressed: _saving ? null : _acknowledge,
            ),
          ],
          if (widget.open && sos != null) ...[
            const SizedBox(height: Space.sm),
            if (sos.position case final p?)
              PillButton(
                label: 'Voir la position',
                icon: Icons.location_on_outlined,
                style: PillStyle.tonal,
                onPressed: () => launchUrl(
                  Uri.parse('https://www.google.com/maps?q=${p.lat},${p.lng}'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            const SizedBox(height: Space.sm),
            PillButton(
              label: 'Clore l’alerte (agent en sécurité)',
              icon: Icons.verified_user_outlined,
              style: PillStyle.danger,
              loading: _saving,
              onPressed: _saving ? null : () => _close(sos),
            ),
          ],
          if (widget.open && (g.dayId != null || phone != null)) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                if (g.dayId != null)
                  Expanded(
                    child: PillButton(
                      label: 'Carte',
                      icon: Icons.map_outlined,
                      style: PillStyle.tonal,
                      onPressed: () {
                        Navigator.pop(context);
                        context.go('/map?agent=${g.agentId}');
                      },
                    ),
                  ),
                if (g.dayId != null && phone != null)
                  const SizedBox(width: Space.sm),
                if (phone != null)
                  Expanded(
                    child: PillButton(
                      label: 'Appeler',
                      icon: Icons.call_outlined,
                      style: PillStyle.tonal,
                      onPressed: () => launchUrl(
                        Uri(
                          scheme: 'tel',
                          path: phone.replaceAll(RegExp(r'[^0-9+]'), ''),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
