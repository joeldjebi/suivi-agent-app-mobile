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
import 'missions_controller.dart';

class MissionsScreen extends ConsumerStatefulWidget {
  const MissionsScreen({super.key});

  @override
  ConsumerState<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends ConsumerState<MissionsScreen> {
  bool _done = false;

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
          data: (list) {
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
                      const SizedBox(height: Space.lg),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xxxl),
                          child: Text(
                            _done
                                ? 'Aucune mission terminée.'
                                : 'Aucune mission en cours.\nVos missions apparaîtront ici.',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        GroupedList(
                          indent: 62,
                          children: [
                            for (final m in shown) MissionCard(mission: m),
                          ],
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
class MissionCard extends StatelessWidget {
  const MissionCard({super.key, required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (label, _, tone) = missionStatus(mission.status);
    final p = mission.progress;
    final color = toneColor(context, tone == Tone.neutral ? Tone.info : tone);
    final details = [
      if (!mission.isActive) 'Désactivée',
      if (mission.forGroup) 'Équipe',
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
