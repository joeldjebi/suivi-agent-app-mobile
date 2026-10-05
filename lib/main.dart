import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final container = ProviderContainer();
  // Reprise de session (et de l'apparence de la structure) avant le premier écran utile.
  container.read(authProvider.notifier).restore();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SuiviAgentApp(),
    ),
  );
}
