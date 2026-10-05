// Carte « Ma zone » (zoom, styles avec les vraies tuiles) et « Ce que rapporte cette mission »,
// sur simulateur contre l'API locale (démo). Prérequis préparés par le script de lancement :
// journée ouverte pour Aminata Diallo (Plateau), rémunération propre sur « 120 visites cette
// semaine ». Le test annonce les positions (« LOC: ») et les captures (« SHOT: »).
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

/// Laisse charger les tuiles, puis capture.
Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, 3500);
  debugPrint('SHOT:$name');
  await settle(tester, 2500);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await waitFor(tester, f);
  await tester.tap(f.last);
  await settle(tester);
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

  testWidgets('agent : carte de sa zone et rémunération de la mission', (
    tester,
  ) async {
    debugPrint('LOC:5.3235,-4.0172');
    await settle(tester, 1500);
    app.main();
    await waitFor(tester, find.text('Se connecter'));
    await tester.enterText(find.byType(TextFormField).at(0), '07 02 02 02 02');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.tap(find.text('Se connecter'));
    await waitFor(tester, find.text('Dans votre zone'));
    await shot(tester, '01-journee');

    // Carte plein écran : zoom avant, arrière, puis chaque style.
    await tester.tap(find.text('Plateau').last);
    await settle(tester);
    await shot(tester, '02-ma-zone');
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await shot(tester, '03-zoom-avant');
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await shot(tester, '04-zoom-arriere');
    await tester.tap(find.byIcon(Icons.layers_outlined));
    await settle(tester);
    await shot(tester, '05-styles');
    for (final style in ['Sobre', 'Sombre', 'Humanitaire']) {
      await tapText(tester, style);
      await tester.tapAt(const Offset(200, 150));
      await settle(tester);
      await shot(tester, '06-style-${style.toLowerCase()}');
      await tester.tap(find.byIcon(Icons.layers_outlined));
      await settle(tester);
    }
    await tapText(tester, 'Standard');
    await tester.tapAt(const Offset(200, 150));
    await settle(tester);
    await tester.tap(find.byType(BackButton));
    await settle(tester);

    // Mission de l'équipe avec rémunération propre.
    await tester.tap(
      find.descendant(
        of: find.byType(AppNavBar),
        matching: find.text('Missions'),
      ),
    );
    await settle(tester);
    if (find.text('120 visites cette semaine').evaluate().isEmpty) {
      final done = find.textContaining('Terminées');
      await waitFor(tester, done);
      await tester.tap(done.first);
      await settle(tester);
    }
    await tapText(tester, '120 visites cette semaine');
    await settle(tester, 2000);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await waitFor(tester, find.text('CE QUE RAPPORTE CETTE MISSION'));
    await shot(tester, '07-ce-que-rapporte');
    expect(find.text('Par formulaire accepté'), findsOneWidget);
  });
}
