import 'dart:async';

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

/// Nouvelle version (mineure ou recommandée) : fenêtre qu'on peut fermer, affichée dès que
/// l'éditeur la publie, puis de nouveau une fois par jour (mineure) ou toutes les heures
/// (recommandée) tant que l'app n'est pas à jour. Une version critique bloque l'app (écran).
class UpdatePrompt extends ConsumerStatefulWidget {
  const UpdatePrompt({super.key, required this.child});

  final Widget child;

  /// Dernière proposition : « version|importance|instant ».
  static const prefKey = 'update.prompted';

  /// L'app ouverte longtemps : délai de nouvelle proposition vérifié régulièrement.
  static const tick = Duration(minutes: 1);

  /// Filet de sécurité si l'annonce en direct est manquée (connexion coupée).
  static const recheck = Duration(minutes: 30);

  /// À proposer maintenant ? Nouvelle version ou importance changée : tout de suite ; sinon
  /// après le délai de l'importance.
  static bool due(UpdateInfo update, String? last, DateTime now) {
    final parts = last?.split('|');
    if (parts == null || parts.length != 3) return true;
    if (parts[0] != '${update.version}' || parts[1] != update.importance.name) {
      return true;
    }
    final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[2]) ?? 0);
    return now.difference(at) >= update.remindEvery;
  }

  @override
  ConsumerState<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends ConsumerState<UpdatePrompt> {
  bool _showing = false;
  Timer? _tick;
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShow(ref.read(updateProvider)),
    );
    _tick = Timer.periodic(
      UpdatePrompt.tick,
      (_) => _maybeShow(ref.read(updateProvider)),
    );
    _recheck = Timer.periodic(
      UpdatePrompt.recheck,
      (_) => ref.read(updateProvider.notifier).check(),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _recheck?.cancel();
    super.dispose();
  }

  Future<void> _maybeShow(UpdateInfo? update) async {
    if (_showing || update == null || !update.prompt) return;
    final now = DateTime.now();
    SharedPreferences? prefs;
    String? last;
    try {
      prefs = await SharedPreferences.getInstance();
      last = prefs.getString(UpdatePrompt.prefKey);
    } catch (_) {
      // Stockage indisponible : proposée à chaque ouverture.
    }
    if (!UpdatePrompt.due(update, last, now) || !mounted || _showing) return;
    _showing = true;
    try {
      await prefs?.setString(
        UpdatePrompt.prefKey,
        '${update.version}|${update.importance.name}|${now.millisecondsSinceEpoch}',
      );
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
            update.importance == UpdateImportance.recommended
                ? 'Une mise à jour recommandée est disponible. Installez-la dès que possible.'
                : 'Une nouvelle version de l’application est disponible.',
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
