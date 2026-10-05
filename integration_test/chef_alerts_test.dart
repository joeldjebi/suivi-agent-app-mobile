// Alertes intelligentes vues par le chef, sur simulateur contre l'API locale (démo) :
// le planificateur du serveur a ouvert des alertes sur des agents de l'Équipe Nord ; le chef
// les reçoit en notifications et voit les agents en alerte dans « Mon équipe ».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/session.dart';
import 'package:suivi_agent/design/components.dart';
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

  testWidgets('chef : alertes reçues, centre d’alertes et prise en charge', (
    tester,
  ) async {
    app.main();
    await waitFor(tester, find.text('Se connecter'));
    await tester.enterText(find.byType(TextFormField).at(0), '07 01 01 01 01');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.tap(find.text('Se connecter'));
    await waitFor(tester, find.text('Mon équipe'));
    await waitFor(tester, find.text('Immobile'));
    await shot(tester, '01-equipe');

    await tester.tap(
      find.ancestor(
        of: find.text('Alertes'),
        matching: find.byType(SurfaceCard),
      ),
    );
    await waitFor(tester, find.textContaining('Batterie'));
    await shot(tester, '02-alertes');

    // Détail d'Aminata : ses alertes, puis je m'en occupe.
    await tester.tap(find.text('Aminata Diallo').first);
    await settle(tester);
    await shot(tester, '03-detail');
    await tester.enterText(
      find.byType(TextField).last,
      'Appelée : en rendez-vous client',
    );
    await tester.tap(find.text('Je m’en occupe'));
    await waitFor(tester, find.textContaining('Yao Kouassi s’en occupe'));
    await shot(tester, '04-prise');

    await tester.tap(find.text('Aminata Diallo').first);
    await settle(tester);
    await tester.tap(find.text('Carte'));
    await settle(tester, 2500);
    await shot(tester, '05-carte');
  });
}
