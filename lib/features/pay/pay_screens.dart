import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/user_avatar.dart';

/// Mes gains : estimation de la période en cours et paies validées.
final myPayProvider = FutureProvider.autoDispose<MyPay>(
  (ref) => ref.read(repositoryProvider).myPay(),
);

/// Chef d'équipe : paie de la période écoulée encore en brouillon (ajustements possibles).
final draftRunProvider = FutureProvider.autoDispose<PayRunDetail?>((ref) async {
  final repo = ref.read(repositoryProvider);
  final draft = (await repo.payRuns()).where((r) => r.isDraft).firstOrNull;
  return draft == null ? null : repo.payRun(draft.id);
});

/// Chef d'équipe : estimation de la période en cours pour son équipe.
final teamPayProvider = FutureProvider.autoDispose<CurrentPay>(
  (ref) => ref.read(repositoryProvider).teamPay(),
);

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Écran à grand titre, rechargeable, avec les états de chargement et d'erreur.
class _PayScaffold<T> extends StatelessWidget {
  const _PayScaffold({
    required this.title,
    required this.value,
    required this.onRefresh,
    required this.builder,
  });

  final String title;
  final AsyncValue<T> value;
  final Future<void> Function() onRefresh;
  final List<Widget> Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: value.when(
          skipLoadingOnRefresh: true,
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
          data: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.page,
              Space.sm,
              Space.page,
              Space.xxxl,
            ),
            children: builder(data),
          ),
        ),
      ),
    );
  }
}

/// Grand montant de la période, avec l'avancement de la période.
class _HeroAmount extends StatelessWidget {
  const _HeroAmount({
    required this.caption,
    required this.amount,
    required this.currency,
    required this.period,
    this.note,
  });

