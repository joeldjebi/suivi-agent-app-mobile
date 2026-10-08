import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/network_status.dart';
import '../../core/providers.dart';

/// « 14:32 » aujourd'hui, « hier à 18:10 », sinon « le 6 oct. à 18:10 ».
String _when(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 0) return formatTime(at);
  if (days == 1) return 'hier à ${formatTime(at)}';
  return 'le ${formatShortDate(at)} à ${formatTime(at)}';
}

/// Texte du bandeau hors ligne.
String offlineMessage(DateTime? lastOnlineAt, [DateTime? now]) =>
    lastOnlineAt == null
    ? 'Hors ligne · Données enregistrées sur le téléphone'
    : 'Hors ligne · Données de votre dernière connexion (${_when(lastOnlineAt, now ?? DateTime.now())})';

/// Hors ligne : petit bandeau en haut de l'app ; les écrans affichent les dernières
/// données reçues et se mettent à jour d'eux-mêmes au retour du réseau.
class OfflineFrame extends ConsumerWidget {
  const OfflineFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkProvider);
    final phoneOnline = ref.watch(syncProvider.select((s) => s.online));
    final offline = !network.online || !phoneOnline;
    if (!offline) return child;
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Semantics(
          liveRegion: true,
          child: Material(
            color: scheme.inverseSurface,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, top + 6, 16, 7),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 16,
                    color: scheme.onInverseSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      offlineMessage(network.lastOnlineAt),
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onInverseSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
