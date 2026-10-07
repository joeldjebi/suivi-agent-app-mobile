// Chrono de la journée hors de l'app (Live Activity) sur simulateur, contre l'API locale :
// l'agent Aminata Diallo a une journée ouverte. « BG:nom » : un script externe met l'app en
// arrière-plan, capture l'écran (Dynamic Island) puis la ramène.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/session.dart';
import 'package:suivi_agent/main.dart' as app;

import 'zone_test.dart' show settle, shot, waitFor;

Future<void> background(WidgetTester tester, String name) async {
  await settle(tester, 1500);
  debugPrint('BG:$name');
  await settle(tester, 9000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await SessionStore().clear();
    (await SharedPreferences.getInstance()).clear();
    final db = AppDatabase();
    await db.wipe();
    await db.close();
  });

  testWidgets('agent : chrono de la journée sur l’écran verrouillé', (
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
    await waitFor(tester, find.text('MA ZONE'));
    await shot(tester, '01-journee');
    await background(tester, '02-island-journee');

    await tester.tap(find.text('Pause'));
    await settle(tester, 3000);
    await shot(tester, '03-pause');
    await background(tester, '04-island-pause');

    await tester.tap(find.text('Reprendre'));
    await settle(tester, 3000);
  });
}
