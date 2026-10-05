import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/common.dart';
import 'alerts_screen.dart';
import 'report_screen.dart';
import 'team_controller.dart';

/// Chef d'équipe : ses agents en direct, les alertes d'abord.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamProvider);
    final pending = ref.watch(requestsProvider).value?.length ?? 0;
    final openAlerts = ref.watch(openAlertsProvider).value?.length;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: HeroScaffoldBody(
        onRefresh: () async {
          await ref.read(teamProvider.notifier).refresh();
          await ref.read(openAlertsProvider.notifier).refresh();
        },
        header: const BrandHeader(title: 'Mon équipe'),
        children: [
          team.when(
            loading: () => const SurfaceCard(
              child: SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => InfoBanner(
              icon: Icons.wifi_off_rounded,
              message: ApiException.from(e).message,
              action: TextButton(
                onPressed: () => ref.invalidate(teamProvider),
                child: const Text('Réessayer'),
              ),
            ),
            data: (t) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'En journée',
                        value: t.active,
                        tone: Tone.success,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _Stat(
                        label: 'En pause',
                        value: t.paused,
                        tone: Tone.warning,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _Stat(
                        label: 'Alertes',
                        // Centre d'alertes (dont « journée pas démarrée ») ; à défaut, l'équipe.
                        value: openAlerts ?? t.alerts.length,
                        tone: (openAlerts ?? t.alerts.length) == 0
                            ? Tone.neutral
                            : Tone.danger,
                        onTap: () => context.push('/alerts'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Shortcut(
                          icon: Icons.insights_rounded,
                          label: 'Bilan du jour',
                          onTap: () => context.push('/report'),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: _Shortcut(
                          icon: Icons.campaign_outlined,
                          label: 'Message à l’équipe',
                          onTap: () => showTeamMessageSheet(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (pending > 0) ...[
                  const SizedBox(height: Space.sm),
                  SurfaceCard(
                    onTap: () => context.go('/requests'),
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.md,
                      Space.md,
                      Space.md,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.pending_actions_outlined,
                          size: 20,
                          color: toneColor(context, Tone.warning),
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            '$pending demande${pending > 1 ? 's' : ''} de zone à valider',
                            style: text.titleSmall,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 20),
                      ],
                    ),
                  ),
                ],
                if (t.alerts.isNotEmpty) ...[
                  SectionHeader(
                    'À surveiller',
                    trailing: TextButton(
                      onPressed: () => context.push('/alerts'),
                      child: const Text('Toutes les alertes'),
                    ),
                  ),
                  GroupedList(
                    children: [
                      for (final a in t.alerts) _AgentRow(agent: a, team: t),
                    ],
                  ),
                ],
                if (t.working.isNotEmpty) ...[
                  const SectionHeader('En journée'),
                  GroupedList(
                    children: [
                      for (final a in t.working) _AgentRow(agent: a, team: t),
                    ],
                  ),
                ],
                if (t.idle.isNotEmpty) ...[
                  const SectionHeader('Pas encore en journée'),
                  GroupedList(
                    children: [for (final m in t.idle) _IdleRow(member: m)],
                  ),
                ],
                if (t.live.isEmpty && t.idle.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: Space.xxxl),
                    child: Text(
                      'Aucun agent dans votre équipe pour le moment.',
                      textAlign: TextAlign.center,
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

/// Raccourci de « Mon équipe » (bilan, message).
class _Shortcut extends StatelessWidget {
  const _Shortcut({
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
    return SurfaceCard(
      onTap: onTap,
      semanticLabel: label,
      radius: Radii.tile,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.tone,
    this.onTap,
  });

  final String label;
  final int value;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$value $label',
      button: onTap != null,
      excludeSemantics: true,
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.md,
        ),
        radius: Radii.tile,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: text.headlineSmall?.copyWith(
                color: toneColor(context, tone),
              ),
            ),
            Text(
              label,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Raison de l'alerte, en clair.
String? alertLabel(LiveAgent a) => a.signalLost
    ? 'Signal perdu'
    : a.isMocked
    ? 'Position simulée'
    : a.outsideZone
    ? outsideLabel(a)
    : a.alerts.isNotEmpty
    ? alertLabelOf(a.alerts.first)
    : null;

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent, required this.team});

  final LiveAgent agent;
  final TeamOverview team;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final alert = alertLabel(agent);
    final paused = agent.status == DayStatus.paused;
    final color = alert != null
        ? scheme.error
        : toneColor(context, paused ? Tone.warning : Tone.success);
    final status = alert ?? (paused ? 'En pause' : 'En cours');

    return InkWell(
      onTap: () => showAgentSheet(context, agent: agent, team: team),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            StatusAvatar(
              initials: team.members[agent.agentId]?.initials ?? '?',
              ringColor: color,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.name,
                    style: text.titleSmall?.copyWith(fontSize: 15),
                  ),
                  Text(
                    '${team.zoneName(agent.zoneId)} · ${agent.lastPositionAt == null ? 'aucune position' : formatAgo(agent.lastPositionAt!)}',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Text(status, style: text.labelMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _IdleRow extends StatelessWidget {
  const _IdleRow({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.xs,
        Space.sm,
      ),
      child: Row(
        children: [
          StatusAvatar(initials: member.initials, ringColor: scheme.outline),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.fullName,
                  style: text.titleSmall?.copyWith(fontSize: 15),
                ),
                Text(
                  'Journée non démarrée',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (member.phone != null)
            IconButton(
              tooltip: 'Appeler ${member.fullName}',
              icon: Icon(Icons.call_outlined, color: scheme.primary, size: 20),
              onPressed: () => _call(member.phone!),
            ),
        ],
      ),
    );
  }
}

void _call(String phone) => launchUrl(
  Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')),
);

/// Fiche d'un agent : état, alertes, appel, réaffectation.
Future<void> showAgentSheet(
  BuildContext context, {
  required LiveAgent agent,
  required TeamOverview team,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _AgentSheet(agent: agent, team: team),
  );
}

class _AgentSheet extends ConsumerStatefulWidget {
  const _AgentSheet({required this.agent, required this.team});

  final LiveAgent agent;
  final TeamOverview team;

  @override
  ConsumerState<_AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends ConsumerState<_AgentSheet> {
  bool _reassigning = false;
  String? _sending;

  Future<void> _reassign(Zone zone) async {
    tapFeedback();
    setState(() => _sending = zone.id);
    try {
      await ref
          .read(teamProvider.notifier)
          .reassign(widget.agent.agentId, zone.id);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(
        context,
        '${widget.agent.name} est affecté(e) à ${zone.name}. L’agent a été prévenu.',
      );
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.agent;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final phone = widget.team.members[a.agentId]?.phone;
    final alert = alertLabel(a);
    final paused = a.status == DayStatus.paused;
    final color = alert != null
        ? scheme.error
        : toneColor(context, paused ? Tone.warning : Tone.success);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusAvatar(
                initials: widget.team.members[a.agentId]?.initials ?? '?',
                ringColor: color,
                size: 48,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, style: text.titleLarge),
                    Text(
                      paused
                          ? 'En pause'
                          : 'En journée depuis ${formatTime(a.startedAt)}',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          if (alert != null) ...[
            InfoBanner(
              icon: Icons.warning_amber_rounded,
              tone: Tone.danger,
              message: switch (alert) {
                'Signal perdu' =>
                  'Aucune position récente : GPS coupé, application fermée ou réseau absent.',
                'Position simulée' =>
                  'Le téléphone signale une position simulée (application de faux GPS).',
                _ => 'La dernière position est en dehors de sa zone.',
              },
            ),
            const SizedBox(height: Space.sm),
          ],
          InfoRow(
            icon: Icons.place_outlined,
            label: 'Zone',
            value: widget.team.zoneName(a.zoneId),
          ),
          InfoRow(
            icon: Icons.my_location_outlined,
            label: 'Dernière position',
            value: a.lastPositionAt == null
                ? '—'
                : formatAgo(a.lastPositionAt!),
          ),
          if (a.batteryLevel != null)
            InfoRow(
              icon: a.batteryLevel! < 0.2
                  ? Icons.battery_alert_outlined
                  : Icons.battery_5_bar_outlined,
              label: 'Batterie',
              value: '${(a.batteryLevel! * 100).round()} %',
              tone: a.batteryLevel! < 0.2 ? Tone.danger : null,
            ),
          const SizedBox(height: Space.lg),
          if (!_reassigning && a.position != null) ...[
            PillButton(
              label: 'Voir sur la carte',
              icon: Icons.map_rounded,
              style: PillStyle.tonal,
              onPressed: () {
                Navigator.pop(context);
                context.go('/map?agent=${a.agentId}');
              },
            ),
            const SizedBox(height: Space.sm),
          ],
          if (!_reassigning)
            Row(
              children: [
                if (phone != null) ...[
                  Expanded(
                    child: PillButton(
                      label: 'Appeler',
                      icon: Icons.call_outlined,
                      onPressed: () => _call(phone),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                ],
                Expanded(
                  child: PillButton(
                    label: 'Changer de zone',
                    style: PillStyle.outline,
                    onPressed: () => setState(() => _reassigning = true),
                  ),
                ),
              ],
            )
          else ...[
            Text('Nouvelle zone', style: text.titleSmall),
            const SizedBox(height: Space.sm),
            GroupedList(
              children: [
                for (final z in widget.team.zones.where(
                  (z) => z.id != a.zoneId,
                ))
                  InkWell(
                    onTap: z.isFull || _sending != null
                        ? null
                        : () => _reassign(z),
                    child: Opacity(
                      opacity: z.isFull ? 0.5 : 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg,
                          vertical: Space.md,
                        ),
                        child: Row(
                          children: [
                            const IconSquircle(
                              icon: Icons.place_outlined,
                              size: 32,
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: Text(z.name, style: text.titleSmall),
                            ),
                            if (_sending == z.id)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Text(
                                z.isFull
                                    ? 'Complète'
                                    : z.capacity == null
                                    ? 'Illimitée'
                                    : '${z.placesLeft} place(s)',
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            TextButton(
              onPressed: () => setState(() => _reassigning = false),
              child: const Text('Annuler'),
            ),
          ],
        ],
      ),
    );
  }
}
