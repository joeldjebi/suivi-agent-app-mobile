// Validation d'une demande de zone par le chef, vue de l'app de l'agent (simulateur, API
// locale) : « ACT:approve » demande à un script externe de valider la demande ; le test
// mesure le temps avant que l'écran de l'agent change.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/session.dart';
import 'package:suivi_agent/main.dart' as app;

import 'zone_test.dart' show settle, shot, waitFor;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await SessionStore().clear();
    (await SharedPreferences.getInstance()).clear();
    final db = AppDatabase();
    await db.wipe();
    await db.close();
  });

  testWidgets('agent : la validation du chef s’affiche sans geste', (
    tester,
  ) async {
    app.main();
    await waitFor(
      tester,
      find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'Se connecter' || w.data == 'Passer'),
      ),
    );
    if (find.text('Passer').evaluate().isNotEmpty) {
      await tester.tap(find.text('Passer'));
    }
    await waitFor(tester, find.text('Se connecter'));
    await tester.enterText(find.byType(TextFormField).at(0), '07 02 02 02 01');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.tap(find.text('Se connecter'));
    await waitFor(tester, find.text('Choisir ma zone'));
    await tester.tap(find.text('Choisir ma zone'));
    await waitFor(tester, find.text('Plateau'));
    await tester.tap(find.text('Plateau').first);
    await waitFor(tester, find.text('Validation en attente'));
    await shot(tester, '01-en-attente');

    // L'agent quitte l'app ; le chef valide pendant ce temps ; l'agent revient.
    debugPrint('ACT:${const String.fromEnvironment('SCENARIO', defaultValue: 'approve')}');
    await settle(tester, 12000);
    final start = DateTime.now();
    await waitFor(
      tester,
      find.text('Démarrer ma journée'),
      timeout: const Duration(seconds: 40),
    );
    debugPrint(
      'VERIF:visible apres ${DateTime.now().difference(start).inMilliseconds} ms',
    );
    await shot(tester, '02-validee');
  });
}
