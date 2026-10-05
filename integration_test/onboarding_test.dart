// Démarrage, onboarding réglé par l'éditeur et retour depuis le profil, sur simulateur
// contre l'API locale (le script de lancement modifie la page 2 avant le test).
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

  testWidgets('démarrage, onboarding animé, puis revu depuis le profil', (
    tester,
  ) async {
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint('SHOT:01-splash');
    await settle(tester, 1500);

    await waitFor(tester, find.text('Votre journée, en un geste'));
    await shot(tester, '02-page1');
    // Toucher l'animation la rejoue.
    await tester.tap(find.byType(PageView));
    await settle(tester, 400);
    debugPrint('SHOT:03-page1-rejouee');
    await settle(tester, 1500);

    await tester.tap(find.text('Suivant'));
    await waitFor(tester, find.text('Vos missions, partout'));
    await shot(tester, '04-page2-editeur');

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await waitFor(tester, find.text('Commencer'));
    await shot(tester, '05-page3');
    await tester.tap(find.text('Commencer'));
    await waitFor(tester, find.text('Se connecter'));
    await shot(tester, '06-connexion');

    await tester.enterText(find.byType(TextFormField).at(0), '07 02 02 02 01');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.tap(find.text('Se connecter'));
    await waitFor(tester, find.text('Profil'));
    await settle(tester, 1500);
    await tester.tap(find.text('Profil').last);
    await waitFor(tester, find.text('Découvrir l’app'));
    await tester.scrollUntilVisible(
      find.text('Découvrir l’app'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Au-dessus de la barre d'onglets.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester, 600);
    await tester.tap(find.text('Découvrir l’app'));
    await waitFor(tester, find.text('Votre journée, en un geste'));
    await shot(tester, '07-revu-profil');
    await tester.tap(find.text('Passer'));
    await waitFor(tester, find.text('Découvrir l’app'));
  });
}
