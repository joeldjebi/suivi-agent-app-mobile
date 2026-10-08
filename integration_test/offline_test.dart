// Mode hors ligne sur simulateur, contre l'API locale : « ACT:apidown » / « ACT:apiup »
// demandent à un script externe d'arrêter puis de relancer l'API.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/session.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/main.dart' as app;

import 'zone_test.dart' show settle, shot, waitFor;

Finder _tab(String label) =>
    find.descendant(of: find.byType(AppNavBar), matching: find.text(label));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await SessionStore().clear();
    (await SharedPreferences.getInstance()).clear();
    final db = AppDatabase();
    await db.wipe();
    await db.close();
  });

  testWidgets('hors ligne : les écrans déjà vus restent affichés', (
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
    await tester.enterText(find.byType(TextFormField).at(0), '07 02 02 02 02');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.tap(find.text('Se connecter'));
    await waitFor(tester, _tab('Missions'));
    await settle(tester, 2000);
    // Écrans consultés avec du réseau.
    await tester.tap(_tab('Missions'));
    await settle(tester, 3000);
    await shot(tester, '01-missions-en-ligne');
    await tester.tap(_tab('Journée'));
    await settle(tester, 1500);
    await tester.tap(find.text('Ma semaine').first);
    await settle(tester, 3000);
    await shot(tester, '02-semaine-en-ligne');
    await tester.tap(find.byType(BackButton));
    await settle(tester, 1500);

    debugPrint('ACT:apidown');
    await settle(tester, 6000);
    // Retour sur les écrans : relus sans réseau.
    await tester.tap(_tab('Missions'));
    await settle(tester, 4000);
    await waitFor(tester, find.textContaining('Hors ligne ·'));
    debugPrint(
      'VERIF:erreur=${find.textContaining('Réessayez au retour').evaluate().length}',
    );
    await shot(tester, '03-missions-hors-ligne');
    await tester.tap(_tab('Journée'));
    await settle(tester, 1500);
    await tester.tap(find.text('Ma semaine').first);
    await settle(tester, 4000);
    debugPrint(
      'VERIF:semaine-erreur=${find.textContaining('Réessayez au retour').evaluate().length}',
    );
    await shot(tester, '04-semaine-hors-ligne');
    await tester.tap(find.byType(BackButton));
    await settle(tester, 1500);

    debugPrint('ACT:apiup');
    final start = DateTime.now();
    final end = start.add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(end) &&
        find.textContaining('Hors ligne ·').evaluate().isNotEmpty) {
      await settle(tester, 1000);
    }
    debugPrint(
      'VERIF:bandeau=${find.textContaining('Hors ligne ·').evaluate().length} apres ${DateTime.now().difference(start).inSeconds} s',
    );
    await shot(tester, '05-de-retour');
  });
}
