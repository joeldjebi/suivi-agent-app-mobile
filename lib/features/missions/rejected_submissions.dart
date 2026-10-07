import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database.dart';
import '../../core/format.dart';
import '../../core/sync.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import 'missions_controller.dart';

/// Ce que l'agent peut faire, selon le motif du refus.
String rejectionHint(String? code) => switch (code) {
  'DAY_REQUIRED' =>
    'Démarrez votre journée dans la zone de la mission, puis renvoyez-le.',
  'WRONG_ZONE' =>
    'Renvoyez-le pendant une journée dans une zone de la mission.',
  'INVALID_FORM' => 'Corrigez les champs signalés puis renvoyez-le.',
  'MISSION_CLOSED' =>
    'La mission est close : il ne peut plus être envoyé. Supprimez-le.',
  'NOT_FOUND' => 'La mission n’est plus disponible pour vous. Supprimez-le.',
  _ => 'Corrigez-le puis renvoyez-le, ou supprimez-le.',
};

/// Bandeau des formulaires refusés (écran Journée et Missions) : rien ne doit passer inaperçu.
class RejectedSubmissionsBanner extends ConsumerWidget {
  const RejectedSubmissionsBanner({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rejected = ref.watch(rejectedSubmissionsProvider).value ?? const [];
    if (rejected.isEmpty) return const SizedBox.shrink();
    final n = rejected.length;
    return Padding(
      padding: padding,
      child: InfoBanner(
        icon: Icons.error_outline_rounded,
        tone: Tone.danger,
        message:
            '$n formulaire${n > 1 ? 's' : ''} refusé${n > 1 ? 's' : ''} : à corriger ou supprimer.',
        action: TextButton(
          onPressed: () => showRejectedSubmissions(context),
          child: const Text('Voir'),
        ),
      ),
    );
  }
}

/// Liste des formulaires refusés, avec le motif et les actions possibles.
Future<void> showRejectedSubmissions(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _RejectedSheet(),
    );

class _RejectedSheet extends ConsumerWidget {
  const _RejectedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rejected = ref.watch(rejectedSubmissionsProvider).value ?? const [];
    if (rejected.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Text(
          'Aucun formulaire refusé.',
          textAlign: TextAlign.center,
          style: text.bodyLarge,
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xxl),
      children: [
        Text('Formulaires refusés', style: text.titleLarge?.bold),
        const SizedBox(height: Space.xs),
        Text(
          'Le serveur ne les a pas acceptés. Ils sont gardés sur votre téléphone tant que vous ne les avez pas corrigés ou supprimés.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.lg),
        for (final s in rejected) _RejectedTile(row: s),
      ],
    );
  }
}

class _RejectedTile extends ConsumerWidget {
  const _RejectedTile({required this.row});

  final PendingSubmission row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final retry = canRetrySubmission(row.errorCode);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.missionTitle, style: text.titleSmall?.semibold),
            Text(
              'Saisi le ${formatShortDate(row.submittedAt.toLocal())} à ${formatTime(row.submittedAt.toLocal())}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.sm),
            Text(
              row.error ?? 'Refusé',
              style: text.bodyMedium?.copyWith(color: scheme.error),
            ),
            const SizedBox(height: Space.xs),
            Text(
              rejectionHint(row.errorCode),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.sm),
            // Passe à la ligne sur les petits écrans plutôt que de déborder.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      unawaited(discardSubmission(ref, row.clientId)),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Supprimer'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                ),
                if (retry)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(
                        '/missions/${row.missionId}/new?retry=${row.clientId}',
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Corriger'),
                    // Le thème donne aux boutons pleins toute la largeur : ici, sa taille naturelle.
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
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
