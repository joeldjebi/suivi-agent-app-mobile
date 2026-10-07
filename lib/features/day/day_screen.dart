import 'week_screen.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/branding.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/common.dart';
import 'day_controller.dart';
import 'location_consent.dart';
import 'zone_map.dart';
import 'zone_picker.dart';
import '../profile/my_team.dart';
import '../missions/rejected_submissions.dart';

/// Durée de référence d'une journée, pour la barre de progression.

/// Écran principal de l'agent : sa journée, une action à la fois.
class DayScreen extends ConsumerStatefulWidget {
  const DayScreen({super.key});

  @override
  ConsumerState<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends ConsumerState<DayScreen>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(dayProvider.notifier).refresh());
      unawaited(ref.read(syncProvider).flush());
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) showMessage(context, success);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final me = ref.read(meProvider);
    final ok = await ensureLocationConsent(
      context,
      ref.read(trackerProvider),
      structure: ref.read(brandingProvider).displayName,
      trackDuringPause: me.trackDuringPause,
    );
    if (!ok) {
      if (mounted) {
        showMessage(
          context,
          'L’accès à la position est nécessaire pour démarrer la journée.',
          error: true,
        );
      }
      return;
    }
    await _run(
      () => ref.read(dayProvider.notifier).act('start'),
      success: 'Journée démarrée. Bon courage !',
    );
  }

  Future<void> _end() async {
    final confirmed = await confirmSheet(
      context,
      title: 'Terminer la journée ?',
      message:
          'Le partage de votre position s’arrête et votre place dans la zone est libérée.',
      confirmLabel: 'Terminer ma journée',
      destructive: true,
    );
    if (confirmed) {
      await _run(
        () => ref.read(dayProvider.notifier).act('end'),
        success: 'Journée terminée. Merci !',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(brandingProvider);
    final me = ref.watch(meProvider);
    final day = ref.watch(dayProvider);

    return Scaffold(
      body: HeroScaffoldBody(
        header: const BrandHeader(title: 'Ma journée'),
        onRefresh: () async {
          await ref.read(dayProvider.notifier).refresh();
          await ref.read(syncProvider).flush();
        },
        children: [
          day.when(
            loading: () => const SurfaceCard(
              child: SizedBox(
                height: 300,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => InfoBanner(
              icon: Icons.wifi_off_rounded,
              message: ApiException.from(e).message,
              action: TextButton(
                onPressed: () => ref.invalidate(dayProvider),
                child: const Text('Réessayer'),
              ),
            ),
            data: (s) => _DayContent(state: s, branding: branding, me: me),
          ),
        ],
      ),
      bottomNavigationBar: day.hasValue
          ? _ActionBar(
              state: day.requireValue,
              busy: _busy,
              zoneRequired: me.zoneRequired,
              onChooseZone: () => showZonePicker(
                context,
                currentZoneId: day.requireValue.approved?.zoneId,
              ),
              onStart: _start,
              onPause: () => _run(
                () => ref.read(dayProvider.notifier).act('pause'),
                success: 'Pause commencée',
              ),
              onResume: () => _run(
                () => ref.read(dayProvider.notifier).act('resume'),
                success: 'Bonne reprise !',
              ),
              onEnd: _end,
            )
          : null,
    );
  }
}

class _DayContent extends ConsumerWidget {
  const _DayContent({
    required this.state,
    required this.branding,
    required this.me,
  });

  final DayState state;
  final Branding branding;
  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(availableZonesProvider).value;
    String? zoneName(String? id) => id == null
        ? null
        : zones?.zones.where((z) => z.id == id).firstOrNull?.name;
    final zone = zoneName(state.day?.zoneId ?? state.approved?.zoneId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.isWorking) const OutsideZoneBanner(),
        if (me.isAgent)
          const RejectedSubmissionsBanner(
            padding: EdgeInsets.only(bottom: Space.lg),
          ),
        _StatusCard(
          state: state,
          zoneName: zone,
          target: Duration(minutes: me.workdayMinutes),
        ),
        if (state.isWorking) const ZoneCard(),
        if (state.isWorking) const _LiveRows(),
        if (state.pending != null ||
            (!state.isWorking && state.approved != null))
          _ZoneGroup(state: state, zoneName: zoneName, me: me),
        if (me.isAgent) const WeekShortcut(),
        if (!state.isWorking && me.isAgent) const MyTeamCard(),
        if (!state.isWorking && branding.welcomeMessage != null) ...[
          const SizedBox(height: Space.xl),
          _MessageCard(branding: branding),
        ],
      ],
    );
  }
}

