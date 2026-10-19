import 'package:flutter/material.dart';

import '../core/install_app.dart';
import '../core/platform.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import 'common.dart';

/// Version web ouverte dans le navigateur (pas encore installée sur l'écran d'accueil).
bool get canInstallApp => AppPlatform.isWeb && !installStandalone();

/// Installe la version web : fenêtre du navigateur si elle existe (Android, Chrome),
/// sinon les gestes à faire (iPhone : Partager → « Sur l'écran d'accueil »).
Future<void> installApp(BuildContext context) async {
  if (installCanPrompt()) {
    final accepted = await installPrompt();
    if (accepted && context.mounted) {
      showMessage(context, 'PerformX est installée sur votre écran d’accueil.');
    }
    return;
  }
  if (!context.mounted) return;
  final ios = installIsIOS();
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      final scheme = Theme.of(context).colorScheme;
      Widget step(int n, IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: scheme.primary,
              child: Text(
                '$n',
                style: text.labelMedium?.copyWith(color: scheme.onPrimary),
              ),
            ),
            const SizedBox(width: Space.md),
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(label, style: text.bodyLarge)),
          ],
        ),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: IconSquircle(
                icon: Icons.add_to_home_screen_rounded,
                size: 40,
              ),
            ),
            const SizedBox(height: Space.lg),
            Text('Installer PerformX', style: text.headlineSmall),
            const SizedBox(height: Space.sm),
            Text(
              'PerformX s’ouvrira depuis l’écran d’accueil, en plein écran, comme une app.',
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.xl),
            if (ios) ...[
              step(
                1,
                Icons.ios_share_rounded,
                'Dans Safari, touchez Partager (le carré avec une flèche).',
              ),
              step(
                2,
                Icons.add_box_outlined,
                'Choisissez «\u00a0Sur l’écran d’accueil\u00a0», puis «\u00a0Ajouter\u00a0».',
              ),
            ] else ...[
              step(
                1,
                Icons.more_vert_rounded,
                'Ouvrez le menu du navigateur (⋮ ou ⋯).',
              ),
              step(
                2,
                Icons.install_mobile_rounded,
                'Choisissez «\u00a0Installer l’application\u00a0» ou «\u00a0Ajouter à l’écran d’accueil\u00a0».',
              ),
            ],
            const SizedBox(height: Space.lg),
            PillButton(
              label: 'J’ai compris',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    },
  );
}

/// Carte « Installer PerformX » (profil), visible seulement dans le navigateur.
class InstallAppCard extends StatelessWidget {
  const InstallAppCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!canInstallApp) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: GroupedList(
        children: [
          ListRow(
            leading: const IconSquircle(
              icon: Icons.add_to_home_screen_rounded,
              size: 28,
              solid: true,
            ),
            title: 'Installer PerformX',
            subtitle: 'Sur l’écran d’accueil, comme une app',
            onTap: () => installApp(context),
          ),
        ],
      ),
    );
  }
}

/// Lien discret sous la connexion, visible seulement dans le navigateur.
class InstallAppLink extends StatelessWidget {
  const InstallAppLink({super.key});

  @override
  Widget build(BuildContext context) {
    if (!canInstallApp) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Center(
        child: TextButton.icon(
          onPressed: () => installApp(context),
          icon: const Icon(Icons.add_to_home_screen_rounded, size: 20),
          label: const Text('Installer l’app sur cet appareil'),
        ),
      ),
    );
  }
}
