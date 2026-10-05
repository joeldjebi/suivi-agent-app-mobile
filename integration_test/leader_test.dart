// Parcours du chef d'équipe sur simulateur, contre l'API locale (données de démo) :
// créer une mission, la gérer, proposer une prime sur la paie à valider.
// Chaque étape affiche « SHOT:nom » puis marque une pause, pour une capture externe.
// Ce que le test crée est supprimé à la fin avec le compte administrateur.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/config.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/session.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/main.dart' as app;

const title = 'Test simulateur – 30 visites';

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
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

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.last);
  await tester.pump();
  await tester.tap(finder.last);
  await settle(tester);
}

Future<void> tapNav(WidgetTester tester, String label) async {
  final finder = find.descendant(
    of: find.byType(AppNavBar),
    matching: find.text(label),
  );
  await waitFor(tester, finder);
  await tester.tap(finder.last);
  await settle(tester);
}

/// Annonce l'étape et laisse 3 s à la capture d'écran externe.
Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, 800);
  debugPrint('SHOT:$name');
  await settle(tester, 3000);
}

Future<Dio> adminApi() async {
  final dio = Dio(BaseOptions(baseUrl: apiUrl));
  final res = await dio.post<Map<String, dynamic>>(
    '/auth/login',
    data: {'email': 'admin@demo.ci', 'password': 'Password123!'},
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
    // Restes d'un essai interrompu.
    final admin = await adminApi();
    final items =
        ((await admin.get<Map<String, dynamic>>(
                  '/missions',
                  queryParameters: {'limit': 100, 'includeInactive': true},
                )).data!['items']
                as List)
            .cast<Map<String, dynamic>>();
    for (final m in items.where((m) => m['title'] == title)) {
      await admin.delete<void>('/missions/${m['id']}');
    }
  });

  testWidgets('chef d’équipe : missions et paie', (tester) async {
    app.main();
    await waitFor(tester, find.text('Se connecter'));
    await tester.enterText(find.byType(TextFormField).at(0), '07 01 01 01 01');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.tap(find.text('Se connecter'));
    await waitFor(tester, find.text('Mon équipe'));
    await settle(tester);

    // 1. Création d'une mission
    await tapNav(tester, 'Missions');
    await shot(tester, '01-missions');
    await tapText(tester, 'Nouvelle mission');
    await shot(tester, '02-formulaire-vide');

    // Envoi sans les champs requis : refusé, avec les erreurs.
    await tapText(tester, 'Créer');
    await shot(tester, '03-formulaire-erreurs');

    await tester.enterText(find.byType(TextFormField).first, title);
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Visiter 30 boutiques et remplir le formulaire.',
    );
    await tapText(tester, 'Type');
    await shot(tester, '04-choix-type');
    await tapText(tester, 'Prospection');
    await tapText(tester, 'Groupe');
    await shot(tester, '05-choix-groupe');
    final group = [
      'Équipe Nord',
      'Équipe Sud',
      'Équipe Centre',
    ].firstWhere((g) => find.text(g).evaluate().isNotEmpty);
    await tapText(tester, group);
    final target = find.ancestor(
      of: find.text('Formulaires'),
      matching: find.byType(Row),
    );
    await tester.ensureVisible(target.first);
    await tester.enterText(
      find.descendant(of: target.first, matching: find.byType(TextField)),
      '30',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Donnez un titre'), findsNothing);
    expect(find.text('Indiquez une cible positive'), findsNothing);
    await shot(tester, '06-formulaire-rempli');
    await tapText(tester, 'Créer');
    await waitFor(tester, find.text(title));
    await shot(tester, '07-mission-creee');

    // 2. Gestion : modifier la cible puis désactiver
    await tester.tap(find.byTooltip('Gérer la mission'));
    await settle(tester);
    await shot(tester, '08-menu-gestion');
    await tapText(tester, 'Modifier');
    await shot(tester, '09-modifier');
    final editTarget = find.ancestor(
      of: find.text('Formulaires'),
      matching: find.byType(Row),
    );
    await tester.ensureVisible(editTarget.first);
    await tester.enterText(
      find.descendant(of: editTarget.first, matching: find.byType(TextField)),
      '35',
    );
    await settle(tester);
    await tapText(tester, 'Enregistrer');
    await waitFor(tester, find.text('35'));
    await shot(tester, '10-cible-modifiee');
    await tester.tap(find.byTooltip('Gérer la mission'));
    await settle(tester);
    await tapText(tester, 'Désactiver');
    await waitFor(tester, find.textContaining('DÉSACTIVÉE'));
    await shot(tester, '11-desactivee');

    // 3. Paie à valider : proposer une prime
    await tapNav(tester, 'Profil');
    await tapText(tester, 'Gains de l’équipe');
    await waitFor(tester, find.textContaining('À VALIDER'));
    await tester.ensureVisible(find.textContaining('À VALIDER'));
    await settle(tester);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
    await settle(tester);
    await shot(tester, '12-paie-a-valider');
    await tapText(tester, 'Proposer');
    await shot(tester, '13-feuille-prime');
    await tester.enterText(find.widgetWithText(TextField, 'Montant'), '5000');
    await tester.enterText(
      find.widgetWithText(TextField, 'Motif (vu par l’agent)'),
      'Test simulateur',
    );
    await settle(tester);
    await tapText(tester, 'Proposer la prime');
    await settle(tester, 2000);
    await shot(tester, '14-prime-proposee');

    // Vérification côté serveur, puis nettoyage.
    final admin = await adminApi();
    final missions =
        ((await admin.get<Map<String, dynamic>>(
                  '/missions',
                  queryParameters: {'limit': 100, 'includeInactive': true},
                )).data!['items']
                as List)
            .cast<Map<String, dynamic>>();
    final created = missions.firstWhere((m) => m['title'] == title);
    expect(created['isActive'], false);
    expect(num.parse('${created['targetValue']}'), 35);
    final runs = (await admin.get<List<dynamic>>('/pay/runs')).data!;
    final draft = runs.cast<Map<String, dynamic>>().firstWhere(
      (r) => r['status'] == 'draft',
    );
    final run = (await admin.get<Map<String, dynamic>>(
      '/pay/runs/${draft['id']}',
    )).data!;
    final adjustment = (run['adjustments'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((a) => a['reason'] == 'Test simulateur');
    expect(num.parse('${adjustment['amount']}'), 5000);
    debugPrint('VERIF:mission ${created['id']} adj ${adjustment['id']}');
    await admin.delete<void>('/missions/${created['id']}');
    await admin.delete<void>('/pay/adjustments/${adjustment['id']}');
  });
}
