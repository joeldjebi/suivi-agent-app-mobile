import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/common.dart';
import '../profile/my_team.dart';
import 'missions_controller.dart';
import '../day/day_controller.dart';
import 'rejected_submissions.dart';

class MissionsScreen extends ConsumerStatefulWidget {
  const MissionsScreen({super.key});

  @override
  ConsumerState<MissionsScreen> createState() => _MissionsScreenState();
}

/// Filtre de l'agent : toutes, assignées à lui, à son groupe, ou celles où il a envoyé
/// des formulaires.
enum _Scope { all, mine, group, contributed }

bool _inScope(Mission m, _Scope scope) => switch (scope) {
  _Scope.all => true,
  _Scope.mine => !m.forGroup,
  _Scope.group => m.forGroup,
  _Scope.contributed => (m.myForms ?? 0) > 0,
};

class _MissionsScreenState extends ConsumerState<MissionsScreen> {
  bool _done = false;
  _Scope _scope = _Scope.all;

  @override
  Widget build(BuildContext context) {
    final missions = ref.watch(missionsProvider);
    final leader = ref.watch(meProvider).isTeamLead;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: leader
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/missions/create'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nouvelle mission'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(missionsProvider.future),
        child: missions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(Space.page),
            children: [
              InfoBanner(
                icon: Icons.wifi_off_rounded,
                message: ApiException.from(e).message,
              ),
            ],
          ),
          data: (all) {
            // Agent : filtre par affectation (le chef voit toutes les missions de ses équipes).
            final list = leader
                ? all
                : all.where((m) => _inScope(m, _scope)).toList();
            final groupName = leader
                ? null
                : ref.watch(myTeamProvider).value?.groupName;
            // Agent : zone de sa journée (ou celle déjà obtenue pour aujourd'hui).
            final dayState = leader ? null : ref.watch(dayProvider).value;
            final dayZone = dayState == null
                ? null
                : dayState.isWorking
                ? dayState.day!.zoneId
                : dayState.approved?.zoneId;
            final open = list
                .where(
                  (m) =>
                      m.isActive &&
                      m.isOpen &&
                      m.status != MissionStatus.achieved,
                )
                .toList();
            final done = list.where((m) => !open.contains(m)).toList();
            final shown = _done ? done : open;
            return ListView(
              // Place pour le bouton « Nouvelle mission » du chef.
              padding: EdgeInsets.only(bottom: leader ? 96 : Space.xxl),
              children: [
                BrandHeader(
                  title: 'Missions',
                  subtitle: '${open.length} en cours',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.page,
                    Space.sm,
                    Space.page,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSegmented<bool>(
                        segments: {
                          false: 'En cours (${open.length})',
                          true: 'Terminées (${done.length})',
                        },
                        selected: _done,
                        onChanged: (v) => setState(() => _done = v),
                      ),
                      if (!leader) ...[
                        const RejectedSubmissionsBanner(
                          padding: EdgeInsets.only(top: Space.md),
                        ),
                        const SizedBox(height: Space.md),
                        _ScopeChips(
                          all: all,
                          selected: _scope,
                          onChanged: (s) => setState(() => _scope = s),
                        ),
                      ],
                      const SizedBox(height: Space.lg),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xxxl),
                          child: Text(
                            _scope != _Scope.all
                                ? 'Aucune mission dans ce filtre.'
                                : _done
                                ? 'Aucune mission terminée.'
                                : 'Aucune mission en cours.\nVos missions apparaîtront ici.',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        ..._sections(
                          shown,
                          dayZone: _done ? null : dayZone,
                          groupName: groupName,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

(String, IconData, Tone) missionStatus(MissionStatus s) => switch (s) {
  MissionStatus.todo => (
    'À faire',
    Icons.radio_button_unchecked_rounded,
    Tone.neutral,
  ),
  MissionStatus.inProgress => (
    'En cours',
    Icons.trending_up_rounded,
    Tone.info,
  ),
  MissionStatus.achieved => (
    'Atteint',
    Icons.check_circle_outline_rounded,
    Tone.success,
  ),
  MissionStatus.failed => ('Échouée', Icons.cancel_outlined, Tone.danger),
};

/// Ligne de mission : petit anneau de progression, titre, avancement, pourcentage.
/// Agent avec une zone pour aujourd'hui : les missions de cette zone d'abord, puis les
/// autres avec l'endroit où les faire. Sinon, une seule liste.
List<Widget> _sections(
  List<Mission> missions, {
  required String? dayZone,
  required String? groupName,
}) {
  if (dayZone == null) {
    return [
      GroupedList(
        indent: 62,
        children: [
          for (final m in missions)
            MissionCard(mission: m, groupName: groupName),
        ],
      ),
    ];
  }
  bool here(Mission m) => m.zones.any((z) => z.id == dayZone);
  final mine = missions.where(here).toList();
  final others = missions.where((m) => !here(m)).toList();
  final zoneName = missions
      .expand((m) => m.zones)
      .where((z) => z.id == dayZone)
      .firstOrNull
      ?.name;
  return [
    GroupedList(
      header: zoneName == null ? 'Dans ma zone' : 'À faire à $zoneName',
      indent: 62,
      children: [
        for (final m in mine) MissionCard(mission: m, groupName: groupName),
        if (mine.isEmpty)
          const ListRow(title: 'Aucune mission dans votre zone aujourd’hui'),
      ],
    ),
    if (others.isNotEmpty)
      GroupedList(
        header: 'Autres zones',
        indent: 62,
        children: [
          for (final m in others)
            MissionCard(
              mission: m,
              groupName: groupName,
              where: 'à faire à ${m.zones.map((z) => z.name).join(', ')}',
            ),
        ],
      ),
  ];
}

class MissionCard extends StatelessWidget {
  const MissionCard({
    super.key,
    required this.mission,
    this.groupName,
    this.where,
  });

  /// Agent, mission d'une autre zone : où la faire.
  final String? where;

  final Mission mission;

  /// Agent : nom de son groupe, pour les missions collectives.
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (label, _, tone) = missionStatus(mission.status);
    final p = mission.progress;
    final color = toneColor(context, tone == Tone.neutral ? Tone.info : tone);
    // Agent (la liste porte ses formulaires envoyés) : affectation et participation.
    final agentView = mission.myForms != null;
    final forms = mission.myForms ?? 0;
    final details = [
      if (!mission.isActive) 'Désactivée',
      if (agentView)
        mission.forGroup ? (groupName ?? 'Mon groupe') : 'Personnelle'
      else if (mission.forGroup)
        'Équipe',
      if (forms > 0)
        '$forms formulaire${forms > 1 ? 's' : ''} envoyé${forms > 1 ? 's' : ''}',
      ?where,
      mission.progressMethod == 'manual'
          ? 'Validation du responsable'
          : '${formatNumber(p.current)} sur ${formatNumber(p.target)}',
      if (mission.dueDate != null && mission.isOpen)
        'avant le ${formatShortDate(mission.dueDate!)}',
    ].join(' · ');

    return Semantics(
      label: '${mission.title}, $label, ${p.percent} %',
      child: ListRow(
        onTap: () => context.push('/missions/${mission.id}'),
        leading: ProgressRing(
          value: p.percent / 100,
          size: 34,
          stroke: 4.5,
          color: color,
          child: mission.status == MissionStatus.achieved
              ? Icon(Icons.check_rounded, size: 18, color: color)
              : null,
        ),
        title: mission.title,
        subtitle: details,
        trailing: Text(
          '${p.percent} %',
          style: text.titleSmall?.copyWith(
            color: p.percent > 0 ? color : scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Filtres de l'agent, avec le nombre de missions de chacun.
class _ScopeChips extends StatelessWidget {
  const _ScopeChips({
    required this.all,
    required this.selected,
    required this.onChanged,
  });

  final List<Mission> all;
  final _Scope selected;
  final ValueChanged<_Scope> onChanged;

  static const _labels = {
    _Scope.all: 'Toutes',
    _Scope.mine: 'À moi',
    _Scope.group: 'Mon groupe',
    _Scope.contributed: 'Mes participations',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final scope in _Scope.values) ...[
            ChoiceChip(
              label: Text(
                '${_labels[scope]} (${all.where((m) => _inScope(m, scope)).length})',
              ),
              selected: selected == scope,
              showCheckmark: false,
              onSelected: (_) => onChanged(scope),
            ),
            const SizedBox(width: Space.sm),
          ],
        ],
      ),
    );
  }
}
