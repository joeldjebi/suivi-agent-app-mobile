import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/core/api_client.dart';
import 'package:suivi_agent/core/models.dart';
import 'package:suivi_agent/core/providers.dart';
import 'package:suivi_agent/app.dart';
import 'package:suivi_agent/features/team/map_options.dart';

import 'package:suivi_agent/widgets/form_rows.dart';

import 'fakes.dart';
import 'package:drift/drift.dart' show Value;
import 'package:suivi_agent/core/database.dart';

/// Écran de téléphone (390 × 844) : la mise en page réelle, pas une fenêtre 800 × 600.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump();
  await tester.tap(find.text(text));
  await _settle(tester);
}

/// Segment d'un sélecteur (onglets d'une mission), par son libellé.
Finder _segment(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AppSegmented),
  matching: find.text(label),
);

Future<void> _tapSegment(WidgetTester tester, String label) async {
  await tester.tap(_segment(label));
  await _settle(tester);
}

/// Onglet de la barre de navigation, par son libellé.
Finder _tab(String label) =>
    find.descendant(of: find.byType(AppNavBar), matching: find.text(label));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    // Chaque test ouvre sa propre base en mémoire : c'est voulu.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('connexion : numéro et mot de passe, erreurs lisibles', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(testApp(auth: SignedOutAuth.new));
    await _settle(tester);

    expect(find.text('Numéro de téléphone'), findsOneWidget);
    expect(
      find.textContaining('Créer'),
      findsNothing,
      reason: 'pas de création de compte dans l’app',
    );

    await _tapText(tester, 'Se connecter');
    expect(find.text('Saisissez votre numéro de téléphone'), findsOneWidget);
    expect(find.text('Saisissez votre mot de passe'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), '0707070707');
    expect(find.text('07 07 07 07 07'), findsOneWidget);
  });

  testWidgets('connexion refusée : message du serveur affiché', (tester) async {
    _phone(tester);
    final repo = FakeRepository()
      ..loginError = ApiException(
        'Email ou mot de passe incorrect',
        status: 401,
      );
    await tester.pumpWidget(testApp(auth: SignedOutAuth.new, repo: repo));
    await _settle(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '0707070707');
    await tester.enterText(find.byType(TextFormField).at(1), 'faux');
    await _tapText(tester, 'Se connecter');
    expect(find.text('Email ou mot de passe incorrect'), findsOneWidget);
  });

  testWidgets(
    'agent : journée, missions, profil, aux couleurs de la structure',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
      await _settle(tester);

      expect(find.text('Ma journée'), findsOneWidget);
      expect(find.text('Démo Abidjan'), findsWidgets);
      // Le message d'accueil est plus bas : on fait défiler jusqu'à lui.
      await tester.scrollUntilVisible(
        find.text('Bonne journée sur le terrain !'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Bonne journée sur le terrain !'), findsOneWidget);
      expect(find.text('Choisir ma zone'), findsOneWidget);
      for (final tab in ['Journée', 'Missions', 'Profil']) {
        expect(_tab(tab), findsOneWidget);
      }
      expect(_tab('Demandes'), findsNothing);
      final primary = Theme.of(
        tester.element(find.text('Ma journée')),
      ).colorScheme.primary;
      expect(primary, const Color(0xFF0F766E));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('chef d’équipe : équipe, demandes, missions, profil', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
    );
    await _settle(tester);

    expect(find.text('Mon équipe'), findsOneWidget);
    expect(
      _tab('Journée'),
      findsNothing,
      reason: 'pas d’écran de journée pour le chef',
    );
    expect(_tab('Demandes'), findsOneWidget);
    // Alerte en tête : Aminata est hors de sa zone.
    expect(find.text('À SURVEILLER'), findsOneWidget);
    expect(find.text('Hors zone · 12 min'), findsOneWidget);
    expect(find.text('Serge Gbagbo'), findsOneWidget);
    expect(find.text('1 demande de zone à valider'), findsOneWidget);

    await tester.tap(_tab('Demandes'));
    await _settle(tester);
    expect(find.text('Serge Gbagbo'), findsOneWidget);
    expect(find.text('Valider'), findsOneWidget);
    expect(find.textContaining('Zone Cocody'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'notifications : marquées lues en quittant l’écran, sans erreur',
    (tester) async {
      _phone(tester);
      final repo = FakeRepository();
      await tester.pumpWidget(
        testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      );
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await _settle(tester);
      expect(find.text('Notifications'), findsWidgets);

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(repo.markAllReadCalls, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'déconnexion depuis le profil : retour à la connexion, sans erreur',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
      await _settle(tester);
      await tester.tap(_tab('Profil'));
      await _settle(tester);
      await tester.scrollUntilVisible(
        find.text('Se déconnecter'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await _tapText(tester, 'Se déconnecter');
      await tester.tap(find.text('Se déconnecter').last);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Numéro de téléphone'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('chef : feuille de refus ouverte puis fermée, sans erreur', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
    );
    await _settle(tester);
    await tester.tap(_tab('Demandes'));
    await _settle(tester);
    await tester.tap(find.text('Refuser'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Zone pleine');
    await _tapText(tester, 'Annuler');
    expect(tester.takeException(), isNull);
    expect(find.text('Refuser la demande'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chef : carte de l’équipe, fiche agent et itinéraire du jour', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
    );
    await _settle(tester);
    await tester.tap(_tab('Carte'));
    await _settle(tester);

    expect(find.textContaining('3 en journée'), findsOneWidget);
    expect(find.textContaining('1 alerte'), findsOneWidget);
    expect(find.text('Agents en journée'), findsOneWidget);
    // Les alertes passent en tête de liste.
    expect(find.text('Hors zone · 12 min'), findsOneWidget);

    // Zoom avant et arrière par les boutons.
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final before = map.mapController!.camera.zoom;
    await tester.tap(find.byIcon(Icons.add_rounded));
    await _settle(tester);
    expect(map.mapController!.camera.zoom, before + 1);
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await _settle(tester);
    expect(map.mapController!.camera.zoom, before);

    await _tapText(tester, 'Koffi Brou');
    expect(find.text('Itinéraire du jour'), findsOneWidget);
    expect(find.text('Agents en journée'), findsNothing);

    await _tapText(tester, 'Itinéraire du jour');
    expect(find.text('Distance parcourue'), findsOneWidget);
    expect(find.text('Masquer le trajet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await _settle(tester);
    expect(find.text('Agents en journée'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chef : style et options de la carte', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
    );
    await _settle(tester);
    await tester.tap(_tab('Carte'));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.layers_outlined));
    await _settle(tester);
    expect(find.text('Sombre'), findsOneWidget);
    expect(find.text('Humanitaire'), findsOneWidget);

    await tester.tap(find.text('Sombre'));
    await _tapText(tester, 'Alertes seulement');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('map.style'), 'sombre');
    expect(prefs.getBool('map.alerts'), isTrue);

    // Fermeture du panneau : seule l'agente en alerte reste listée.
    await tester.tapAt(const Offset(200, 60));
    await _settle(tester);
    expect(find.text('Alertes'), findsOneWidget);
    expect(find.text('Aminata Diallo'), findsOneWidget);
    expect(find.text('Koffi Brou'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chef : onglets de la mission, jours en accordéon, filtres', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
        repo: repo,
      ),
    );
    await _settle(tester);
    await tester.tap(_tab('Missions'));
    await _settle(tester);
    await _tapText(tester, '120 visites cette semaine');

    // Aperçu par défaut.
    expect(_segment('Aperçu'), findsOneWidget);
    expect(find.text('DÉTAILS'), findsOneWidget);
    expect(find.text('Boutique Awa'), findsNothing);

    // Équipe : contributions, du plus au moins contributif.
    await _tapSegment(tester, 'Équipe');
    expect(find.text('CONTRIBUTIONS'), findsOneWidget);
    expect(find.text('Koffi Brou'), findsOneWidget);

    // Formulaires : aujourd'hui ouvert, les autres jours fermés.
    await _tapSegment(tester, 'Formulaires');
    expect(find.text('5 formulaires'), findsOneWidget);
    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.text('Hier'), findsOneWidget);
    expect(find.text('Boutique Awa'), findsOneWidget);
    expect(find.text('Pharmacie du Marché'), findsNothing);

    await _tapText(tester, 'Hier');
    expect(find.text('Pharmacie du Marché'), findsOneWidget);
    await _tapText(tester, 'Hier');
    expect(find.text('Pharmacie du Marché'), findsNothing);
    await _tapText(tester, 'Tout ouvrir');
    // Le dernier jour est plus bas : on fait défiler jusqu'à lui.
    await tester.scrollUntilVisible(
      find.text('Maquis Chez Tanti'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Maquis Chez Tanti'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tout fermer'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapText(tester, 'Tout fermer');
    expect(find.text('Boutique Awa'), findsNothing);

    // Fiche complète d'un formulaire, avec le rejet.
    await _tapText(tester, 'Aujourd’hui');
    await _tapText(tester, 'Boutique Awa');
    expect(find.text('Nom du commerce'), findsOneWidget);
    expect(find.text('Rejeter ce formulaire'), findsOneWidget);
    await tester.tapAt(const Offset(200, 40));
    await _settle(tester);

    // Statut : rejetés → les jours trouvés s'ouvrent.
    await tester.scrollUntilVisible(
      find.text('Tous les statuts'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapText(tester, 'Tous les statuts');
    await tester.tap(find.text('Rejetés').last);
    await _settle(tester);
    expect(repo.submissionQueries.last.rejected, isTrue);
    expect(find.text('Pharmacie du Marché'), findsOneWidget);
    expect(find.text('Boutique Awa'), findsNothing);

    // Période : aujourd'hui → aucun rejet.
    await _tapText(tester, 'Toute la période');
    await tester.tap(find.text('Aujourd’hui').last);
    await _settle(tester);
    expect(find.text('Aucun formulaire pour ces filtres.'), findsOneWidget);
    await _tapText(tester, 'Effacer les filtres');
    expect(find.text('5 formulaires'), findsOneWidget);

    // Équipe → toucher un agent ouvre ses formulaires.
    await _tapSegment(tester, 'Équipe');
    await _tapText(tester, 'Aminata Diallo');
    expect(repo.submissionQueries.last.agentId, 'a2');
    expect(find.text('2 formulaires'), findsOneWidget);
    expect(find.text('Garage Yao'), findsOneWidget);
    expect(find.text('Boutique Awa'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('agent : sa contribution, jamais celles de ses collègues', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
    await _settle(tester);
    await tester.tap(_tab('Missions'));
    await _settle(tester);
    await _tapText(tester, '120 visites cette semaine');

    expect(_segment('Aperçu'), findsOneWidget);
    expect(_segment('Mes formulaires'), findsOneWidget);
    expect(_segment('Équipe'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('MA CONTRIBUTION'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('45'), findsOneWidget);
    expect(find.text('58 % de la progression de l’équipe'), findsOneWidget);
    expect(find.text('Aminata Diallo'), findsNothing);
    expect(find.text('Koffi Brou'), findsNothing);

    // Ce que rapporte la mission : paliers du plus haut au plus bas.
    await tester.scrollUntilVisible(
      find.text('CE QUE RAPPORTE CETTE MISSION'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Par formulaire accepté'), findsOneWidget);
    expect(find.text('Commission'), findsNothing);
    final tiers = tester
        .widgetList<Text>(find.textContaining('Prime à'))
        .map((t) => t.data)
        .toList();
    expect(tiers, [
      'Prime à 100 % de l’objectif',
      'Prime à 80 % de l’objectif',
    ]);
    expect(
      find.textContaining('Conditions propres à cette mission'),
      findsOneWidget,
    );

    // Ses formulaires : pas de filtres d'équipe.
    await _tapSegment(tester, 'Mes formulaires');
    expect(find.text('Tous les agents'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'profil : informations, mot de passe, apparence ; numéro non modifiable',
    (tester) async {
      _phone(tester);
      final repo = FakeRepository();
      await tester.pumpWidget(
        testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      );
      await _settle(tester);
      await tester.tap(_tab('Profil'));
      await _settle(tester);
      expect(find.text('MON COMPTE'), findsOneWidget);

      // Informations personnelles.
      await _tapText(tester, 'Informations personnelles');
      await tester.enterText(find.byType(TextFormField).at(0), 'Koffi Junior');
      await _tapText(tester, 'Enregistrer');
      expect(repo.profile['firstName'], 'Koffi Junior');
      await tester.scrollUntilVisible(
        find.text('Koffi Junior Brou'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Koffi Junior Brou'), findsOneWidget);

      // Téléphone : affiché, mais pas modifiable (identifiant de connexion).
      await tester.tap(find.text('Téléphone'));
      await _settle(tester);
      expect(find.text('MON COMPTE'), findsOneWidget);
      expect(find.text('Enregistrer'), findsNothing);

      // Mot de passe : règles affichées, saisies différentes refusées.
      await _tapText(tester, 'Mot de passe');
      await tester.enterText(find.byType(TextFormField).at(0), 'Password123!');
      await tester.enterText(find.byType(TextFormField).at(1), 'court');
      await tester.enterText(find.byType(TextFormField).at(2), 'autre');
      await _tapText(tester, 'Enregistrer');
      expect(find.text('8 caractères minimum'), findsWidgets);
      expect(repo.passwordChanges, isEmpty);
      await tester.enterText(find.byType(TextFormField).at(1), 'Nouveau2026!');
      await tester.enterText(find.byType(TextFormField).at(2), 'Nouveau2026!');
      await _tapText(tester, 'Enregistrer');
      expect(repo.passwordChanges.single, ('Password123!', 'Nouveau2026!'));
      expect(find.text('MON COMPTE'), findsOneWidget);

      // Apparence : sombre (après la disparition du message de confirmation).
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);
      await _tapText(tester, 'Apparence');
      await tester.tap(find.text('Sombre').last);
      await _settle(tester);
      expect(
        Theme.of(tester.element(find.text('Apparence').first)).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('formule sans missions : pas d’onglet Missions', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      testApp(auth: () => SignedInAuth(fakeMe(features: const {}))),
    );
    await _settle(tester);
    expect(_tab('Journée'), findsOneWidget);
    expect(_tab('Profil'), findsOneWidget);
    expect(_tab('Missions'), findsNothing);
    await tester.tap(_tab('Profil'));
    await _settle(tester);
    expect(find.text('MON COMPTE'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('abonnement suspendu : l’app est bloquée', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(subscriptionStatus: 'suspended')),
      ),
    );
    await _settle(tester);
    expect(find.text('Accès suspendu'), findsOneWidget);
    expect(find.byType(AppNavBar), findsNothing);
    expect(find.text('Se déconnecter'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('rémunération : mes gains, reçu et gains de l’équipe', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(
          fakeMe(
            role: 'team_lead',
            first: 'Yao',
            features: const {'missions', 'payroll'},
          ),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(_tab('Profil'));
    await _settle(tester);
    expect(find.text('RÉMUNÉRATION'), findsOneWidget);
    // Estimation en direct dans la ligne du profil.
    expect(find.text('58\u202f300\u00a0FCFA'), findsOneWidget);

    await tester.tap(find.text('Mes gains'));
    await _settle(tester);
    expect(find.text('Total estimé'), findsOneWidget);
    expect(find.text('3 × 2\u202f500\u00a0FCFA'), findsOneWidget);
    expect(find.text('-1\u202f000\u00a0FCFA'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Août 2026'), 200);
    // Au-dessus de la barre d'onglets.
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await _settle(tester);
    expect(find.text('Validée, en attente de paiement'), findsOneWidget);
    await tester.tap(find.text('Août 2026'));
    await _settle(tester);
    expect(find.text('Paie de août 2026'), findsOneWidget);
    expect(find.text('OM-58213'), findsOneWidget);
    await tester.tapAt(const Offset(200, 40));
    await _settle(tester);

    await tester.tap(find.byType(BackButton));
    await _settle(tester);
    await tester.tap(find.text('Gains de l’équipe'));
    await _settle(tester);
    // Le chef n'apparaît pas parmi ses agents ; l'agent sans grille est signalé.
    expect(find.text('Yao Brou'), findsNothing);
    expect(find.text('Aminata Diallo'), findsWidgets);
    expect(find.text('Sans grille'), findsOneWidget);
    expect(find.textContaining('pas de grille'), findsOneWidget);
    await tester.tap(find.text('Aminata Diallo').first);
    await _settle(tester);
    expect(find.text('Détail estimé'.toUpperCase()), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('formule sans rémunération : pas de « Mes gains »', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
    await _settle(tester);
    await tester.tap(_tab('Profil'));
    await _settle(tester);
    expect(find.text('MON COMPTE'), findsOneWidget);
    expect(find.text('Mes gains'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'formule changée par l’éditeur : l’app s’adapte au retour, sans reconnexion',
    (tester) async {
      _phone(tester);
      final repo = FakeRepository();
      await tester.pumpWidget(
        testApp(
          auth: () =>
              SignedInAuth(fakeMe(features: const {'missions', 'payroll'})),
          repo: repo,
        ),
      );
      await _settle(tester);
      expect(_tab('Missions'), findsOneWidget);
      await tester.tap(_tab('Profil'));
      await _settle(tester);
      expect(find.text('Mes gains'), findsOneWidget);

      // L'éditeur passe la structure sur une formule sans missions ni rémunération.
      repo.meResponse = meJsonWith(features: const []);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(_tab('Missions'), findsNothing);
      expect(find.text('Mes gains'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'abonnement suspendu pendant l’utilisation : l’app se bloque au retour',
    (tester) async {
      _phone(tester);
      final repo = FakeRepository();
      await tester.pumpWidget(
        testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      );
      await _settle(tester);
      expect(find.byType(AppNavBar), findsOneWidget);
      repo.meResponse = meJsonWith(features: const [], status: 'suspended');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(find.text('Accès suspendu'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('chef : crée une mission pour son groupe', (tester) async {
    _phone(tester);
    final repo = FakeRepository();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
        repo: repo,
      ),
    );
    await _settle(tester);
    await tester.tap(_tab('Missions'));
    await _settle(tester);
    await tester.tap(find.text('Nouvelle mission'));
    await _settle(tester);
    expect(find.text('Créer'), findsOneWidget);

    // Champs manquants : la mission n'est pas envoyée.
    await tester.tap(find.text('Créer'));
    await _settle(tester);
    expect(repo.createdMissions, isEmpty);

    await tester.enterText(
      find.byType(TextFormField).first,
      '40 visites au Plateau',
    );
    await tester.tap(find.text('Type'));
    await _settle(tester);
    await tester.tap(find.text('Visite commerciale').last);
    await _settle(tester);
    await tester.tap(find.text('Groupe'));
    await _settle(tester);
    await tester.tap(find.text('Équipe Nord').last);
    await _settle(tester);
    // Où : au moins une zone (celles du chef).
    final plateau = find.widgetWithText(FilterChip, 'Plateau');
    await tester.scrollUntilVisible(
      plateau,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(plateau);
    await _settle(tester);
    final target = find.widgetWithText(FieldRow, 'Formulaires');
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.descendant(of: target, matching: find.byType(TextFormField)),
      '40',
    );
    await tester.tap(find.text('Créer'));
    await _settle(tester);
    expect(repo.createdMissions, hasLength(1));
    expect(
      repo.createdMissions.single,
      containsPair('title', '40 visites au Plateau'),
    );
    expect(repo.createdMissions.single, containsPair('typeId', 't1'));
    expect(repo.createdMissions.single, containsPair('assigneeGroupId', 'g1'));
    expect(
      repo.createdMissions.single,
      containsPair('progressMethod', 'count'),
    );
    expect(repo.createdMissions.single, containsPair('targetValue', 40.0));
    expect(repo.createdMissions.single['zoneIds'], ['z1']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chef : désactive une mission depuis son détail', (tester) async {
    _phone(tester);
    final repo = FakeRepository();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
        repo: repo,
      ),
    );
    await _settle(tester);
    await tester.tap(_tab('Missions'));
    await _settle(tester);
    await _tapText(tester, '120 visites cette semaine');
    await tester.tap(find.byTooltip('Gérer la mission'));
    await _settle(tester);
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Supprimer la mission'), findsOneWidget);
    await tester.tap(find.text('Désactiver'));
    await _settle(tester);
    expect(repo.missionUpdates.single.$1, 'm1');
    expect(repo.missionUpdates.single.$2, {'isActive': false});

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chef : propose une prime sur la paie à valider', (tester) async {
    _phone(tester);
    final repo = FakeRepository();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(
          fakeMe(
            role: 'team_lead',
            first: 'Yao',
            features: const {'missions', 'payroll'},
          ),
        ),
        repo: repo,
      ),
    );
    await _settle(tester);
    await tester.tap(_tab('Profil'));
    await _settle(tester);
    await tester.tap(find.text('Gains de l’équipe'));
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.text('PAIE DE SEPTEMBRE 2026 · À VALIDER'),
      200,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await _settle(tester);
    await tester.tap(find.text('Koffi Brou').last);
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Montant'), '5000');
    await tester.enterText(
      find.widgetWithText(TextField, 'Motif (vu par l’agent)'),
      'Meilleur résultat',
    );
    await tester.pump();
    await tester.tap(find.text('Proposer la prime'));
    await _settle(tester);
    expect(repo.proposals.single, ('a2', 5000, 'Meilleur résultat'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('agent : ma zone sur la carte, alerte de sortie puis retour', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository()
      ..day = DayState(
        day: WorkDay(
          id: 'd1',
          status: DayStatus.active,
          zoneId: 'z1',
          startedAt: DateTime.now().subtract(const Duration(hours: 1)),
          endedAt: null,
          pausedSeconds: 0,
          currentPauseStartedAt: null,
        ),
        approved: ZoneRequest(
          id: 'r1',
          zoneId: 'z1',
          status: RequestStatus.approved,
          expiresAt: null,
          isChange: false,
        ),
      );
    final alerts = FakeAlerts();
    await tester.pumpWidget(
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo, alerts: alerts),
    );
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SuiviAgentApp)),
    );
    final tracker = container.read(trackerProvider) as FakeTracker;

    expect(find.text('MA ZONE'), findsOneWidget);
    expect(find.text('Position en attente'), findsOneWidget);

    tracker.emit(const LatLng(5.32, -4.02));
    await _settle(tester);
    expect(find.text('Dans votre zone'), findsOneWidget);

    // Sortie franche : bandeau en haut, carte en rouge, alerte du téléphone.
    tracker.emit(eastOfPlateau(450));
    await _settle(tester);
    expect(find.textContaining('Hors de Plateau depuis 1 min'), findsOneWidget);
    expect(find.text('Hors zone depuis 1 min'), findsOneWidget);
    expect(alerts.shown.single.$1, 'Vous êtes hors de votre zone');

    await tester.tap(find.text('Voir'));
    await _settle(tester);
    expect(find.byType(FlutterMap), findsOneWidget);
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await _settle(tester);
    await tester.tap(find.byType(BackButton));
    await _settle(tester);

    tracker.emit(const LatLng(5.32, -4.02));
    await _settle(tester);
    expect(find.textContaining('Hors de Plateau'), findsNothing);
    expect(alerts.shown.last.$1, 'De retour dans votre zone');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chef : durée de la sortie de zone dans l’équipe', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
    );
    await _settle(tester);
    expect(find.text('Hors zone · 12 min'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('agent : carte de sa zone, zoom et style', (tester) async {
    _phone(tester);
    final repo = FakeRepository()
      ..day = DayState(
        day: WorkDay(
          id: 'd1',
          status: DayStatus.active,
          zoneId: 'z1',
          startedAt: DateTime.now().subtract(const Duration(hours: 1)),
          endedAt: null,
          pausedSeconds: 0,
          currentPauseStartedAt: null,
        ),
        approved: ZoneRequest(
          id: 'r1',
          zoneId: 'z1',
          status: RequestStatus.approved,
          expiresAt: null,
          isChange: false,
        ),
      );
    await tester.pumpWidget(
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
    );
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SuiviAgentApp)),
    );
    (container.read(trackerProvider) as FakeTracker).emit(
      const LatLng(5.32, -4.02),
    );
    await _settle(tester);
    await tester.tap(find.text('Plateau').last);
    await _settle(tester);

    final map = MapController.maybeOf(
      tester.element(find.byType(MarkerLayer)),
    )!;
    final before = map.camera.zoom;
    await tester.tap(find.byIcon(Icons.add_rounded));
    await _settle(tester);
    expect(map.camera.zoom, closeTo(before + 1, 0.01));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await _settle(tester);
    expect(map.camera.zoom, closeTo(before - 1, 0.01));

    // Style seulement : pas d'options de la carte d'équipe.
    await tester.tap(find.byIcon(Icons.layers_outlined));
    await _settle(tester);
    expect(find.text('STYLE'), findsOneWidget);
    expect(find.text('Noms des agents'), findsNothing);
    await tester.tap(find.text('Sombre'));
    await _settle(tester);
    expect(container.read(mapPrefsProvider).chosenStyle, MapStyle.sombre);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chef : centre d’alertes, prise en charge et historique', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
        repo: repo,
      ),
    );
    await _settle(tester);
    final tile = find.ancestor(
      of: find.text('Alertes'),
      matching: find.byType(SurfaceCard),
    );
    expect(find.descendant(of: tile, matching: find.text('4')), findsOneWidget);
    await tester.tap(tile);
    await _settle(tester);

    // Une carte par agent : Aminata a deux alertes, en pastilles.
    expect(
      find.text('3 agents à surveiller · 1 pris en charge'),
      findsOneWidget,
    );
    expect(find.text('Hors zone · 420 m'), findsOneWidget);
    expect(find.text('Batterie 12 %'), findsOneWidget);
    expect(find.text('Pas démarrée'), findsOneWidget);
    expect(find.textContaining('Yao Kouassi s’en occupe'), findsOneWidget);

    // Détail d'Aminata : je m'en occupe, pour ses deux alertes.
    await tester.tap(find.text('Aminata Diallo'));
    await _settle(tester);
    expect(
      find.textContaining('Hors de Plateau, jusqu’à 420 m'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField).last,
      'Appelée, elle revient',
    );
    await tester.tap(find.text('Je m’en occupe'));
    await _settle(tester);
    expect(repo.acknowledged, [
      ('al1', 'Appelée, elle revient'),
      ('al5', 'Appelée, elle revient'),
    ]);

    await _tapSegment(tester, 'Refermées');
    expect(find.text('Jean-Marc Aka'), findsOneWidget);
    expect(find.text('Batterie 12 %'), findsOneWidget);
    await tester.tap(find.text('Jean-Marc Aka'));
    await _settle(tester);
    expect(find.text('40 min'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chef : bilan du jour et message à l’équipe', (tester) async {
    _phone(tester);
    final repo = FakeRepository();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
        repo: repo,
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Bilan du jour'));
    await _settle(tester);

    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.text(' / 3'), findsOneWidget);
    expect(find.text('13 h 10'), findsOneWidget);
    expect(find.text('1 en retard'), findsOneWidget);
    expect(find.text('PAS ENCORE DÉMARRÉ'), findsOneWidget);
    expect(find.text('Pas de journée'), findsOneWidget);
    expect(find.text('14 formulaires'), findsOneWidget);
    expect(find.text('Hors zone'), findsOneWidget);
    expect(find.text('Batterie faible'), findsOneWidget);
    expect(find.byTooltip('WhatsApp Aminata Diallo'), findsOneWidget);

    // Jour précédent, puis retour à aujourd'hui (pas de jour suivant au-delà).
    await tester.tap(find.byTooltip('Jour précédent'));
    await _settle(tester);
    expect(find.text('Aujourd’hui'), findsNothing);
    expect(
      repo.reportDays.last!.day,
      DateTime.now().subtract(const Duration(days: 1)).day,
    );
    await tester.tap(find.byTooltip('Jour suivant'));
    await _settle(tester);
    expect(find.text('Aujourd’hui'), findsOneWidget);

    await tester.tap(find.text('Message à l’équipe'));
    await _settle(tester);
    await tester.enterText(
      find.byType(TextField).last,
      'Réunion à 17 h au bureau.',
    );
    await tester.pump();
    await tester.tap(find.text('Envoyer'));
    await _settle(tester);
    expect(repo.teamMessages.single, ('Réunion à 17 h au bureau.', null));
    expect(find.text('Message envoyé à 3 agents'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('agent : son chef, son groupe, ses zones et ses missions', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository()..withMyForms = true;
    await tester.pumpWidget(
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
    );
    await _settle(tester);

    // Journée : le chef à contacter et le groupe.
    await tester.scrollUntilVisible(
      find.text('Yao Kouassi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mon chef d’équipe · Équipe Nord'), findsOneWidget);
    expect(find.byTooltip('Appeler Yao Kouassi'), findsOneWidget);
    expect(find.byTooltip('WhatsApp Yao Kouassi'), findsOneWidget);

    // Profil : section « Mon équipe ».
    await tester.tap(_tab('Profil'));
    await _settle(tester);
    expect(find.text('MON ÉQUIPE'), findsOneWidget);
    expect(find.text('Équipe Nord'), findsOneWidget);
    expect(find.text('4 agents'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ma zone'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Plateau'), findsOneWidget);

    // Missions : affectation, participations et filtres.
    await tester.tap(_tab('Missions'));
    await _settle(tester);
    expect(find.text('Toutes (3)'), findsOneWidget);
    expect(find.textContaining('Équipe Nord · '), findsWidgets);
    expect(find.textContaining('3 formulaires envoyés'), findsOneWidget);
    expect(find.textContaining('Personnelle'), findsOneWidget);
    await _tapText(tester, 'À moi (1)');
    expect(find.text('Relance clients Cocody'), findsOneWidget);
    expect(find.text('120 visites cette semaine'), findsNothing);
    await _tapText(tester, 'Mes participations (2)');
    expect(find.text('120 visites cette semaine'), findsOneWidget);
    expect(find.text('Relance clients Cocody'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('agent sans groupe : la raison de l’absence de zones', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository()
      ..agentTeam = const AgentTeam(
        usesGroups: true,
        groupMissing: true,
        leads: [],
        zones: [],
      );
    await tester.pumpWidget(
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
    );
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.textContaining('rattaché à aucun groupe'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('rattaché à aucun groupe'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'agent : missions et rémunération de chaque zone avant de démarrer',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
      await _settle(tester);
      await _tapText(tester, 'Choisir ma zone');
      expect(find.text('120 visites cette semaine'), findsOneWidget);
      expect(find.textContaining('par formulaire'), findsOneWidget);
      expect(find.text('Aucune mission dans cette zone'), findsWidgets);

      await tester.tap(find.text('120 visites cette semaine'));
      await _settle(tester);
      expect(
        find.text('Présentez la nouvelle offre aux commerces.'),
        findsOneWidget,
      );
      expect(find.text('Votre groupe'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Nom du commerce'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('FORMULAIRE À REMPLIR'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('CE QUE RAPPORTE CETTE MISSION'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Par formulaire accepté'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('agent : envoi de formulaire seulement après le démarrage', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
    await _settle(tester);
    await tester.tap(_tab('Missions'));
    await _settle(tester);
    await tester.tap(find.text('120 visites cette semaine'));
    await _settle(tester);
    expect(find.textContaining('Démarrez votre journée'), findsOneWidget);
    expect(find.text('Nouveau formulaire'), findsNothing);
    expect(find.text('Ma journée'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('agent à temps partiel : objectif du jour selon sa durée', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      testApp(auth: () => SignedInAuth(fakeMe(workdayMinutes: 270))),
    );
    await _settle(tester);
    expect(find.text('4 h 30 de terrain'), findsOneWidget);
    expect(find.text('sur 4 h 30'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  Future<void> fillForm(WidgetTester tester, String commerce) async {
    await tester.enterText(find.byType(TextFormField).first, commerce);
    await tester.tap(find.text('Oui'));
    await _settle(tester);
  }

  testWidgets('formulaire refusé à l’envoi : reste à l’écran avec le motif', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository()
      ..submitError = ApiException(
        'Cette mission se fait à : Plateau',
        status: 409,
        code: 'WRONG_ZONE',
      );
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(submissionRequiresDay: false)),
        repo: repo,
      ),
    );
    await _settle(tester);
    await tester.tap(_tab('Missions'));
    await _settle(tester);
    await _tapText(tester, '120 visites cette semaine');
    await _tapText(tester, 'Nouveau formulaire');
    await fillForm(tester, 'Boutique Awa');
    await _tapText(tester, 'Enregistrer');

    // Le formulaire n'est ni perdu ni annoncé « enregistré » : le motif s'affiche.
    expect(
      find.text('Refusé : Cette mission se fait à : Plateau'),
      findsOneWidget,
    );
    expect(find.text('Boutique Awa'), findsOneWidget);
    expect(find.textContaining('enregistré'), findsNothing);

    // Une fois le problème réglé, l'envoi passe.
    repo.submitError = null;
    await _tapText(tester, 'Enregistrer');
    debugPrint(
      'T2: ${repo.submittedForms.length} ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).where((t) => t != null).join(' | ')}',
    );
    expect(find.text('Formulaire envoyé.'), findsOneWidget);
    expect(repo.submittedForms.single['data'], {
      'commerce': 'Boutique Awa',
      'interesse': true,
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'formulaire refusé en arrière-plan : bandeau, correction et renvoi',
    (tester) async {
      _phone(tester);
      final repo = FakeRepository();
      await tester.pumpWidget(
        testApp(
          auth: () => SignedInAuth(fakeMe(submissionRequiresDay: false)),
          repo: repo,
        ),
      );
      await _settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SuiviAgentApp)),
      );
      final db = container.read(databaseProvider);
      await db
          .into(db.pendingSubmissions)
          .insert(
            PendingSubmissionsCompanion.insert(
              clientId: 'old',
              missionId: 'm1',
              missionTitle: '120 visites cette semaine',
              dataJson: '{"commerce":"Boutique Awa","interesse":true}',
              submittedAt: DateTime.now().toUtc(),
              error: const Value(
                'Démarrez votre journée pour envoyer un formulaire',
              ),
              errorCode: const Value('DAY_REQUIRED'),
            ),
          );
      await _settle(tester);

      expect(
        find.text('1 formulaire refusé : à corriger ou supprimer.'),
        findsOneWidget,
      );
      await _tapText(tester, 'Voir');
      expect(
        find.text('Démarrez votre journée pour envoyer un formulaire'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Démarrez votre journée dans la zone'),
        findsOneWidget,
      );
      await _tapText(tester, 'Corriger');

      // Formulaire rouvert avec ses valeurs et le motif du refus.
      expect(find.text('Corriger le formulaire'), findsOneWidget);
      expect(find.text('Boutique Awa'), findsOneWidget);
      expect(
        find.textContaining('Refusé : Démarrez votre journée'),
        findsOneWidget,
      );
      await _tapText(tester, 'Enregistrer');
      expect(repo.submittedForms, hasLength(1));
      expect(await db.select(db.pendingSubmissions).get(), isEmpty);
      expect(find.textContaining('formulaire refusé'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
