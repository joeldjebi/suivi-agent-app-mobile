import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/tracking.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';

/// Explique le partage de position avant la demande système (transparence, ARTCI),
/// puis demande l'autorisation. Renvoie vrai si le suivi peut démarrer.
Future<bool> ensureLocationConsent(
  BuildContext context,
  LocationTracker tracker, {
  required String structure,
  required bool trackDuringPause,
}) async {
  var access = await tracker.access();
  if (access == LocationAccess.granted ||
      access == LocationAccess.needsAlways) {
    return true;
  }
  if (!context.mounted) return false;

  if (access == LocationAccess.serviceDisabled) {
    final open = await confirmSheet(
      context,
      title: 'Activez la localisation',
      message:
          'La localisation du téléphone est désactivée. Activez-la pour démarrer votre journée.',
      confirmLabel: 'Ouvrir les réglages',
    );
    if (open) await Geolocator.openLocationSettings();
    return false;
  }

  if (access == LocationAccess.deniedForever) {
    final open = await confirmSheet(
      context,
      title: 'Autorisation refusée',
      message:
          'Autorisez l’accès à la position dans les réglages de l’application pour démarrer votre journée.',
      confirmLabel: 'Ouvrir les réglages',
    );
    if (open) await Geolocator.openAppSettings();
    return false;
  }

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
                icon: Icons.share_location_outlined,
                size: 40,
              ),
            ),
            const SizedBox(height: Space.lg),
            Text('Partage de votre position', style: text.headlineSmall),
            const SizedBox(height: 16),
            point(
              Icons.schedule_rounded,
              'Votre position est partagée avec $structure uniquement pendant votre journée${trackDuringPause ? ', pauses comprises' : ', hors pauses'}.',
            ),
            point(
              Icons.stop_circle_outlined,
              'Le suivi s’arrête dès que vous terminez votre journée.',
            ),
            point(
              Icons.notifications_active_outlined,
              'Une notification reste visible tant que le suivi est actif.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Autoriser et continuer'),
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
  if (accepted != true) return false;
  access = await tracker.access(request: true);
  return access == LocationAccess.granted ||
      access == LocationAccess.needsAlways;
}
