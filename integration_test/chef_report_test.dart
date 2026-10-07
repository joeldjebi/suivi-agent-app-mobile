// Bilan du jour et message à l'équipe du chef, sur simulateur contre l'API locale (démo).
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

  testWidgets('chef : bilan du jour et message à l’équipe', (tester) async {
    await login(tester, '07 01 01 01 01');
    await waitFor(tester, find.text('Mon équipe'));
    await settle(tester, 2000);
    await shot(tester, '01-equipe');
    await tester.tap(find.text('Bilan du jour'));
    await waitFor(tester, find.text('JOURNÉES'));
    await shot(tester, '02-bilan');
    await tester.tap(find.byTooltip('Jour précédent'));
    await settle(tester, 2500);
    await shot(tester, '03-bilan-veille');
    await tester.tap(find.byTooltip('Jour suivant'));
    await settle(tester, 1500);
    await tester.tap(find.text('Message à l’équipe'));
    await settle(tester);
    await tester.enterText(
      find.byType(TextField).last,
      'Test : réunion à 17 h au bureau du Plateau.',
    );
    await settle(tester);
    await shot(tester, '04-message');
    await tester.tap(find.text('Envoyer'));
    await waitFor(tester, find.textContaining('Message envoyé à'));
    await shot(tester, '05-envoye');
  });
}
