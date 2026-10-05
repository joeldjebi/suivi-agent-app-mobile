import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import 'team_controller.dart';

/// Chef d'équipe : demandes de zone à valider (RG-07, RG-19).
class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(requestsProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final count = requests.value?.length ?? 0;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(requestsProvider.notifier).refresh(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.page,
            MediaQuery.paddingOf(context).top + Space.lg,
            Space.page,
            Space.xxl,
          ),
          children: [
            Text('Demandes', style: text.headlineMedium),
            const SizedBox(height: 2),
            Text(
              count == 0
                  ? 'Aucune demande en attente'
                  : '$count choix de zone à valider',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.lg),
            ...requests.when(
              loading: () => [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(Space.xxxl),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ],
              error: (e, _) => [
                InfoBanner(
                  icon: Icons.wifi_off_rounded,
                  message: ApiException.from(e).message,
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xxxl),
                        child: Text(
                          'Tout est à jour.\nLes demandes de vos agents apparaîtront ici.',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ]
                  : [
                      for (final r in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: _RequestCard(request: r),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.request});

  final PendingRequest request;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    String? reason;
    if (!approve) {
      reason = await _askReason(context, widget.request.agentName);
      if (reason == null) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(requestsProvider.notifier)
          .decide(widget.request.id, approve: approve, reason: reason);
      if (mounted) {
        showMessage(
          context,
          approve
              ? 'Zone ${widget.request.zoneName} validée pour ${widget.request.agentName}'
              : 'Demande refusée',
        );
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
      unawaited(ref.read(requestsProvider.notifier).refresh());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final remaining = r.expiresAt?.difference(DateTime.now());
    final urgent = remaining != null && remaining.inMinutes < 5;
    final initials = r.agentName
        .split(' ')
        .map((p) => p.isEmpty ? '' : p[0])
        .take(2)
        .join()
        .toUpperCase();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusAvatar(
                initials: initials,
                ringColor: toneColor(context, Tone.warning),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.agentName,
                      style: text.titleSmall?.copyWith(fontSize: 15),
                    ),
                    Text(
                      '${r.isChange ? 'Changement vers' : 'Zone'} ${r.zoneName} · ${formatAgo(r.createdAt)}',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (remaining != null)
                Text(
                  remaining.isNegative
                      ? 'Expire'
                      : 'Expire dans ${remaining.inMinutes + 1} min',
                  style: text.labelMedium?.copyWith(
                    color: urgent
                        ? scheme.error
                        : toneColor(context, Tone.warning),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'Refuser',
                  style: PillStyle.outline,
                  height: 42,
                  onPressed: _busy ? null : () => _decide(false),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: PillButton(
                  label: 'Valider',
                  height: 42,
                  loading: _busy,
                  onPressed: () => _decide(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Motif du refus (facultatif) : l'agent le voit dans sa notification.
Future<String?> _askReason(BuildContext context, String agentName) =>
    showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _ReasonSheet(agentName: agentName),
    );

/// Le champ appartient à la feuille : il vit jusqu'à la fin de l'animation de fermeture.
class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({required this.agentName});

  final String agentName;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Refuser la demande',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${widget.agentName} sera prévenu et choisira une autre zone.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _reason,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Motif (facultatif)'),
          ),
          const SizedBox(height: Space.sm),
          PillButton(
            label: 'Refuser',
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
