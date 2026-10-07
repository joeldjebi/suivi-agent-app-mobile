import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';

/// « Ma semaine » d'une date donnée (null : la semaine en cours).
final weekProvider = FutureProvider.autoDispose.family<WeekSummary, String?>(
  (ref, date) => ref.read(repositoryProvider).week(date),
);

String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// « 12 h 30 », « 45 min », « 0 h ».
String _hours(Duration d) {
  if (d.inMinutes == 0) return '0 h';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// Accès depuis « Ma journée » : temps de la semaine en cours.
class WeekShortcut extends ConsumerWidget {
  const WeekShortcut({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(weekProvider(null)).value;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final share = week == null || week.objectiveTotal == Duration.zero
        ? 0.0
        : week.totals.worked.inSeconds / week.objectiveTotal.inSeconds;
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: SurfaceCard(
        semanticLabel: 'Ma semaine',
        onTap: () => context.push('/day/week'),
        child: Row(
          children: [
            const IconSquircle(icon: Icons.bar_chart_rounded, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ma semaine', style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    week == null
                        ? 'Heures, objectif et formulaires'
                        : '${_hours(week.totals.worked)} · ${week.totals.daysWorked} jour${week.totals.daysWorked > 1 ? 's' : ''} · ${week.totals.forms} formulaire${week.totals.forms > 1 ? 's' : ''}',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (week != null && week.totals.daysWorked > 0) ...[
                    const SizedBox(height: 8),
                    ThinProgress(value: share),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// « Ma semaine » : temps travaillé par jour face à l'objectif, totaux, comparaison avec
/// la semaine précédente et missions où l'agent a contribué.
class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key});

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  /// Un jour de la semaine affichée ; null : la semaine en cours.
  String? _date;

  void _shift(WeekSummary week, int weeks) {
    final target = week.from.add(Duration(days: 7 * weeks));
    setState(() => _date = week.isCurrent && weeks > 0 ? null : _day(target));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(weekProvider(_date));
    return Scaffold(
      appBar: AppBar(title: const Text('Ma semaine')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(weekProvider(_date).future),
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              InfoBanner(
                icon: Icons.wifi_off_rounded,
                message: ApiException.from(e).message,
              ),
            ],
          ),
          data: (week) => _WeekView(
            week: week,
            onPrevious: () => _shift(week, -1),
            onNext: week.isCurrent ? null : () => _shift(week, 1),
          ),
        ),
      ),
    );
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView({
    required this.week,
    required this.onPrevious,
    required this.onNext,
  });

  final WeekSummary week;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final t = week.totals;
    final diff = t.worked - week.previous.worked;
    final share = week.objectiveTotal == Duration.zero
        ? 0.0
        : t.worked.inSeconds / week.objectiveTotal.inSeconds;
    final range =
        '${DateFormat('d MMM', 'fr_FR').format(week.from)} – ${DateFormat('d MMM', 'fr_FR').format(week.to)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.page, 4, Space.page, 40),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              tooltip: 'Semaine précédente',
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    week.isCurrent ? 'Cette semaine' : range,
                    style: text.titleMedium,
                  ),
                  if (week.isCurrent)
                    Text(
                      range,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: onNext,
              tooltip: 'Semaine suivante',
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TEMPS TRAVAILLÉ',
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _hours(t.worked),
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.daysWorked == 0
                          ? 'aucune journée'
                          : 'sur ${_hours(week.objectiveTotal)} visées',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (t.daysWorked > 0) ...[
                const SizedBox(height: 10),
                ThinProgress(value: share, height: 8),
                const SizedBox(height: 6),
                Text(
                  '${(share * 100).round()} % de l’objectif de vos ${t.daysWorked} jour${t.daysWorked > 1 ? 's' : ''} travaillé${t.daysWorked > 1 ? 's' : ''} (${_hours(week.objective)} par jour)',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (week.previous.worked > Duration.zero ||
                  t.worked > Duration.zero) ...[
                const SizedBox(height: 10),
                _Trend(diff: diff),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        SurfaceCard(child: _WeekChart(week: week)),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Jours',
                value: '${t.daysWorked}',
                hint: 'travaillés',
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _Stat(
                label: 'Formulaires',
                value: '${t.forms}',
                hint: t.rejected > 0
                    ? '${t.rejected} rejeté${t.rejected > 1 ? 's' : ''}'
                    : 'envoyés',
                alert: t.rejected > 0,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _Stat(
                label: 'Moyenne',
                value: t.daysWorked == 0
                    ? '—'
                    : _hours(
                        Duration(seconds: t.worked.inSeconds ~/ t.daysWorked),
                      ),
                hint: 'par jour',
              ),
            ),
          ],
        ),
        if (week.missions.isNotEmpty)
          GroupedList(
            header: 'Mes missions de la semaine',
            children: [
              for (final m in week.missions)
                ListRow(
                  leading: const IconSquircle(
                    icon: Icons.flag_rounded,
                    size: 28,
                  ),
                  title: m.title,
                  value: '${m.forms} formulaire${m.forms > 1 ? 's' : ''}',
                  onTap: () => context.push('/missions/${m.id}'),
                ),
            ],
          ),
        if (week.days.any((d) => d.worked > Duration.zero))
          GroupedList(
            header: 'Jour par jour',
            children: [
              for (final d in week.days.where((d) => d.worked > Duration.zero))
                ListRow(
                  title: toBeginningOfSentenceCase(
                    DateFormat('EEEE d MMMM', 'fr_FR').format(d.date),
                  ),
                  subtitle: [
                    if (d.zones.isNotEmpty) d.zones.join(', '),
                    '${d.forms} formulaire${d.forms > 1 ? 's' : ''}${d.rejected > 0 ? ' · ${d.rejected} rejeté${d.rejected > 1 ? 's' : ''}' : ''}',
                  ].join(' · '),
                  value: _hours(d.worked),
                ),
            ],
          ),
      ],
    );
  }
}

/// Écart avec la semaine précédente.
class _Trend extends StatelessWidget {
  const _Trend({required this.diff});

  final Duration diff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final up = diff >= Duration.zero;
    final color = diff.inMinutes.abs() < 1
        ? scheme.onSurfaceVariant
        : up
        ? toneColor(context, Tone.success)
        : toneColor(context, Tone.warning);
    return Row(
      children: [
        Icon(
          diff.inMinutes.abs() < 1
              ? Icons.trending_flat_rounded
              : up
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            diff.inMinutes.abs() < 1
                ? 'Autant que la semaine précédente'
                : '${up ? '+' : '−'}${_hours(diff.abs())} par rapport à la semaine précédente',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Barres des heures par jour, avec la ligne de l'objectif.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.week});

  final WeekSummary week;

  static const _height = 140.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final objective = week.objective.inSeconds.toDouble();
    final top = [
      objective * 1.15,
      ...week.days.map((d) => d.worked.inSeconds.toDouble()),
    ].reduce((a, b) => a > b ? a : b);
    final objectiveY = _height * objective / top;
    final today = _day(week.today);

    return Semantics(
      label:
          'Heures par jour : ${week.days.map((d) => '${DateFormat('EEEE', 'fr_FR').format(d.date)} ${_hours(d.worked)}').join(', ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Heures par jour', style: text.titleSmall),
                ),
                Container(
                  width: 14,
                  height: 2,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  'Objectif ${_hours(week.objective)}',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: _height + 26,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: objectiveY,
                    child: Container(
                      height: 1.5,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in week.days)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (d.worked > Duration.zero)
                                  Text(
                                    d.worked.inMinutes >= 60
                                        ? '${d.worked.inHours}h${(d.worked.inMinutes % 60).toString().padLeft(2, '0')}'
                                        : '${d.worked.inMinutes}m',
                                    style: text.labelSmall?.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Container(
                                  height: d.worked == Duration.zero
                                      ? 4
                                      : (_height * d.worked.inSeconds / top)
                                            .clamp(6, _height),
                                  decoration: BoxDecoration(
                                    color: d.worked == Duration.zero
                                        ? scheme.outlineVariant.withValues(
                                            alpha: d.future ? 0.3 : 0.6,
                                          )
                                        : d.worked.inSeconds >= objective
                                        ? toneColor(context, Tone.success)
                                        : scheme.primary,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6),
                                      bottom: Radius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final d in week.days)
                  Expanded(
                    child: Text(
                      DateFormat('EEEEE', 'fr_FR').format(d.date).toUpperCase(),
                      textAlign: TextAlign.center,
                      style: text.labelMedium?.copyWith(
                        color: _day(d.date) == today
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: _day(d.date) == today
                            ? FontWeight.w700
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.hint,
    this.alert = false,
  });

  final String label;
  final String value;
  final String hint;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            hint,
            style: text.bodySmall?.copyWith(
              color: alert
                  ? toneColor(context, Tone.warning)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
