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
import 'missions_controller.dart';
import 'missions_screen.dart';
import '../day/day_controller.dart';

enum _Tab { overview, team, forms }

/// Détail d'une mission : en-tête fixe, puis trois onglets (Aperçu, Équipe, Formulaires).
class MissionScreen extends ConsumerStatefulWidget {
  const MissionScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends ConsumerState<MissionScreen> {
  _Tab _tab = _Tab.overview;

  Future<void> _refresh() async {
    ref.invalidate(submissionsProvider);
    ref.invalidate(missionProvider(widget.id));
    await ref.read(missionProvider(widget.id).future);
  }

  /// Équipe → Formulaires, filtrés sur l'agent touché.
  void _showAgent(Contribution c) {
    final notifier = ref.read(submissionFilterProvider(widget.id).notifier);
    notifier.set(
      ref
          .read(submissionFilterProvider(widget.id))
          .withAgent(c.agentId, c.name),
    );
    setState(() => _tab = _Tab.forms);
  }

  /// Actions du chef : modifier, déclarer le résultat, désactiver, supprimer.
  Future<void> _manage(Mission m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        Widget row(
          String key,
          IconData icon,
          String title, {
          String? subtitle,
          Color? color,
        }) => ListRow(
          leading: IconSquircle(
            icon: icon,
            color: color ?? scheme.primary,
            size: 28,
            solid: true,
          ),
          title: title,
          subtitle: subtitle,
          chevron: false,
          onTap: () => Navigator.pop(context, key),
        );
        final manualOpen =
            m.progressMethod == 'manual' &&
            m.isActive &&
            m.status != MissionStatus.achieved &&
            m.status != MissionStatus.failed;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            0,
            Space.page,
            Space.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GroupedList(
                children: [
                  row(
                    'edit',
                    Icons.edit_rounded,
                    'Modifier',
                    subtitle: 'Titre, consignes, cible, échéance',
                  ),
                  if (manualOpen) ...[
                    row(
                      'achieved',
                      Icons.check_rounded,
                      'Déclarer atteinte',
                      color: const Color(0xFF34A853),
                    ),
                    row(
                      'failed',
                      Icons.close_rounded,
                      'Déclarer échouée',
                      color: const Color(0xFFE5484D),
                    ),
                  ],
                  row(
                    m.isActive ? 'deactivate' : 'activate',
                    m.isActive
                        ? Icons.pause_circle_rounded
                        : Icons.play_circle_rounded,
                    m.isActive ? 'Désactiver' : 'Réactiver',
                    subtitle: m.isActive
                        ? 'Les agents ne la voient plus ; rien n’est perdu'
                        : 'Les agents la voient à nouveau',
                    color: const Color(0xFF6B7280),
                  ),
                ],
              ),
              GroupedList(
                children: [
                  ListRow(
                    title: 'Supprimer la mission',
                    titleColor: scheme.error,
                    centered: true,
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    if (action == 'edit') {
      await context.push('/missions/${m.id}/edit');
      return;
    }
    final repo = ref.read(repositoryProvider);
    try {
      switch (action) {
        case 'achieved' || 'failed':
          final achieved = action == 'achieved';
          final ok = await confirmSheet(
            context,
            title: achieved ? 'Mission atteinte ?' : 'Mission échouée ?',
            message: achieved
                ? 'L’équipe sera prévenue et la mission passera dans « Terminées ».'
                : 'La mission sera close comme non atteinte.',
            confirmLabel: achieved ? 'Déclarer atteinte' : 'Déclarer échouée',
            destructive: !achieved,
          );
          if (!ok) return;
          await repo.setMissionResult(m.id, achieved: achieved);
        case 'deactivate' || 'activate':
          await repo.updateMission(m.id, {'isActive': action == 'activate'});
        case 'delete':
          if (!mounted) return;
          final ok = await confirmSheet(
            context,
            title: 'Supprimer la mission ?',
            message:
                'La suppression est définitive. Si des formulaires ont déjà été envoyés, désactivez-la plutôt.',
            confirmLabel: 'Supprimer',
            destructive: true,
          );
          if (!ok) return;
          await repo.deleteMission(m.id);
          ref.invalidate(missionsProvider);
          if (!mounted) return;
          showMessage(context, 'Mission supprimée');
          context.pop();
          return;
      }
      ref.invalidate(missionProvider(m.id));
      ref.invalidate(missionsProvider);
      if (mounted) {
        showMessage(context, switch (action) {
          'achieved' => 'Mission déclarée atteinte',
          'failed' => 'Mission déclarée échouée',
          'deactivate' => 'Mission désactivée',
          _ => 'Mission réactivée',
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      showMessage(
        context,
        e.code == 'HAS_DEPENDENCIES'
            ? 'Des formulaires ont déjà été reçus : désactivez la mission plutôt que de la supprimer.'
            : e.message,
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final mission = ref.watch(missionProvider(id));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Le chef d'équipe suit la mission ; seuls les agents remplissent des formulaires.
    final leader = ref.watch(meProvider).isTeamLead;
    // Les filtres vivent tant que la mission est ouverte, quel que soit l'onglet.
    ref.watch(submissionFilterProvider(id));

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (leader && mission.hasValue)
            IconButton(
              tooltip: 'Gérer la mission',
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: () => _manage(mission.value!),
            ),
        ],
      ),
      body: mission.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: InfoBanner(
            icon: Icons.error_outline_rounded,
            message: ApiException.from(e).message,
            tone: Tone.danger,
          ),
        ),
        data: (m) {
          // Le détail par agent est réservé au chef.
          final hasTeam = leader && m.contributions.isNotEmpty;
          final tab = !hasTeam && _tab == _Tab.team ? _Tab.overview : _tab;
          final overline = [
            if (!m.isActive) 'Désactivée',
            if (m.typeName != null) m.typeName!,
            if (m.forGroup) 'Objectif d’équipe',
          ].join(' · ');

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page + Space.xs,
                  0,
                  Space.page,
                  Space.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (overline.isNotEmpty)
                      Text(
                        overline.toUpperCase(),
                        style: text.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.4,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      m.title,
                      style: text.headlineMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  0,
                  Space.page,
                  Space.sm,
                ),
                child: AppSegmented<_Tab>(
                  segments: {
                    _Tab.overview: 'Aperçu',
                    if (hasTeam) _Tab.team: 'Équipe',
                    _Tab.forms: leader ? 'Formulaires' : 'Mes formulaires',
                  },
                  selected: tab,
                  onChanged: (t) => setState(() => _tab = t),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: switch (tab) {
                    _Tab.overview => _Overview(mission: m, leader: leader),
                    _Tab.team => _TeamTab(
                      mission: m,
                      leader: leader,
                      onAgent: _showAgent,
                    ),
                    _Tab.forms => _FormsTab(mission: m, leader: leader),
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar:
          !leader &&
              mission.hasValue &&
              mission.requireValue.isOpen &&
              mission.requireValue.progressMethod != 'manual'
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _SubmitAction(mission: mission.requireValue),
              ),
            )
          : null,
    );
  }
}

/// Défilement commun aux onglets (marges, place pour le bouton du bas).
ListView _tabList(List<Widget> children) => ListView(
  physics: const AlwaysScrollableScrollPhysics(),
  padding: const EdgeInsets.fromLTRB(
    Space.page,
    Space.sm,
    Space.page,
    Space.xxxl * 3,
  ),
  children: children,
);

String _methodLabel(Mission m) => switch (m.progressMethod) {
  'count' => 'Chaque formulaire envoyé compte pour 1.',
  'field_sum' => 'Les montants saisis sont additionnés.',
  _ => 'Votre responsable valide l’atteinte de l’objectif.',
};

Color _missionColor(BuildContext context, Mission m) {
  final (_, _, tone) = missionStatus(m.status);
  return toneColor(context, tone == Tone.neutral ? Tone.info : tone);
}

/// Aperçu : anneau, statut, détails, consignes.
class _Overview extends StatelessWidget {
  const _Overview({required this.mission, required this.leader});

  final Mission mission;
  final bool leader;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (label, _, tone) = missionStatus(m.status);
    final color = _missionColor(context, m);

    return _tabList([
      SurfaceCard(
        padding: const EdgeInsets.symmetric(vertical: Space.xl),
        child: Column(
          children: [
            Semantics(
              label: 'Progression : ${m.progress.percent} %',
              excludeSemantics: true,
              child: ProgressRing(
                value: m.progress.percent / 100,
                size: 150,
                stroke: 16,
                color: color,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${m.progress.percent} %',
                      style: text.displaySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      m.progressMethod == 'manual'
                          ? 'manuel'
                          : '${formatNumber(m.progress.current)} sur ${formatNumber(m.progress.target)}',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            StatusPill(label: label, color: toneColor(context, tone)),
          ],
        ),
      ),
      if (!leader && m.myContribution != null)
        _MyContribution(mission: m, color: color),
      GroupedList(
        header: 'Détails',
        indent: Space.lg,
        footer: _methodLabel(m),
        children: [
          ListRow(
            title: 'Objectif',
            value: m.progressMethod == 'manual'
                ? 'Validation'
                : formatNumber(m.progress.target),
          ),
          if (m.dueDate != null)
            ListRow(
              title: 'Échéance',
              value:
                  '${formatShortDate(m.dueDate!)} à ${formatTime(m.dueDate!)}',
            ),
          if (m.typeName != null) ListRow(title: 'Type', value: m.typeName),
          if (m.zones.isNotEmpty)
            ListRow(
              title: m.zones.length > 1 ? 'Zones' : 'Zone',
              value: m.zones.map((z) => z.name).join(', '),
            ),
          if (leader && m.hasOwnPay)
            const ListRow(title: 'Rémunération', value: 'Propre à la mission'),
        ],
      ),
      if (!leader && m.earnings != null && !m.earnings!.isEmpty)
        MissionEarningsCard(earnings: m.earnings!),
      if (m.description != null) ...[
        const SectionHeader('Consignes'),
        SurfaceCard(child: Text(m.description!, style: text.bodyLarge)),
      ],
    ]);
  }
}

/// Agent : ce que rapporte la mission (conditions propres, ou sa grille).
class MissionEarningsCard extends StatelessWidget {
  const MissionEarningsCard({super.key, required this.earnings});

  final MissionEarnings earnings;

  @override
  Widget build(BuildContext context) {
    final e = earnings;
    final money = toneColor(context, Tone.success);
    return GroupedList(
      header: 'Ce que rapporte cette mission',
      indent: Space.lg,
      footer: switch (e.source) {
        'mission' =>
          'Conditions propres à cette mission. Vos gains de la période sont dans « Mes gains ».',
        'type' =>
          'Conditions du type de mission. Vos gains de la période sont dans « Mes gains ».',
        _ =>
          'Selon votre grille de rémunération. Vos gains de la période sont dans « Mes gains ».',
      },
      children: [
        if ((e.perForm ?? 0) > 0)
          ListRow(
            leading: IconSquircle(
              icon: Icons.description_outlined,
              color: money,
              size: 28,
              solid: true,
            ),
            title: 'Par formulaire accepté',
            value: formatMoney(e.perForm!),
          ),
        if ((e.commissionPercent ?? 0) > 0)
          ListRow(
            leading: IconSquircle(
              icon: Icons.percent_rounded,
              color: money,
              size: 28,
              solid: true,
            ),
            title: 'Commission',
            value: '${formatNumber(e.commissionPercent!)} % des montants',
          ),
        for (final t in e.tiers)
          ListRow(
            leading: IconSquircle(
              icon: Icons.emoji_events_outlined,
              color: const Color(0xFFD97706),
              size: 28,
              solid: true,
            ),
            title: 'Prime à ${t.threshold} % de l’objectif',
            value: formatMoney(t.amount),
          ),
      ],
    );
  }
}

/// Agent, mission d'équipe : sa part de l'objectif commun.
class _MyContribution extends StatelessWidget {
  const _MyContribution({required this.mission, required this.color});

  final Mission mission;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final mine = m.myContribution!;
    final team = m.progress.current;
    final share = team <= 0 ? 0 : (mine / team * 100).round();
    final unit = m.progressMethod == 'count'
        ? (mine == 1 ? 'formulaire' : 'formulaires')
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Ma contribution'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatNumber(mine),
                    style: text.displaySmall?.copyWith(
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      unit,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              ThinProgress(value: team <= 0 ? 0 : mine / team, color: color),
              const SizedBox(height: Space.sm),
              Text(
                mine <= 0
                    ? 'Vos formulaires validés compteront ici.'
                    : '$share % de la progression de l’équipe',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Équipe : contribution de chaque agent ; le chef touche un agent pour voir ses formulaires.
class _TeamTab extends StatelessWidget {
  const _TeamTab({
    required this.mission,
    required this.leader,
    required this.onAgent,
  });

  final Mission mission;
  final bool leader;
  final ValueChanged<Contribution> onAgent;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = _missionColor(context, m);
    final sorted = [...m.contributions]
      ..sort((a, b) => b.value.compareTo(a.value));

    return _tabList([
      GroupedList(
        header: 'Contributions',
        indent: Space.lg,
        footer: leader ? 'Touchez un agent pour voir ses formulaires.' : null,
        children: [
          for (final c in sorted)
            InkWell(
              onTap: leader && c.agentId != null ? () => onAgent(c) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.md,
                  Space.md,
                  Space.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: text.bodyLarge?.medium,
                                ),
                              ),
                              Text(
                                formatNumber(c.value),
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.sm),
                          ThinProgress(
                            value: c.value / m.progress.target,
                            color: color,
                            height: 4,
                          ),
                        ],
                      ),
                    ),
                    if (leader && c.agentId != null) ...[
                      const SizedBox(width: Space.sm),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    ]);
  }
}

/// Formulaires : filtres (chef), envois en attente (agent), jours en accordéon.
class _FormsTab extends ConsumerStatefulWidget {
  const _FormsTab({required this.mission, required this.leader});

  final Mission mission;
  final bool leader;

  @override
  ConsumerState<_FormsTab> createState() => _FormsTabState();
}

class _FormsTabState extends ConsumerState<_FormsTab> {
  /// Jours ouverts ou fermés à la main ; sinon : aujourd'hui ouvert,
  /// ou tout ouvert quand un filtre réduit déjà la liste.
  final _open = <DateTime, bool>{};

  Mission get mission => widget.mission;

  Future<void> _reject(Submission s) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _RejectSheet(),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await ref.read(repositoryProvider).rejectSubmission(s.id, reason);
      ref.invalidate(submissionsProvider);
      ref.invalidate(missionProvider(mission.id));
      if (mounted) {
        showMessage(context, 'Formulaire rejeté, l’agent a été prévenu');
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leader = widget.leader;
    // L'agent voit tous ses formulaires ; le chef filtre ceux de son équipe.
    final filter = leader
        ? ref.watch(submissionFilterProvider(mission.id))
        : const SubmissionFilter();
    ref.listen(submissionFilterProvider(mission.id), (_, _) {
      setState(_open.clear);
    });
    final local = leader
        ? const <PendingSubmission>[]
        : ref.watch(localSubmissionsProvider(mission.id)).value ?? [];
    final remote = ref.watch(
      submissionsProvider((missionId: mission.id, filter: filter)),
    );
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // Titre : la première valeur saisie ; détail : le champ suivant.
    List<MissionField> filled(Map<String, dynamic> data) => mission.fields
        .where((f) => data[f.key] != null && data[f.key] != '')
        .toList();
    String summary(Map<String, dynamic> data) {
      final f = filled(data).firstOrNull;
      return f == null ? '' : _display(f, data[f.key]);
    }

    String? detail(Map<String, dynamic> data) {
      final f = filled(data).skip(1).firstOrNull;
      return f == null ? null : '${f.label} : ${_display(f, data[f.key])}';
    }

    final sent = remote.value ?? const <Submission>[];
    final byDay = <DateTime, List<Submission>>{};
    for (final s in sent) {
      final d = s.submittedAt;
      byDay.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(s);
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    bool isOpen(DateTime day) =>
        _open[day] ?? (filter.isActive || day == today);
    final allOpen = byDay.keys.isNotEmpty && byDay.keys.every(isOpen);

    return _tabList([
      if (leader) ...[
        _FilterBar(mission: mission, filter: filter),
        const SizedBox(height: Space.md),
      ],
      if (remote.hasValue && sent.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, 0, 0, Space.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${sent.length} formulaire${sent.length > 1 ? 's' : ''}',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  for (final day in byDay.keys) {
                    _open[day] = !allOpen;
                  }
                }),
                child: Text(allOpen ? 'Tout fermer' : 'Tout ouvrir'),
              ),
            ],
          ),
        ),
      if (local.isNotEmpty) ...[
        GroupedList(
          header: 'En attente d’envoi',
          indent: Space.lg,
          children: [
            for (final s in local)
              _SubmissionRow(
                title: summary(jsonDecode(s.dataJson) as Map<String, dynamic>),
                subtitle:
                    s.error ?? 'Saisi à ${formatTime(s.submittedAt.toLocal())}',
                chip: s.error != null
                    ? const StatusChip(
                        label: 'Refusé',
                        icon: Icons.error_outline_rounded,
                        tone: Tone.danger,
                      )
                    : const StatusChip(
                        label: 'En attente',
                        icon: Icons.cloud_upload_outlined,
                        tone: Tone.warning,
                      ),
                onDiscard: s.error != null
                    ? () => discardSubmission(ref, s.clientId)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: Space.md),
      ],
      if (sent.isEmpty && local.isEmpty)
        SurfaceCard(
          child: Column(
            children: [
              Text(
                remote.isLoading
                    ? 'Chargement…'
                    : remote.hasError
                    ? ApiException.from(remote.error!).message
                    : filter.isActive
                    ? 'Aucun formulaire pour ces filtres.'
                    : 'Aucun formulaire pour le moment.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (filter.isActive && !remote.isLoading)
                TextButton(
                  onPressed: () => ref
                      .read(submissionFilterProvider(mission.id).notifier)
                      .set(const SubmissionFilter()),
                  child: const Text('Effacer les filtres'),
                ),
            ],
          ),
        ),
      for (final entry in byDay.entries) ...[
        _DayAccordion(
          label: _dayLabel(entry.key),
          submissions: entry.value,
          open: isOpen(entry.key),
          onToggle: () => setState(() => _open[entry.key] = !isOpen(entry.key)),
          rows: [
            for (final s in entry.value)
              _SubmissionRow(
                title: summary(s.data),
                subtitle: [
                  if (leader && s.agentName != null) s.agentName!,
                  formatTime(s.submittedAt),
                  if (s.rejected)
                    'Rejeté : ${s.rejectedReason ?? ''}'
                  else if (detail(s.data) case final d?)
                    d,
                ].join(' · '),
                chip: s.rejected
                    ? const StatusChip(
                        label: 'Rejeté',
                        icon: Icons.block_rounded,
                        tone: Tone.danger,
                      )
                    : null,
                onTap: () => _showSubmission(
                  context,
                  mission: mission,
                  submission: s,
                  onReject: leader && !s.rejected ? () => _reject(s) : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
      ],
    ]);
  }
}

/// Un jour de formulaires : en-tête toujours visible, lignes repliables.
class _DayAccordion extends StatelessWidget {
  const _DayAccordion({
    required this.label,
    required this.submissions,
    required this.open,
    required this.onToggle,
    required this.rows,
  });

  final String label;
  final List<Submission> submissions;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rejected = submissions.where((s) => s.rejected).length;
    final count = submissions.length;
    final summary = [
      '$count formulaire${count > 1 ? 's' : ''}',
      if (rejected > 0) '$rejected rejeté${rejected > 1 ? 's' : ''}',
    ].join(' · ');

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: '$label, $summary',
            excludeSemantics: true,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.md,
                  Space.md,
                  Space.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: text.bodyLarge?.semibold),
                          const SizedBox(height: 1),
                          Text.rich(
                            TextSpan(
                              text: '$count formulaire${count > 1 ? 's' : ''}',
                              children: [
                                if (rejected > 0)
                                  TextSpan(
                                    text:
                                        ' · $rejected rejeté${rejected > 1 ? 's' : ''}',
                                    style: TextStyle(
                                      color: toneColor(context, Tone.danger),
                                    ),
                                  ),
                              ],
                            ),
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: Motion.of(context, Motion.fast),
                      curve: Motion.curve,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 22,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context, Motion.medium),
            curve: Motion.curve,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    children: [
                      for (final row in rows) ...[
                        Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: Space.lg,
                          color: scheme.outlineVariant,
                        ),
                        row,
                      ],
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// « Aujourd'hui », « Hier », puis la date.
String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Aujourd’hui';
  if (diff == 1) return 'Hier';
  return formatDay(day);
}

/// Filtres du chef : agent, période, statut. Chaque pastille ouvre un choix.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.mission, required this.filter});

  final Mission mission;
  final SubmissionFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(submissionFilterProvider(mission.id).notifier);
    final agents = mission.contributions.where((c) => c.agentId != null);

    // Trois pastilles au plus : une rangée défilante, toutes construites.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: SizedBox(
        height: 36,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (agents.isNotEmpty) ...[
              _FilterChip(
                icon: Icons.person_outline_rounded,
                label: filter.agentName ?? 'Tous les agents',
                active: filter.agentId != null,
                onTap: () async {
                  final picked = await pickOption<String?>(
                    context,
                    title: 'Agent',
                    selected: filter.agentId,
                    options: {
                      null: 'Tous les agents',
                      for (final c in agents) c.agentId: c.name,
                    },
                  );
                  if (picked == null) return;
                  final id = picked.value;
                  controller.set(
                    filter.withAgent(
                      id,
                      agents.where((c) => c.agentId == id).firstOrNull?.name,
                    ),
                  );
                },
              ),
              const SizedBox(width: Space.sm),
            ],
            _FilterChip(
              icon: Icons.calendar_today_rounded,
              label: filter.period.label,
              active: filter.period != SubmissionPeriod.all,
              onTap: () async {
                final picked = await pickOption<SubmissionPeriod>(
                  context,
                  title: 'Période',
                  selected: filter.period,
                  options: {
                    for (final p in SubmissionPeriod.values) p: p.label,
                  },
                );
                if (picked != null) {
                  controller.set(filter.withPeriod(picked.value));
                }
              },
            ),
            const SizedBox(width: Space.sm),
            _FilterChip(
              icon: Icons.task_alt_rounded,
              label: switch (filter.rejected) {
                null => 'Tous les statuts',
                false => 'Valides',
                true => 'Rejetés',
              },
              active: filter.rejected != null,
              onTap: () async {
                final picked = await pickOption<bool?>(
                  context,
                  title: 'Statut',
                  selected: filter.rejected,
                  options: const {
                    null: 'Tous les statuts',
                    false: 'Valides',
                    true: 'Rejetés',
                  },
                );
                if (picked != null) {
                  controller.set(filter.withStatus(picked.value));
                }
              },
            ),
            if (filter.isActive) ...[
              const SizedBox(width: Space.xs),
              TextButton(
                onPressed: () => controller.set(const SubmissionFilter()),
                child: const Text('Effacer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pastille de filtre : grise au repos, à la couleur de la structure si active.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurface;
    return Semantics(
      button: true,
      label: 'Filtre : $label',
      excludeSemantics: true,
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: color),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fiche complète d'un formulaire : tous les champs, l'auteur, l'heure.
Future<void> _showSubmission(
  BuildContext context, {
  required Mission mission,
  required Submission submission,
  VoidCallback? onReject,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  builder: (context) {
    final s = submission;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Formulaire', style: text.headlineSmall),
                const SizedBox(height: 2),
                Text(
                  [
                    if (s.agentName != null) s.agentName!,
                    '${formatShortDate(s.submittedAt)} à ${formatTime(s.submittedAt)}',
                  ].join(' · '),
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (s.rejected) ...[
            const SizedBox(height: Space.md),
            InfoBanner(
              icon: Icons.block_rounded,
              message: 'Rejeté : ${s.rejectedReason ?? ''}',
              tone: Tone.danger,
            ),
          ],
          GroupedList(
            header: 'Réponses',
            indent: Space.lg,
            children: [
              for (final f in mission.fields)
                ListRow(
                  title: f.label,
                  value: s.data[f.key] == null || s.data[f.key] == ''
                      ? '—'
                      : _display(f, s.data[f.key]),
                ),
            ],
          ),
          if (onReject != null) ...[
            const SizedBox(height: Space.xl),
            PillButton(
              label: 'Rejeter ce formulaire',
              icon: Icons.block_rounded,
              style: PillStyle.outline,
              onPressed: () {
                Navigator.pop(context);
                onReject();
              },
            ),
          ],
        ],
      ),
    );
  },
);

/// Motif du rejet. Le champ appartient à la feuille : il vit jusqu'à la fin de
/// l'animation de fermeture.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet();

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.xxl,
        0,
        Space.xxl,
        Space.xxl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Rejeter le formulaire', style: text.headlineSmall),
          const SizedBox(height: Space.sm),
          Text(
            'Il ne comptera plus dans la progression. L’agent verra le motif.',
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motif',
              hintText: 'Ex. : visite en double',
            ),
          ),
          const SizedBox(height: Space.sm),
          PillButton(
            label: 'Rejeter',
            style: PillStyle.danger,
            onPressed: () => Navigator.pop(context, _reason.text.trim()),
          ),
          const SizedBox(height: Space.sm),
          PillButton(
            label: 'Annuler',
            style: PillStyle.outline,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  const _SubmissionRow({
    required this.title,
    required this.subtitle,
    this.chip,
    this.onDiscard,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget? chip;
  final VoidCallback? onDiscard;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, 10, Space.md, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? 'Formulaire' : title,
                    style: text.bodyLarge?.medium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ?chip,
            if (onDiscard != null)
              IconButton(
                tooltip: 'Supprimer ce formulaire',
                onPressed: onDiscard,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }
}

String _display(MissionField f, Object? v) => switch (f.type) {
  FieldType.boolean => v == true ? 'Oui' : 'Non',
  FieldType.number => formatNumber(v as num),
  FieldType.date => formatShortDate(DateTime.parse(v as String)),
  _ => '$v',
};

/// Envoi d'un formulaire : pendant la journée, dans une zone de la mission (si la structure
/// l'exige). Sinon, ce qu'il manque et le chemin pour y remédier.
class _SubmitAction extends ConsumerWidget {
  const _SubmitAction({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final day = ref.watch(dayProvider).value;
    final working = day?.isWorking ?? false;
    final dayZone = working ? day!.day!.zoneId : null;
    final inZone =
        mission.zones.isEmpty || mission.zones.any((z) => z.id == dayZone);
    if (!me.submissionRequiresDay || (working && inZone)) {
      return PillButton(
        label: 'Nouveau formulaire',
        icon: Icons.add_rounded,
        onPressed: () => context.push('/missions/${mission.id}/new'),
      );
    }
    final zones = mission.zones.map((z) => z.name).join(', ');
    return InfoBanner(
      icon: working
          ? Icons.wrong_location_outlined
          : Icons.play_circle_outline_rounded,
      tone: Tone.info,
      message: working
          ? 'Cette mission se fait à : $zones. Vous travaillez aujourd’hui dans une autre zone.'
          : 'Démarrez votre journée${zones.isEmpty ? '' : ' à $zones'} pour envoyer un formulaire.',
      action: working
          ? null
          : TextButton(
              onPressed: () => context.go('/day'),
              child: const Text('Ma journée'),
            ),
    );
  }
}
