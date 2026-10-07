// Mises à jour en direct et modification d'une mission par le chef, sur simulateur contre
// l'API locale (démo). Le script de lancement modifie la mission côté admin à « ACT:rename ».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/session.dart';
import 'package:suivi_agent/main.dart' as app;

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Introuvable après ${timeout.inSeconds} s : $finder');
}

Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, 2000);
  debugPrint('SHOT:$name');
  await settle(tester, 2500);
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

  Future<void> login(WidgetTester tester, String phone) async {
    app.main();
    // Premier lancement : l'onboarding passe avant la connexion.
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
    await tester.enterText(find.byType(TextFormField).at(0), phone);
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.tap(find.text('Se connecter'));
  }

  testWidgets('chef : mission modifiée par l’admin en direct, puis par le chef', (
    tester,
  ) async {
    await login(tester, '07 01 01 01 01');
    await waitFor(tester, find.text('Mon équipe'));
    await settle(tester, 1500);
    await tester.tap(find.text('Missions').last);
    // Échéance dépassée : la mission est rangée dans « Terminées ».
    await waitFor(tester, find.textContaining('Terminées'));
    await tester.tap(find.textContaining('Terminées'));
    await waitFor(tester, find.text('120 visites cette semaine'));
    await tester.tap(find.text('120 visites cette semaine'));
    await waitFor(tester, find.byTooltip('Gérer la mission'));
    await shot(tester, '01-mission');

    // L'admin renomme la mission sur le web : l'écran change sans geste.
    debugPrint('ACT:rename');
    await waitFor(
      tester,
      find.text('120 visites – modifiée par l’admin'),
      timeout: const Duration(seconds: 15),
    );
    await shot(tester, '02-en-direct');

    // Modification par le chef : échéance dépassée, le calendrier s'ouvre sur aujourd'hui.
    await tester.tap(find.byTooltip('Gérer la mission'));
    await settle(tester);
    await tester.tap(find.text('Modifier'));
    await waitFor(tester, find.text('Enregistrer'));
    await tester.tap(find.text('Échéance').last);
    await settle(tester);
    await shot(tester, '03-calendrier');
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.enterText(
      find.byType(TextFormField).first,
      '120 visites cette semaine',
    );
    await settle(tester);
    await shot(tester, '04-edition');
    await tester.tap(find.text('Enregistrer'));
    await waitFor(tester, find.text('Mission mise à jour'));
    await waitFor(tester, find.text('120 visites cette semaine'));
    await shot(tester, '05-enregistre');
  });
}
