import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/push.dart';
import 'features/onboarding/onboarding_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final container = ProviderContainer();
  // Reprise de session (et de l'apparence de la structure) avant le premier écran utile.
  container.read(authProvider.notifier).restore();
  // Onboarding vérifié en même temps (affiché au premier lancement ou à une nouvelle version).
  container.read(onboardingProvider);
  // Notifications push : réception et notification qui a lancé l'app.
  unawaited(container.read(pushProvider).start());
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SuiviAgentApp(),
    ),
  );
}
