import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/local_notifications.dart';
import '../../core/providers.dart';
import '../../core/push.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../profile/notifications_screen.dart';
import '../team/team_controller.dart';

/// Espace connecté : enregistre le téléphone pour les notifications push (autorisation
/// demandée avec explication si la formule les inclut) et ouvre l'écran d'une notification
/// touchée, ou exécute son bouton (« Approuver » une demande de zone).
class PushHandler extends ConsumerStatefulWidget {
  const PushHandler({super.key, required this.leader, required this.child});

  final bool leader;
  final Widget child;

  @override
  ConsumerState<PushHandler> createState() => _PushHandlerState();
}

class _PushHandlerState extends ConsumerState<PushHandler> {
  /// Tests sur simulateur : pas de fenêtre d'autorisation devant les écrans capturés.
  static const _skipPrompt = bool.fromEnvironment('SKIP_NOTIFICATION_PROMPT');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final open = ref.read(pushInboxProvider.notifier).take();
      if (open != null) unawaited(_handle(open));
      unawaited(_prepare());
    });
  }

  Future<void> _prepare() async {
    final push = ref.read(pushProvider);
    final me = ref.read(meProvider);
    await push.attach(me);
    if (_skipPrompt || !await push.shouldAsk(me)) return;
    // Laisse l'écran d'accueil s'afficher avant la question.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final accepted = await _explain(context, widget.leader);
    if (!mounted) return;
    if (accepted) {
      await push.enable();
    } else {
      await push.askLater();
    }
  }

  Future<void> _handle(PushOpen open) async {
    ref.invalidate(notificationsProvider);
    final data = open.data;
    final requestId = data['requestId'];
    if (widget.leader && requestId != null) {
      if (open.action == zoneApproveAction) return _approve(requestId);
      if (open.action == zoneRejectAction) {
        context.go('/requests');
        showMessage(context, 'Indiquez le motif du refus.');
        return;
      }
    }
    var route = pushRouteFor(data, leader: widget.leader);
    if (route.startsWith('/missions') && !ref.read(meProvider).hasMissions) {
      route = '/notifications';
    }
    // Onglets : on y va ; écrans secondaires : ouverts par-dessus l'onglet en cours.
    const pushed = ['/notifications', '/alerts', '/report', '/sos'];
    if (pushed.contains(route)) {
      unawaited(context.push(route));
    } else {
      context.go(route);
    }
  }

  Future<void> _approve(String requestId) async {
    context.go('/requests');
    try {
      await ref
          .read(requestsProvider.notifier)
          .decide(requestId, approve: true);
      if (mounted) showMessage(context, 'Demande de zone approuvée.');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
      unawaited(ref.read(requestsProvider.notifier).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pushInboxProvider, (_, next) {
      if (next == null) return;
      final open = ref.read(pushInboxProvider.notifier).take();
      if (open != null) unawaited(_handle(open));
    });
    // Formule changée en cours de session : téléphone enregistré si elle inclut le push.
    ref.listen(meProvider.select((me) => me.hasPush), (was, has) {
      if (has && was != true) unawaited(_prepare());
    });
    return widget.child;
  }
}

/// Explique ce que le téléphone recevra avant la demande du système.
Future<bool> _explain(BuildContext context, bool leader) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      final scheme = Theme.of(context).colorScheme;
      Widget point(IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: text.bodyLarge)),
          ],
        ),
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: IconSquircle(
                icon: Icons.notifications_active_outlined,
                size: 40,
              ),
            ),
            const SizedBox(height: Space.lg),
            Text('Restez informé', style: text.headlineSmall),
            const SizedBox(height: 16),
            if (leader) ...[
              point(
                Icons.pending_actions_outlined,
                'Les demandes de zone de votre équipe, à approuver directement depuis la notification.',
              ),
              point(
                Icons.warning_amber_rounded,
                'Les alertes : retard, sortie de zone, GPS coupé.',
              ),
            ] else ...[
              point(
                Icons.check_circle_outline_rounded,
                'La réponse à vos demandes de zone.',
              ),
              point(
                Icons.flag_outlined,
                'Les nouvelles missions et les formulaires à corriger.',
              ),
            ],
            point(
              Icons.chat_bubble_outline_rounded,
              'Les messages et les paiements, même application fermée.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Activer les notifications'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Plus tard'),
            ),
          ],
        ),
      );
    },
  );
  return accepted ?? false;
}
