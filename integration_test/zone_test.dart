// Sortie de zone sur simulateur, contre l'API locale (données de démo) : l'agent
// Aminata Diallo (zone Plateau) a une journée ouverte. Le test annonce les positions à
// simuler (« LOC:lat,lng ») et les captures (« SHOT:nom ») ; un script externe s'en charge.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/config.dart';
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
  await settle(tester, 2500);
  debugPrint('SHOT:$name');
  await settle(tester, 2500);
}

Future<void> moveTo(WidgetTester tester, double lat, double lng) async {
  debugPrint('LOC:$lat,$lng');
  await settle(tester, 1500);
}

Future<Dio> agentApi() async {
  final dio = Dio(BaseOptions(baseUrl: apiUrl));
  final res = await dio.post<Map<String, dynamic>>(
    '/auth/login',
    data: {'phone': '0702020202', 'password': 'Password123!'},
  );
  dio.options.headers['Authorization'] = 'Bearer ${res.data!['accessToken']}';
  return dio;
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

  testWidgets('agent : sortie de zone puis retour', (tester) async {
    // Au cœur du Plateau avant l'ouverture de l'app.
    await moveTo(tester, 5.3205, -4.0215);
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
    await tester.enterText(find.byType(TextFormField).at(0), '07 02 02 02 02');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.tap(find.text('Se connecter'));
    await waitFor(tester, find.text('MA ZONE'));
    await waitFor(tester, find.text('Dans votre zone'));
    await shot(tester, '01-dans-la-zone');

    // 600 m à l'est du Plateau, de l'autre côté de la lagune.
    await moveTo(tester, 5.3225, -4.0045);
    await waitFor(tester, find.textContaining('Hors de Plateau'));
    await shot(tester, '02-hors-zone');

    await tester.tap(find.text('Voir'));
    await settle(tester);
    await shot(tester, '03-ma-zone');
    await tester.tap(find.byType(BackButton));
    await settle(tester);

    // Retour au centre de la zone.
    await moveTo(tester, 5.3205, -4.0215);
    await waitFor(tester, find.text('Dans votre zone'));
    expect(find.textContaining('Hors de Plateau'), findsNothing);
    await shot(tester, '04-retour');

    // Les positions partent au serveur : la sortie y est close (retour).
    final api = await agentApi();
    final day =
        (await api.get<Map<String, dynamic>>('/days/current')).data!['day']
            as Map<String, dynamic>;
    final end = DateTime.now().add(const Duration(seconds: 60));
    List<dynamic> exits = [];
    while (DateTime.now().isBefore(end)) {
      await settle(tester, 2000);
      exits = (await api.get<List<dynamic>>(
        '/days/${day['id']}/zone-exits',
      )).data!;
      if (exits.isNotEmpty &&
          exits.every((e) => (e as Map)['endedAt'] != null)) {
        break;
      }
    }
    debugPrint('VERIF:${exits.map((e) => (e as Map)['endReason']).toList()}');
    expect(exits, isNotEmpty);
    expect(exits.every((e) => (e as Map)['endReason'] == 'returned'), isTrue);
  });
}
