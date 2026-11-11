import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'core/app_lock.dart';
import 'core/app_version.dart';
import 'core/error_report.dart';
import 'core/photo_files.dart';
import 'core/providers.dart';
import 'core/push.dart';
import 'features/onboarding/onboarding_data.dart';

/// Supervision des erreurs (Sentry, projet performx-mobile). Clé publique, intégrée aux
/// versions publiées (release) ; aucune en développement ni pendant les tests.
/// --dart-define=SENTRY_DSN=… la remplace (vide : désactivée).
const _sentryDsnPubliee =
    'https://24e3366afe1458343c8c62d5ced2b293@o4512291627663360.ingest.de.sentry.io/4512291664625744';
const _sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue: kReleaseMode ? _sentryDsnPubliee : '',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppVersion.load();
  // Version web : photos en attente d'envoi relues depuis le navigateur.
  await initPhotoFiles();
  if (_sentryDsn.isEmpty) return _run();
  // Web : l'app s'affiche d'abord ; Sentry (script téléchargé depuis son site) suit, sans
  // retarder l'ouverture. Ses gestionnaires d'erreurs s'ajoutent à ceux déjà en place.
  if (kIsWeb) {
    await _run();
    return SentryFlutter.init(_sentryOptions);
  }
  await SentryFlutter.init(_sentryOptions, appRunner: _run);
}

void _sentryOptions(SentryFlutterOptions options) {
  options
    ..dsn = _sentryDsn
    ..release = 'suivi-agent@${AppVersion.current}'
    ..tracesSampleRate = 0
    // Rien de personnel : ni capture d'écran, ni saisie, ni identité.
    ..sendDefaultPii = false
    ..attachScreenshot = false
    ..beforeSend = (event, hint) {
      // Échec de téléchargement d'une tuile de carte (réseau mobile lent/coupé) : attendu,
      // pas un bug — on ne le remonte pas pour ne pas polluer le journal d'erreurs.
      if (_isTileLoadError(event)) return null;
      event.user = null;
      return event;
    };
}

/// Vrai si l'événement vient d'un échec de chargement de tuile (flutter_map / OSM).
bool _isTileLoadError(SentryEvent event) {
  bool mark(String? s) =>
      s != null &&
      (s.contains('NetworkTileImageProvider') ||
          s.contains('tile_provider/network') ||
          s.contains('tile.openstreetmap'));
  if (mark(event.throwable?.toString())) return true;
  for (final ex in event.exceptions ?? const <SentryException>[]) {
    if (mark(ex.value)) return true;
    for (final f in ex.stackTrace?.frames ?? const <SentryStackFrame>[]) {
      if (mark(f.absPath) || mark(f.fileName) || mark(f.function)) return true;
    }
  }
  return false;
}

Future<void> _run() async {
  await initializeDateFormatting('fr_FR');
  final container = ProviderContainer();
  // Élément impossible à afficher (version publiée) : un message clair, pas un bloc gris.
  if (kReleaseMode) {
    ErrorWidget.builder = (_) => const Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Affichage impossible pour le moment. Revenez en arrière puis réessayez.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
  // Erreurs inattendues : journal de la console éditeur.
  ErrorReporter(container).install();
  // Reprise de session (et de l'apparence de la structure) avant le premier écran utile.
  container.read(authProvider.notifier).restore();
  // Onboarding vérifié en même temps (affiché au premier lancement ou à une nouvelle version).
  container.read(onboardingProvider);
  // Verrouillage Face ID / empreinte relu avant le premier écran.
  container.read(appLockProvider);
  // Mémoire hors ligne : les écrans non relus depuis 7 jours sont oubliés.
  unawaited(
    container
        .read(databaseProvider)
        .cachePrune(const Duration(days: 7))
        .catchError((Object _) {}),
  );
  // Version minimale et dernière version publiées.
  unawaited(container.read(updateProvider.notifier).check());
  // Notifications push : réception et notification qui a lancé l'app.
  unawaited(container.read(pushProvider).start());
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SuiviAgentApp(),
    ),
  );
}
