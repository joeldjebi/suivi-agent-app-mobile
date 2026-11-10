import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';

/// Inscription de la structure pas encore validée (ou refusée) par l'éditeur :
/// l'app est bloquée tant que l'éditeur n'a pas validé le compte.
class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final branding = ref.watch(brandingProvider);
    final auth = ref.watch(authProvider);
    final me = auth is SignedIn ? auth.me : null;
    final rejected = me?.rejected ?? false;
    final reason = me?.rejectionReason;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: IconSquircle(
                  icon: rejected
                      ? Icons.cancel_rounded
                      : Icons.hourglass_top_rounded,
                  color: rejected ? scheme.error : scheme.primary,
                  size: 56,
                ),
              ),
              const SizedBox(height: Space.xl),
              Text(
                rejected ? 'Inscription non retenue' : 'Compte en attente',
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: Space.sm),
              Text(
                rejected
                    ? 'L’inscription de ${branding.displayName} n’a pas été '
                          'retenue par l’éditeur.'
                    : 'L’inscription de ${branding.displayName} est en cours de '
                          'validation par l’éditeur. Vous pourrez accéder à '
                          'l’application dès qu’elle sera validée.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (rejected && reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                Container(
                  padding: const EdgeInsets.all(Space.lg),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(Radii.card),
                  ),
                  child: Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                ),
              ],
              const SizedBox(height: Space.xxl),
              PillButton(
                label: 'Réessayer',
                icon: Icons.refresh_rounded,
                onPressed: () => ref.read(authProvider.notifier).restore(),
              ),
              const SizedBox(height: Space.sm),
              PillButton(
                label: 'Se déconnecter',
                style: PillStyle.outline,
                onPressed: () => ref.read(authProvider.notifier).logout(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