  final String caption;
  final int amount;
  final String currency;
  final PayPeriod period;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final progress = period.progress(now);
    final day = (progress * period.days).round().clamp(1, period.days);
    return SurfaceCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption.toUpperCase(),
            style: text.labelSmall?.semibold.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: Space.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(amount, currency),
              style: text.displaySmall?.semibold.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(
              note!,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: Space.lg),
          ThinProgress(value: progress, height: 5),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Jour $day sur ${period.days}',
                  style: text.bodySmall?.medium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(
                formatRange(period.start, period.end),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ligne d'un élément de gains : libellé, calcul (« 9 × 2 500 FCFA ») et montant.
class _ItemRow extends StatelessWidget {
  const _ItemRow(this.item, {required this.currency});

  final PayItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final unit = item.unitAmount;
    return ListRow(
      title: item.label,
      subtitle: item.quantity != null && unit != null
          ? '${formatNumber(item.quantity!)} × ${formatMoney(unit.abs(), currency)}'
          : null,
      trailing: Text(
        '${item.amount > 0 ? '+' : ''}${formatMoney(item.amount, currency)}',
        style: text.bodyMedium?.medium.copyWith(
          color: item.isDeduction ? scheme.error : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Ligne de total : libellé et montant en gras.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    required this.currency,
  });

  final String label;
  final int amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListRow(
      title: label,
      trailing: Text(
        formatMoney(amount, currency),
        style: text.bodyLarge?.semibold.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Détail des éléments, ou une note quand rien n'est encore acquis.
List<Widget> _itemsSection({
  required String header,
  required List<PayItem> items,
  required int total,
  required String currency,
  required String totalLabel,
  String? footer,
}) => [
  GroupedList(
    header: header,
    footer: footer,
    indent: Space.lg,
    children: [
      for (final item in items) _ItemRow(item, currency: currency),
      if (items.isEmpty)
        const ListRow(title: 'Aucun gain pour l’instant', chevron: false),
      _TotalRow(label: totalLabel, amount: total, currency: currency),
    ],
  ),
];

// ---------------------------------------------------------------------------

/// Agent ou chef : ses gains estimés en direct et ses paies validées.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pay = ref.watch(myPayProvider);
    final scheme = Theme.of(context).colorScheme;
    return _PayScaffold<MyPay>(
      title: 'Mes gains',
      value: pay,
      onRefresh: () => ref.refresh(myPayProvider.future),
      builder: (data) {
        final current = data.current;
        final estimate = data.estimate;
        final noGrid = estimate == null || estimate.gridName == null;
        return [
          _HeroAmount(
            caption: 'Estimation · ${current.period.label}',
            amount: estimate?.gross ?? 0,
            currency: current.currency,
            period: current.period,
            note: 'Calculée en direct à partir de votre activité',
          ),
          if (noGrid) ...[
            const SizedBox(height: Space.lg),
            const InfoBanner(
              icon: Icons.info_outline_rounded,
              message:
                  'Aucune grille de rémunération ne vous est encore attribuée. Rapprochez-vous de votre responsable.',
              tone: Tone.info,
            ),
          ] else
            ..._itemsSection(
              header: 'Détail de la période',
              items: estimate.items,
              total: estimate.gross,
              currency: current.currency,
              totalLabel: 'Total estimé',
              footer:
                  'Le montant définitif est fixé quand votre structure valide la paie, ajustements compris.',
            ),
          GroupedList(
            header: 'Paies validées',
            footer:
                'Votre structure vous paie en dehors de l’application (Mobile Money, banque).',
            children: [
              if (data.history.isEmpty)
                const ListRow(
                  title: 'Aucune paie validée pour l’instant',
                  chevron: false,
                ),
              for (final receipt in data.history)
                ListRow(
                  leading: IconSquircle(
                    icon: receipt.isPaid
                        ? Icons.check_rounded
                        : Icons.schedule_rounded,
                    color: receipt.isPaid
                        ? const Color(0xFF34A853)
                        : const Color(0xFFF59E0B),
                    size: 28,
                    solid: true,
                  ),
                  title: _capitalize(receipt.period.label),
                  subtitle: receipt.isPaid
                      ? 'Payée le ${formatShortDate(receipt.paidAt!)}'
                      : 'Validée, en attente de paiement',
                  trailing: Text(
                    formatMoney(receipt.total, current.currency),
                    style: Theme.of(context).textTheme.bodyMedium?.medium
                        .copyWith(
                          color: scheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                  onTap: () =>
                      showReceipt(context, receipt, currency: current.currency),
                ),
            ],
          ),
        ];
      },
    );
  }
}

/// Reçu d'une paie validée : détail, ajustements, net et paiement.
Future<void> showReceipt(
  BuildContext context,
  PayReceipt receipt, {
  required String currency,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  builder: (context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          0,
          Space.page,
          Space.xxl,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Paie de ${receipt.period.label}',
                  style: text.headlineSmall,
                ),
              ),
              StatusPill(
                label: receipt.isPaid ? 'Payée' : 'À payer',
                color: toneColor(
                  context,
                  receipt.isPaid ? Tone.success : Tone.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            formatRange(receipt.period.start, receipt.period.end),
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          ..._itemsSection(
            header: 'Gains calculés',
            items: receipt.items,
            total: receipt.gross,
            currency: currency,
            totalLabel: 'Sous-total',
          ),
          if (receipt.adjustmentDetails.isNotEmpty)
            GroupedList(
              header: 'Ajustements',
              indent: Space.lg,
              children: [
                for (final a in receipt.adjustmentDetails)
                  _ItemRow(a, currency: currency),
              ],
            ),
          GroupedList(
            header: 'Paiement',
            indent: Space.lg,
            children: [
              _TotalRow(
                label: 'Net à payer',
                amount: receipt.total,
                currency: currency,
              ),
              ListRow(
                title: 'Statut',
                value: receipt.isPaid
                    ? 'Payée le ${formatShortDate(receipt.paidAt!)}'
                    : 'En attente',
              ),
              if (receipt.paymentReference != null)
                ListRow(title: 'Référence', value: receipt.paymentReference),
            ],
          ),
        ],
      ),
    );
  },
);

// ---------------------------------------------------------------------------

/// Chef d'équipe : gains estimés de ses agents sur la période en cours.
class TeamEarningsScreen extends ConsumerWidget {
  const TeamEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pay = ref.watch(teamPayProvider);
    final me = ref.watch(meProvider);
    return _PayScaffold<CurrentPay>(
      title: 'Gains de l’équipe',
      value: pay,
      onRefresh: () => ref.refresh(teamPayProvider.future),
      builder: (data) {
        final agents = data.lines.where((l) => l.userId != me.id).toList()
          ..sort((a, b) => b.gross.compareTo(a.gross));
        final total = agents.fold<int>(0, (s, l) => s + l.gross);
        final withoutGrid = agents.where((l) => l.gridName == null).length;
        return [
          _HeroAmount(
            caption: 'Équipe · ${data.period.label}',
            amount: total,
            currency: data.currency,
            period: data.period,
            note:
                '${agents.length} agent${agents.length > 1 ? 's' : ''} · estimation en direct',
          ),
          if (withoutGrid > 0) ...[
            const SizedBox(height: Space.lg),
            InfoBanner(
              icon: Icons.info_outline_rounded,
              message:
                  '$withoutGrid agent${withoutGrid > 1 ? 's n’ont' : ' n’a'} pas de grille de rémunération : signalez-le à l’administrateur.',
              tone: Tone.warning,
            ),
          ],
          GroupedList(
            header: 'Agents',
            footer: 'Estimation de la période en cours, mise à jour en direct.',
            children: [
              if (agents.isEmpty)
                const ListRow(title: 'Aucun agent dans votre équipe'),
              for (final line in agents)
                ListRow(
                  leading: UserAvatar(
                    userId: line.userId,
                    version: null,
                    initials: line.initials,
                    size: 32,
                  ),
                  title: line.fullName,
                  subtitle: line.gridName ?? 'Sans grille',
                  trailing: Text(
                    formatMoney(line.gross, data.currency),
                    style: Theme.of(context).textTheme.bodyMedium?.medium
                        .copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                  onTap: () => _showEstimate(context, line, data),
                ),
            ],
          ),
          _DraftRunSection(meId: me.id),
        ];
      },
    );
  }
}

/// Détail de l'estimation d'un agent de l'équipe.
Future<void> _showEstimate(
  BuildContext context,
  PayEstimate line,
  CurrentPay pay,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  builder: (context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(line.fullName, style: text.headlineSmall),
          const SizedBox(height: 2),
          Text(
            '${line.gridName ?? 'Sans grille'} · ${pay.period.label}',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          ..._itemsSection(
            header: 'Détail estimé',
            items: line.items,
            total: line.gross,
            currency: pay.currency,
            totalLabel: 'Total estimé',
          ),
        ],
      ),
    );
  },
);

/// Paie de la période écoulée, en brouillon : le chef propose primes et retenues pour son équipe,
/// l'administrateur décide avant de valider la paie.
class _DraftRunSection extends ConsumerWidget {
  const _DraftRunSection({required this.meId});

  final String meId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(draftRunProvider).value;
    if (run == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final lines = run.lines.where((l) => l.userId != meId).toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    return GroupedList(
      header: 'Paie de ${run.label} · à valider',
      footer:
          'Proposez une prime ou une retenue avant la validation : l’administrateur décide, l’agent est prévenu.',
      children: [
        for (final line in lines)
          Builder(
            builder: (context) {
              final mine = run.adjustments.where(
                (a) => a.userId == line.userId,
              );
              final pending = mine.where((a) => a.status == 'proposed').length;
              return ListRow(
                leading: IconSquircle(
                  icon: Icons.tune_rounded,
                  color: pending > 0
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF6B7280),
                  size: 28,
                  solid: true,
                ),
                title: line.name,
                subtitle: [
                  formatMoney(line.total, run.currency),
                  if (pending > 0)
                    '$pending proposition${pending > 1 ? 's' : ''} en attente',
                  if (mine.any((a) => a.status == 'approved')) 'ajusté',
                ].join(' · '),
                trailing: Text(
                  'Proposer',
                  style: text.bodyMedium?.medium.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () => _proposeAdjustment(
                  context,
                  ref,
                  run,
                  line.userId,
                  line.name,
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Feuille de proposition : prime ou retenue, montant, motif (vu par l'agent).
Future<void> _proposeAdjustment(
  BuildContext context,
  WidgetRef ref,
  PayRunDetail run,
  String userId,
  String name,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  builder: (context) => _AdjustmentSheet(run: run, userId: userId, name: name),
);

class _AdjustmentSheet extends ConsumerStatefulWidget {
  const _AdjustmentSheet({
    required this.run,
    required this.userId,
    required this.name,
  });

  final PayRunDetail run;
  final String userId;
  final String name;

  @override
  ConsumerState<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends ConsumerState<_AdjustmentSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _bonus = true;
  bool _sending = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  int get _value =>
      int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(repositoryProvider)
          .proposeAdjustment(
            widget.run.id,
            userId: widget.userId,
            amount: _bonus ? _value : -_value,
            reason: _reason.text.trim(),
          );
      ref.invalidate(draftRunProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'Proposition envoyée à l’administrateur');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final history = widget.run.adjustments
        .where((a) => a.userId == widget.userId)
        .toList();
    final ready = _value > 0 && _reason.text.trim().length >= 3;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.page,
        0,
        Space.page,
        MediaQuery.viewInsetsOf(context).bottom + Space.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.name, style: text.headlineSmall),
          Text(
            'Paie de ${widget.run.label}',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.lg),
          AppSegmented<bool>(
            segments: const {true: 'Prime', false: 'Retenue'},
            selected: _bonus,
            onChanged: (v) => setState(() => _bonus = v),
          ),
          const SizedBox(height: Space.md),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.xs,
            ),
            child: Column(
              children: [
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Montant',
                    suffixText: widget.run.currency == 'XOF'
                        ? 'FCFA'
                        : widget.run.currency,
                    border: InputBorder.none,
                    filled: false,
                  ),
                ),
                const Divider(height: 1),
                TextField(
                  controller: _reason,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 300,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Motif (vu par l’agent)',
                    hintText: 'Ex. Meilleur résultat de l’équipe',
                    border: InputBorder.none,
                    filled: false,
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          PillButton(
            label: _bonus ? 'Proposer la prime' : 'Proposer la retenue',
            loading: _sending,
            onPressed: ready && !_sending ? _send : null,
          ),
          if (history.isNotEmpty) ...[
            GroupedList(
              header: 'Déjà proposé',
              indent: Space.lg,
              children: [
                for (final a in history)
                  ListRow(
                    title: a.reason,
                    subtitle: switch (a.status) {
                      'approved' => 'Approuvé',
                      'rejected' => 'Refusé',
                      _ => 'En attente de l’administrateur',
                    },
                    trailing: Text(
                      formatMoney(a.amount, widget.run.currency),
                      style: text.bodyMedium?.medium.copyWith(
                        color: a.amount < 0 ? scheme.error : null,
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
