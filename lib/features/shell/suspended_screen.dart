import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';

/// Abonnement de la structure suspendu (facture impayée) : l'app est bloquée.
class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final branding = ref.watch(brandingProvider);
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
                  icon: Icons.block_rounded,
                  color: scheme.error,
                  size: 56,
                ),
              ),
              const SizedBox(height: Space.xl),
              Text(
                'Accès suspendu',
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'L’abonnement de ${branding.displayName} est suspendu. '
                'Votre position n’est plus partagée. Contactez votre responsable.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
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