/// Carte principale : statut, anneau du temps travaillé, repères de la journée.
class _StatusCard extends StatefulWidget {
  const _StatusCard({
    required this.state,
    required this.zoneName,
    required this.target,
  });

  /// Durée de travail attendue de l'agent (objectif du jour).
  final Duration target;

  final DayState state;
  final String? zoneName;

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.state.day?.status == DayStatus.active && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final day = widget.state.day;
    final now = DateTime.now();
    final worked = day?.worked(now) ?? Duration.zero;

    final (String label, Color color) = switch (day?.status) {
      DayStatus.active => (
        'Journée en cours',
        toneColor(context, Tone.success),
      ),
      DayStatus.paused => ('En pause', toneColor(context, Tone.warning)),
      _ => (
        widget.state.approved == null
            ? 'Journée non démarrée'
            : 'Prêt à démarrer',
        scheme.onSurfaceVariant,
      ),
    };
    final ringColor = day?.status == DayStatus.paused
        ? toneColor(context, Tone.warning)
        : scheme.primary;
    final paused = day == null
        ? Duration.zero
        : Duration(seconds: day.pausedSeconds) +
              (day.currentPauseStartedAt == null
                  ? Duration.zero
                  : now.difference(day.currentPauseStartedAt!));
    final tabular = const [FontFeature.tabularFigures()];

    return SurfaceCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(label: label, color: color),
              const SizedBox(width: Space.md),
              if (widget.zoneName != null)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.place_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          widget.zoneName!,
                          style: text.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Semantics(
                label:
                    'Temps travaillé : ${formatShortDuration(worked)} sur ${formatWorkday(widget.target.inMinutes)}',
                excludeSemantics: true,
                child: ProgressRing(
                  value: worked.inSeconds / widget.target.inSeconds,
                  size: 118,
                  stroke: 12,
                  color: ringColor,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        day == null ? '0 h 00' : formatShortDuration(worked),
                        style: text.headlineSmall?.copyWith(
                          fontSize: 20,
                          fontFeatures: tabular,
                        ),
                      ),
                      Text(
                        'sur ${formatWorkday(widget.target.inMinutes)}',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Space.xl),
              Expanded(
                child: day == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Objectif du jour',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${formatWorkday(widget.target.inMinutes)} de terrain',
                            style: text.titleLarge,
                          ),
                          const SizedBox(height: Space.sm),
                          Text(
                            widget.state.approved == null
                                ? 'Choisissez votre zone pour commencer.'
                                : 'Démarrez en arrivant dans votre zone.',
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Metric(
                            label: 'Début',
                            value: formatTime(day.startedAt),
                          ),
                          const SizedBox(height: Space.md),
                          _Metric(
                            label: 'Pauses',
                            value: formatShortDuration(paused),
                          ),
                          const SizedBox(height: Space.md),
                          _Metric(
                            label: 'Restant',
                            value: formatShortDuration(widget.target - worked),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: text.titleLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Partage de position et envoi des données.
class _LiveRows extends ConsumerWidget {
  const _LiveRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracker = ref.watch(trackerProvider);
    final sync = ref.watch(syncProvider);
    final pending = ref.watch(pendingCountProvider).value ?? 0;

    final (
      String gpsTitle,
      String gpsSub,
      Tone gpsTone,
      IconData gpsIcon,
    ) = !tracker.isTracking
        ? (
            'Position non partagée',
            'En pause',
            Tone.neutral,
            Icons.location_disabled_rounded,
          )
        : tracker.error != null
        ? ('GPS indisponible', 'À vérifier', Tone.danger, Icons.gps_off_rounded)
        : (
            'Position partagée',
            tracker.lastFixAt == null
                ? 'Recherche…'
                : formatAgo(tracker.lastFixAt!),
            Tone.success,
            Icons.near_me_rounded,
          );
    final (
      String syncTitle,
      String syncSub,
      Tone syncTone,
      IconData syncIcon,
    ) = !sync.online
        ? (
            'Hors connexion',
            pending > 0 ? '$pending en attente' : 'Données gardées',
            Tone.warning,
            Icons.cloud_off_rounded,
          )
        : pending > 0
        ? (
            'Envoi en cours',
            '$pending en attente',
            Tone.info,
            Icons.cloud_upload_rounded,
          )
        : (
            'Données envoyées',
            sync.lastSyncAt == null ? 'À jour' : formatAgo(sync.lastSyncAt!),
            Tone.success,
            Icons.cloud_done_rounded,
          );

    return GroupedList(
      header: 'Suivi',
      children: [
        ListRow(
          leading: IconSquircle(
            icon: gpsIcon,
            color: toneColor(context, gpsTone),
            size: 28,
            solid: true,
          ),
          title: gpsTitle,
          value: gpsSub,
        ),
        ListRow(
          leading: IconSquircle(
            icon: syncIcon,
            color: toneColor(context, syncTone),
            size: 28,
            solid: true,
          ),
          title: syncTitle,
          value: syncSub,
        ),
      ],
    );
  }
}

class _ZoneGroup extends ConsumerWidget {
  const _ZoneGroup({
    required this.state,
    required this.zoneName,
    required this.me,
  });

  final DayState state;
  final String? Function(String?) zoneName;
  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pending = state.pending;
    final approved = state.approved;
    final canChange =
        !state.isWorking &&
        approved != null &&
        me.allowZoneChangeBeforeStart &&
        pending == null;

    return GroupedList(
      header: 'Zone du jour',
      footer: pending == null
          ? null
          : pending.isChange && approved != null
          ? 'Vous gardez ${zoneName(approved.zoneId) ?? 'votre zone'} en attendant la réponse de votre responsable.'
          : 'Votre responsable a été prévenu. La décision s’affichera ici.',
      children: [
        ListRow(
          leading: IconSquircle(
            icon: pending != null
                ? Icons.hourglass_top_rounded
                : Icons.place_rounded,
            color: pending != null ? toneColor(context, Tone.warning) : null,
            size: 28,
            solid: true,
          ),
          title: pending != null
              ? (zoneName(pending.zoneId) ?? 'Zone demandée')
              : (zoneName(approved?.zoneId) ?? 'Zone'),
          subtitle: pending != null ? 'En attente de validation' : null,
          value: canChange ? 'Changer' : null,
          onTap: canChange
              ? () => showZonePicker(context, currentZoneId: approved.zoneId)
              : null,
        ),
        if (pending != null)
          ListRow(
            title: 'Annuler la demande',
            titleColor: scheme.primary,
            centered: true,
            onTap: () async {
              try {
                await ref.read(dayProvider.notifier).cancelPending(pending.id);
              } on ApiException catch (e) {
                if (context.mounted) {
                  showMessage(context, e.message, error: true);
                }
              }
            },
          ),
      ],
    );
  }
}

/// Message de la structure, présenté comme une notification.
class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.branding});

  final Branding branding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BrandLogo(branding: branding, size: 22),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  branding.displayName,
                  style: text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Message',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(branding.welcomeMessage!, style: text.bodyLarge),
        ],
      ),
    );
  }
}

