// Formulaire refusé par le serveur (mission close pendant la saisie), sur simulateur contre
// l'API locale. Le script de lancement désactive la mission à « ACT:close ».
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

  testWidgets('formulaire refusé à l’envoi : motif affiché, saisie conservée', (
    tester,
  ) async {
    await login(tester, '07 02 02 02 01');
    await waitFor(tester, find.text('Ma journée'));
    await settle(tester, 2000);
    await tester.tap(find.text('Missions').last);
    await waitFor(tester, find.text('Tournée Plateau – test refus'));
    await tester.tap(find.text('Tournée Plateau – test refus'));
    await waitFor(tester, find.text('Nouveau formulaire'));
    await tester.tap(find.text('Nouveau formulaire'));
    await waitFor(tester, find.text('Enregistrer'));
    await tester.enterText(find.byType(TextFormField).first, 'Boutique Awa');
    await tester.tap(find.text('Oui').first);
    await settle(tester);
    await shot(tester, '01-saisie');

    // L'administrateur clôt la mission pendant la saisie.
    debugPrint('ACT:close');
    await settle(tester, 2500);
    await tester.tap(find.text('Enregistrer'));
    await waitFor(tester, find.textContaining('Refusé :'));
    await shot(tester, '02-refus');
    expect(find.text('Boutique Awa'), findsOneWidget);
  });
}
