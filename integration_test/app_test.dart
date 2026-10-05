// Parcours complet de l'agent, sur un vrai appareil ou simulateur, contre l'API locale.
// Prérequis : API démarrée, données de démo fraîches (npm run seed -- --reset),
// localisation autorisée et simulée sur l'appareil.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/config.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/session.dart';
import 'package:suivi_agent/main.dart' as app;

final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

/// Attend qu'un élément apparaisse (appels réseau réels).
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

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.last);
  await tester.tap(finder.last);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  await binding.convertFlutterSurfaceToImage();
  await tester.pump();
  await binding.takeScreenshot(name);
}

Future<void> login(WidgetTester tester, String phone, String password) async {
  await waitFor(tester, find.text('Se connecter'));
  await tester.enterText(find.byType(TextFormField).at(0), phone);
  await tester.enterText(find.byType(TextFormField).at(1), password);
  await tester.tap(find.text('Se connecter'));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Vérification côté serveur, avec le compte administrateur.
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
  setUpAll(() async {
    // Départ propre : aucune session ni donnée locale d'un test précédent.
    await SessionStore().clear();
    (await SharedPreferences.getInstance()).clear();
    final db = AppDatabase();
    await db.wipe();
    await db.close();
  });

  testWidgets('journée complète d’un agent', (tester) async {
    app.main();
    await waitFor(tester, find.text('Connexion'));
    await shot(tester, '01-connexion');

    // Mauvais mot de passe
    await login(tester, '07 02 02 02 01', 'mauvais');
    await waitFor(tester, find.text('Email ou mot de passe incorrect'));

    // Connexion de l'agent (numéro + mot de passe) : l'app prend l'apparence de la structure.
    await login(tester, '07 02 02 02 01', 'Password123!');
    await waitFor(tester, find.text('Ma journée'));
    expect(
      find.text('Bonjour Koffi').evaluate().isNotEmpty ||
          find.text('Bonsoir Koffi').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.text('Démo Abidjan'), findsOneWidget);
    await waitFor(tester, find.textContaining('Bonne journée sur le terrain'));
    final primary = Theme.of(
      tester.element(find.text('Ma journée')),
    ).colorScheme.primary;
    expect(
      primary,
      const Color(0xFF0F766E),
      reason: 'couleur de la structure appliquée après connexion',
    );
    await shot(tester, '02-accueil');

    // Choix de la zone
    await tapText(tester, 'Choisir ma zone');
    await waitFor(tester, find.text('Plateau'));
    await shot(tester, '03-choix-zone');
    await tapText(tester, 'Plateau');
    await waitFor(tester, find.text('Zone Plateau confirmée'));
    await waitFor(tester, find.text('Démarrer ma journée'));

    // Démarrage : le suivi de position commence.
    await tapText(tester, 'Démarrer ma journée');
    await waitFor(tester, find.text('Journée en cours'));
    await waitFor(
      tester,
      find.textContaining('Position partagée'),
      timeout: const Duration(seconds: 40),
    );
    await shot(tester, '04-journee-en-cours');

    // La position arrive au serveur (envoi par lots).
    final admin = await adminApi();
    var located = false;
    for (var i = 0; i < 40 && !located; i++) {
      await tester.pump(const Duration(seconds: 1));
      final live = (await admin.get<List<dynamic>>('/live')).data!;
      located = live.any(
        (a) =>
            (a as Map)['agent']['firstName'] == 'Koffi' &&
            a['position'] != null,
      );
    }
    expect(
      located,
      isTrue,
      reason: 'la position de l’agent doit être visible sur la carte web',
    );

    // Pause puis reprise
    await tapText(tester, 'Pause');
    await waitFor(tester, find.text('En pause'));
    await shot(tester, '05-pause');
    await tapText(tester, 'Reprendre');
    await waitFor(tester, find.text('Journée en cours'));

    // Mission : formulaire généré à partir des champs du type « Prospection ».
    await tapText(tester, 'Missions');
    await waitFor(tester, find.text('50 visites cette semaine'));
    await shot(tester, '06-missions');
    await tapText(tester, '50 visites cette semaine');
    await tapText(tester, 'Nouveau formulaire');
    await waitFor(tester, find.text('Nom du commerce *'));
    await tapText(tester, 'Enregistrer');
    await waitFor(tester, find.text('Champ obligatoire'));
    await tester.enterText(find.byType(TextFormField).at(0), 'Boutique Awa');
    await tapText(tester, 'Oui');
    await tester.enterText(find.byType(TextFormField).at(1), '15 000');
    await tapText(tester, 'Boutique');
    await shot(tester, '07-formulaire');
    await tapText(tester, 'Enregistrer');
    await waitFor(tester, find.textContaining('Formulaire enregistré'));
    await waitFor(tester, find.text('Envoyé'));
    await waitFor(tester, find.text('1 / 50'));
    await shot(tester, '08-mission');

    // Fin de journée
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    await tapText(tester, 'Journée');
    await tapText(tester, 'Terminer');
    await waitFor(tester, find.text('Terminer la journée ?'));
    await tapText(tester, 'Terminer ma journée');
    await waitFor(tester, find.text('Journée terminée. Merci !'));
    await waitFor(tester, find.text('Journée non démarrée'));
    final days = (await admin.get<Map<String, dynamic>>(
      '/days',
      queryParameters: {'status': 'ended'},
    )).data!;
    expect(
      (days['items'] as List).any(
        (d) => (d as Map)['agent']['firstName'] == 'Koffi',
      ),
      isTrue,
    );

    // Déconnexion : retour à l'apparence neutre.
    await tapText(tester, 'Profil');
    await waitFor(tester, find.text('Koffi Brou'));
    await shot(tester, '09-profil');
    await tapText(tester, 'Se déconnecter');
    await tapText(tester, 'Se déconnecter');
    await waitFor(tester, find.text('Connexion'));
    final neutral = Theme.of(
      tester.element(find.text('Connexion')),
    ).colorScheme.primary;
    expect(neutral, const Color(0xFF2563EB));
  });

  testWidgets('chef d’équipe : suit son équipe et valide une demande', (
    tester,
  ) async {
    // Une demande en attente, créée par un agent de l'Équipe Nord.
    final admin = await adminApi();
    await admin.patch<dynamic>('/settings', data: {'approvalMode': 'manual'});
    final agent = Dio(BaseOptions(baseUrl: apiUrl));
    final tokens = await agent.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'phone': '0702020202', 'password': 'Password123!'},
    );
    agent.options.headers['Authorization'] =
        'Bearer ${tokens.data!['accessToken']}';
    final zones =
        (await agent.get<Map<String, dynamic>>(
              '/zones/available',
            )).data!['zones']
            as List;
    await agent.post<dynamic>(
      '/zone-requests',
      data: {'zoneId': (zones.first as Map)['id']},
    );

    app.main();
    await login(tester, '07 01 01 01 01', 'Password123!');
    await waitFor(tester, find.text('Mon équipe'));
    expect(find.text('Équipe'), findsWidgets);
    expect(find.text('Demandes'), findsOneWidget);
    expect(
      find.text('Journée'),
      findsNothing,
      reason: 'le chef n’a pas l’écran de journée des agents',
    );
    await waitFor(tester, find.text('Aminata Diallo'));
    await shot(tester, '10-chef-equipe');

    await tapText(tester, 'Demandes');
    await waitFor(tester, find.text('Valider'));
    await shot(tester, '11-chef-demandes');
    await tapText(tester, 'Valider');
    await waitFor(tester, find.text('Tout est à jour'));
    await admin.patch<dynamic>(
      '/settings',
      data: {'approvalMode': 'automatic'},
    );
  });
}