/// Barre d'action : la prochaine étape de la journée.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.state,
    required this.busy,
    required this.zoneRequired,
    required this.onChooseZone,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
  });

  final DayState state;
  final bool busy;
  final bool zoneRequired;
  final VoidCallback onChooseZone;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final day = state.day;

    final Widget actions;
    if (day != null && day.status == DayStatus.active) {
      actions = Row(
        children: [
          Expanded(
            child: PillButton(
              label: 'Pause',
              icon: Icons.pause_rounded,
              style: PillStyle.outline,
              onPressed: busy ? null : onPause,
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: PillButton(
              label: 'Terminer',
              icon: Icons.stop_rounded,
              loading: busy,
              onPressed: onEnd,
            ),
          ),
        ],
      );
    } else if (day != null && day.status == DayStatus.paused) {
      actions = Row(
        children: [
          Expanded(
            child: PillButton(
              label: 'Reprendre',
              icon: Icons.play_arrow_rounded,
              loading: busy,
              onPressed: onResume,
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: PillButton(
              label: 'Terminer',
              style: PillStyle.outline,
              onPressed: busy ? null : onEnd,
            ),
          ),
        ],
      );
    } else if (state.pending != null && state.approved == null) {
      actions = const PillButton(
        label: 'Validation en attente',
        icon: Icons.hourglass_top_rounded,
        onPressed: null,
      );
    } else if (state.approved == null && zoneRequired) {
      actions = PillButton(
        label: 'Choisir ma zone',
        icon: Icons.place_rounded,
        loading: busy,
        onPressed: onChooseZone,
      );
    } else {
      actions = PillButton(
        label: 'Démarrer ma journée',
        icon: Icons.play_arrow_rounded,
        loading: busy,
        onPressed: onStart,
      );
    }

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.md,
          ),
          child: actions,
        ),
      ),
    );
  }
}
