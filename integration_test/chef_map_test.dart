// Affichage des cartes sur simulateur (vraies tuiles OpenStreetMap), contre l'API locale.
// Le script de lancement prépare des agents en journée et choisit le thème du simulateur.
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

  Future<void> login(WidgetTester tester, String phone) async {
    app.main();
    await waitFor(tester, find.text('Se connecter'));
    await tester.enterText(find.byType(TextFormField).at(0), phone);
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.tap(find.text('Se connecter'));
  }

  testWidgets('chef : carte de l’équipe', (tester) async {
    await login(tester, '07 01 01 01 01');
    await waitFor(tester, find.text('Mon équipe'));
    await tester.tap(
      find.descendant(of: find.byType(AppNavBar), matching: find.text('Carte')),
    );
    await settle(tester, 2000);
    await shot(tester, '01-carte-equipe');
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await shot(tester, '02-zoom');
    await tester.tap(find.byIcon(Icons.zoom_out_map_rounded));
    await settle(tester, 1500);
    await tester.tap(find.text('AD').last);
    await settle(tester, 1500);
    await shot(tester, '03-fiche-agent');
    await tester.tapAt(const Offset(200, 300));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.layers_outlined));
    await settle(tester);
    await shot(tester, '04-options');
    await tester.tap(find.text('Sombre'));
    await tester.tapAt(const Offset(200, 120));
    await settle(tester);
    await shot(tester, '05-sombre');
    await tester.tap(find.byIcon(Icons.layers_outlined));
    await settle(tester);
    await tester.tap(find.text('Standard'));
    await settle(tester);
  });
}
