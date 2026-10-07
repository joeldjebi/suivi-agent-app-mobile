import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'core/app_lock.dart';
import 'core/app_version.dart';
import 'core/providers.dart';
import 'core/push.dart';
import 'features/onboarding/onboarding_data.dart';

/// Supervision des erreurs (Sentry) : active seulement si l'app est compilée avec
/// --dart-define=SENTRY_DSN=…
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppVersion.load();
  if (_sentryDsn.isEmpty) return _run();
  await SentryFlutter.init((options) {
    options
      ..dsn = _sentryDsn
      ..release = 'suivi-agent@${AppVersion.current}'
      ..tracesSampleRate = 0
      // Rien de personnel : ni capture d'écran, ni saisie, ni identité.
      ..sendDefaultPii = false
      ..attachScreenshot = false
      ..beforeSend = (event, hint) {
        event.user = null;
        return event;
      };
  }, appRunner: _run);
}

Future<void> _run() async {
  await initializeDateFormatting('fr_FR');
  final container = ProviderContainer();
  // Reprise de session (et de l'apparence de la structure) avant le premier écran utile.
  container.read(authProvider.notifier).restore();
  // Onboarding vérifié en même temps (affiché au premier lancement ou à une nouvelle version).
  container.read(onboardingProvider);
  // Verrouillage Face ID / empreinte relu avant le premier écran.
  container.read(appLockProvider);
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
