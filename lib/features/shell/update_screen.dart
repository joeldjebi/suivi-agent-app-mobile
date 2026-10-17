import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        child: FillScroll(
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
                if (update?.releaseNotes case final notes?) ...[
                  const SizedBox(height: Space.lg),
                  _ReleaseNotes(notes),
                ],
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

/// Nouveautés de la version, rédigées par l'éditeur.
class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes(this.notes);

  final String notes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nouveautés', style: text.titleSmall),
          const SizedBox(height: Space.xs),
          Text(notes, style: text.bodyMedium),
        ],
      ),
    );
  }
}

/// Mise à jour recommandée : fenêtre à l'ouverture de l'espace connecté, avec « Plus tard ».
/// Elle revient au plus une fois par jour tant que l'app n'est pas à jour.
class UpdatePrompt extends ConsumerStatefulWidget {
  const UpdatePrompt({super.key, required this.child});

  final Widget child;

  /// Dernière proposition : « version|jour ».
  static const prefKey = 'update.prompted';

  @override
  ConsumerState<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends ConsumerState<UpdatePrompt> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShow(ref.read(updateProvider)),
    );
  }

  Future<void> _maybeShow(UpdateInfo? update) async {
    if (_showing || update == null || !update.prompt) return;
    final now = DateTime.now();
    final mark = '${update.version}|${now.year}-${now.month}-${now.day}';
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (prefs.getString(UpdatePrompt.prefKey) == mark) return;
    } catch (_) {
      // Stockage indisponible : proposée à chaque ouverture.
    }
    if (!mounted || _showing) return;
    _showing = true;
    try {
      await prefs?.setString(UpdatePrompt.prefKey, mark);
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _UpdateSheet(update),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(updateProvider, (_, next) => _maybeShow(next));
    return widget.child;
  }
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet(this.update);

  final UpdateInfo update;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final url = update.storeUrl;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: IconSquircle(icon: Icons.system_update_rounded, size: 40),
          ),
          const SizedBox(height: Space.lg),
          Text(
            'Nouvelle version ${update.version ?? ''}'.trim(),
            style: text.headlineSmall,
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Une mise à jour recommandée est disponible. Installez-la dès que possible.',
            style: text.bodyLarge?.copyWith(color: muted),
          ),
          if (update.releaseNotes case final notes?) ...[
            const SizedBox(height: Space.lg),
            _ReleaseNotes(notes),
          ],
          const SizedBox(height: Space.xxl),
          if (url != null) ...[
            PillButton(
              label: 'Mettre à jour',
              icon: Icons.download_rounded,
              onPressed: () {
                Navigator.pop(context);
                openStore(url);
              },
            ),
            const SizedBox(height: Space.md),
          ],
          PillButton(
            label: 'Plus tard',
            style: PillStyle.outline,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
