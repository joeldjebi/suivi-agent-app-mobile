import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import 'alerts_screen.dart' show alertLabelOf;
import 'team_controller.dart';

/// Bilan d'un jour (clé AAAA-MM-JJ).
final dailyReportProvider = FutureProvider.autoDispose
    .family<DailyReport, DateTime>(
      (ref, day) => ref.read(repositoryProvider).dailyReport(date: day),
    );

String _hours(int minutes) {
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return '${minutes ~/ 60} h${m == 0 ? '' : ' ${m.toString().padLeft(2, '0')}'}';
}

String _digits(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

void _call(String phone) => launchUrl(Uri(scheme: 'tel', path: _digits(phone)));

/// WhatsApp : numéro au format international, sans « + ».
void _whatsApp(String phone) => launchUrl(
  Uri.parse('https://wa.me/${_digits(phone).replaceAll('+', '')}'),
  mode: LaunchMode.externalApplication,
);

/// Bilan du jour du chef : résumé de l'équipe, une ligne par agent, actions rapides.
class DailyReportScreen extends ConsumerStatefulWidget {
  const DailyReportScreen({super.key});

  @override
  ConsumerState<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends ConsumerState<DailyReportScreen> {
  late DateTime _day = _today();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isToday => _day == _today();

  void _shift(int days) =>
      setState(() => _day = _day.add(Duration(days: days)));

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(dailyReportProvider(_day));
    final text = Theme.of(context).textTheme;
    final label = _isToday
        ? 'Aujourd’hui'
        : DateFormat('EEEE d MMMM', 'fr_FR').format(_day);

    return Scaffold(
      appBar: AppBar(title: const Text('Bilan du jour')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dailyReportProvider(_day)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            0,
            Space.page,
            Space.xxxl,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Jour précédent',
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    label[0].toUpperCase() + label.substring(1),
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Jour suivant',
                  onPressed: _isToday ? null : () => _shift(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            ...report.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.only(top: Space.xxxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => [
                InfoBanner(
                  icon: Icons.wifi_off_rounded,
                  message: ApiException.from(e).message,
                  action: TextButton(
                    onPressed: () => ref.invalidate(dailyReportProvider(_day)),
                    child: const Text('Réessayer'),
                  ),
                ),
              ],
              data: (r) => [
                _Summary(report: r, today: _isToday),
                if (r.rows.any((x) => !x.started)) ...[
                  SectionHeader(_isToday ? 'Pas encore démarré' : 'Absents'),
                  GroupedList(
                    children: [
                      for (final row in r.rows.where((x) => !x.started))
                        _AgentRow(row: row),
                    ],
                  ),
                ],
                if (r.rows.any((x) => x.started)) ...[
                  const SectionHeader('Journées'),
                  GroupedList(
                    children: [
                      for (final row in r.rows.where((x) => x.started))
                        _AgentRow(row: row),
                    ],
                  ),
                ],
                if (r.rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: Space.xxxl),
                    child: Text(
                      'Aucun agent dans votre équipe.',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.sm,
          ),
          child: PillButton(
            label: 'Message à l’équipe',
            icon: Icons.campaign_outlined,
            onPressed: () => showTeamMessageSheet(context),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.report, required this.today});

  final DailyReport report;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget tile(String value, String label, {Tone? tone}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: text.titleLarge?.copyWith(
              color: tone == null ? null : toneColor(context, tone),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${r.worked}',
                style: text.displaySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(' / ${r.agents}', style: text.titleLarge),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  today
                      ? 'agents en journée ou partis'
                      : 'agents ont travaillé',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          ThinProgress(value: r.agents == 0 ? 0 : r.worked / r.agents),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              tile(_hours(r.workedMinutes), 'Temps travaillé'),
              tile(
                '${r.formsAccepted}',
                r.formsRejected > 0
                    ? 'Formulaires · ${r.formsRejected} rejeté${r.formsRejected > 1 ? 's' : ''}'
                    : 'Formulaires',
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              tile(
                '${r.alerts}',
                'Alertes',
                tone: r.alerts > 0 ? Tone.danger : null,
              ),
              tile(
                '${r.zoneExits}',
                'Sorties de zone',
                tone: r.zoneExits > 0 ? Tone.warning : null,
              ),
            ],
          ),
          if (r.late > 0 || r.autoClosed > 0) ...[
            const SizedBox(height: Space.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (r.late > 0)
                  StatusPill(
                    label: '${r.late} en retard',
                    color: toneColor(context, Tone.warning),
                  ),
                if (r.autoClosed > 0)
                  StatusPill(
                    label:
                        '${r.autoClosed} journée${r.autoClosed > 1 ? 's' : ''} non clôturée${r.autoClosed > 1 ? 's' : ''}',
                    color: toneColor(context, Tone.warning),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.row});

  final DailyReportRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hm = DateFormat.Hm('fr_FR');
    final color = switch (r.status) {
      'working' => toneColor(context, Tone.success),
      'not_started' => scheme.outline,
      'auto' => toneColor(context, Tone.warning),
      _ => scheme.onSurfaceVariant,
    };
    final subtitle = !r.started
        ? 'Pas de journée'
        : [
            '${hm.format(r.startedAt!)} → ${r.endedAt == null ? (r.status == 'working' ? 'en cours' : '—') : hm.format(r.endedAt!)}',
            if (r.zone != null) r.zone!,
          ].join(' · ');
    final chips = <(String, Tone)>[
      if (r.formsAccepted > 0)
        (
          '${r.formsAccepted} formulaire${r.formsAccepted > 1 ? 's' : ''}',
          Tone.info,
        ),
      if (r.late) ('En retard', Tone.warning),
      if (r.status == 'auto') ('Non clôturée', Tone.warning),
      if (r.zoneExits > 0)
        (
          '${r.zoneExits} sortie${r.zoneExits > 1 ? 's' : ''} de zone',
          Tone.warning,
        ),
      for (final a in r.alerts.where((a) => a != 'late_start'))
        (alertLabelOf(a), Tone.danger),
    ];
    final initials = r.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.xs,
        Space.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusAvatar(initials: initials, ringColor: color, size: 38),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(r.name, style: text.titleSmall)),
                    if (r.started)
                      Text(
                        r.targetMinutes == null
                            ? _hours(r.workedMinutes)
                            : '${_hours(r.workedMinutes)} · ${(r.workedMinutes * 100 / r.targetMinutes!).round()} %',
                        style: text.titleSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (label, tone) in chips)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: toneColor(
                              context,
                              tone,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text(
                            label,
                            style: text.labelSmall?.copyWith(
                              color: toneColor(context, tone),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (r.phone != null) ...[
            IconButton(
              tooltip: 'Appeler ${r.name}',
              onPressed: () => _call(r.phone!),
              icon: Icon(Icons.call_outlined, color: scheme.primary),
            ),
            IconButton(
              tooltip: 'WhatsApp ${r.name}',
              onPressed: () => _whatsApp(r.phone!),
              icon: const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Message à l'équipe : toute l'équipe ou des agents choisis.
Future<void> showTeamMessageSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => const _TeamMessageSheet(),
    );

class _TeamMessageSheet extends ConsumerStatefulWidget {
  const _TeamMessageSheet();

  @override
  ConsumerState<_TeamMessageSheet> createState() => _TeamMessageSheetState();
}

class _TeamMessageSheetState extends ConsumerState<_TeamMessageSheet> {
  final _body = TextEditingController();
  var _everyone = true;
  final _chosen = <String>{};
  var _sending = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final n = await ref
          .read(repositoryProvider)
          .sendTeamMessage(
            _body.text.trim(),
            agentIds: _everyone ? null : _chosen.toList(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'Message envoyé à $n agent${n > 1 ? 's' : ''}');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        showMessage(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final members = [...?ref.watch(teamProvider).value?.members.values]
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final ready =
        _body.text.trim().length >= 2 && (_everyone || _chosen.isNotEmpty);

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
          Text('Message à l’équipe', style: text.headlineSmall),
          const SizedBox(height: Space.xs),
          Text(
            'Chaque agent le reçoit en notification dans l’application.',
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _body,
            maxLength: 500,
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Message',
              hintText: 'Ex. Réunion à 17 h au bureau du Plateau.',
            ),
          ),
          const SizedBox(height: Space.sm),
          AppSegmented<bool>(
            selected: _everyone,
            segments: {
              true: 'Toute l’équipe (${members.length})',
              false: 'Choisir',
            },
            onChanged: (v) => setState(() => _everyone = v),
          ),
          if (!_everyone) ...[
            const SizedBox(height: Space.sm),
            GroupedList(
              children: [
                for (final m in members)
                  CheckboxListTile(
                    value: _chosen.contains(m.id),
                    title: Text(m.fullName),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (on) => setState(
                      () =>
                          on == true ? _chosen.add(m.id) : _chosen.remove(m.id),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.lg),
          PillButton(
            label: 'Envoyer',
            icon: Icons.send_rounded,
            loading: _sending,
            onPressed: ready && !_sending ? _send : null,
          ),
        ],
      ),
    );
  }
}
