import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_version.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';

Future<void> openStore(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// App trop ancienne : plus rien ne fonctionne avant la mise à jour.
class UpdateScreen extends ConsumerStatefulWidget {
  const UpdateScreen({super.key});

  @override
  ConsumerState<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends ConsumerState<UpdateScreen> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateProvider);
    final url = update?.storeUrl;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(
                child: IconSquircle(
                  icon: Icons.system_update_rounded,
                  size: 72,
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(
                'Mise à jour nécessaire',
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Cette version de l’application (${AppVersion.current}) n’est plus prise en charge'
                '${update?.version == null ? '' : ' : installez la version ${update!.version} ou plus récente'}.',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: muted),
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Vos journées et formulaires enregistrés sur le téléphone seront envoyés après la mise à jour.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: muted),
              ),
              const Spacer(),
              if (url != null)
                PillButton(
                  label: 'Télécharger la mise à jour',
                  icon: Icons.download_rounded,
                  onPressed: () => openStore(url),
                )
              else
                const InfoBanner(
                  icon: Icons.info_outline_rounded,
                  tone: Tone.info,
                  message:
                      'Demandez le lien de la nouvelle version à votre structure.',
                ),
              const SizedBox(height: Space.sm),
              TextButton(
                onPressed: _checking
                    ? null
                    : () async {
                        setState(() => _checking = true);
                        await ref.read(updateProvider.notifier).check();
                        if (mounted) setState(() => _checking = false);
                      },
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nouvelle version disponible (non obligatoire) : invitation discrète.
class UpdateAvailableBanner extends ConsumerWidget {
  const UpdateAvailableBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateProvider);
    final url = update?.storeUrl;
    if (update == null || update.required || url == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: InfoBanner(
        icon: Icons.system_update_rounded,
        tone: Tone.info,
        message: 'Nouvelle version ${update.version ?? ''} disponible.',
        action: TextButton(
          onPressed: () => openStore(url),
          child: const Text('Mettre à jour'),
        ),
      ),
    );
  }
}
