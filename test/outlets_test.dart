import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/api_client.dart';
import 'package:suivi_agent/core/providers.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/features/outlets/outlet_widgets.dart';
import 'package:suivi_agent/features/outlets/outlets_screen.dart';
import 'package:suivi_agent/features/outlets/outlet_models.dart';
import 'package:suivi_agent/features/outlets/route_screen.dart';
import 'package:suivi_agent/core/push.dart';
import 'package:latlong2/latlong.dart';

import 'fakes.dart';
import 'outlet_fakes.dart';

Finder _tab(String label) =>
    find.descendant(of: find.byType(AppNavBar), matching: find.text(label));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // Listes paresseuses : on fait défiler jusqu'à l'élément s'il n'est pas encore construit.
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('onglet selon la formule ; le chef garde ses demandes', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
    await _settle(tester);
    expect(_tab('Points de vente'), findsNothing);
    await _close(tester);

    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
        repo: OutletsRepo(),
      ),
    );
    await _settle(tester);
    expect(_tab('Points de vente'), findsOneWidget);
    expect(_tab('Missions'), findsOneWidget);
    await _close(tester);

    // Chef : 5 onglets au plus, « Points de vente » prend la place de « Demandes ».
    await tester.pumpWidget(
      testApp(
        auth: () =>
            SignedInAuth(fakeMe(role: 'team_lead', features: outletFeatures)),
        repo: OutletsRepo(),
      ),
    );
    await _settle(tester);
    expect(_tab('Points de vente'), findsOneWidget);
    expect(_tab('Demandes'), findsNothing);
    expect(
      find.descendant(of: find.byType(AppNavBar), matching: find.byType(Icon)),
      findsNWidgets(5),
    );
    await _close(tester);
  });

  testWidgets('les plus proches d’abord, fiche et changement de statut', (
    tester,
  ) async {
    _phone(tester);
    final repo = OutletsRepo();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
        repo: repo,
      ),
    );
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));

    expect(find.text('Boutique Awa'), findsOneWidget);
    expect(find.textContaining('12 m'), findsOneWidget);
    expect(find.textContaining('340 m'), findsOneWidget);
    // Importé sans position : à la fin, « À localiser ».
    expect(find.textContaining('À localiser'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Boutique Awa')).dy,
      lessThan(tester.getTopLeft(find.text('Cave Koffi')).dy),
    );
    expect(find.byType(OutletAvatar), findsNWidgets(3));

    await _tap(tester, find.text('Boutique Awa'));
    expect(find.text('Changer le statut'), findsOneWidget);
    expect(find.text('Voir sur Google Maps'), findsOneWidget);
    expect(find.text('Possède un frigo'), findsOneWidget);
    expect(find.text('Ajouté · Prospect'), findsOneWidget);

    await _tap(tester, find.text('Changer le statut'));
    await _tap(tester, find.text('Client actif'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Commentaire (facultatif)'),
      'Première commande',
    );
    await tester.pump();
    await _tap(tester, find.text('Enregistrer'));
    expect(repo.statusChanges, [('o1', 'active', 'Première commande')]);
    expect(find.text('Statut : Client actif.'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('ajout sur place : photo, doublon signalé puis confirmé', (
    tester,
  ) async {
    _phone(tester);
    final repo = OutletsRepo()
      ..createErrors.add(
        ApiException(
          '« Boutique Awa » existe déjà à 10 m',
          code: 'OUTLET_DUPLICATE',
          status: 409,
          details: {
            'candidates': [
              {
                'id': 'o1',
                'name': 'Boutique Awa',
                'status': 'prospect',
                'distance': 10,
              },
            ],
          },
        ),
      );
    final photos = FakePhotoCapture();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
        repo: repo,
        photos: photos,
      ),
    );
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));
    await _tap(tester, find.text('Ajouter'));

    expect(
      find.textContaining('Position enregistrée (à 8 m près)'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom du point de vente *'),
      'Boutique Awa Bis',
    );
    await _tap(tester, find.bySemanticsLabel('Kiosque'));
    await _tap(
      tester,
      find.bySemanticsLabel('Prendre la photo de la devanture'),
    );
    expect(photos.taken, 1);
    await _tap(tester, find.text('Enregistrer'));

    // Commerce semblable tout près : l'agent confirme que c'est un autre.
    expect(find.text('Est-ce l’un de ceux-ci ?'), findsOneWidget);
    expect(find.textContaining('à 10 m'), findsOneWidget);
    await _tap(tester, find.text('Non, c’est un autre commerce'));

    expect(repo.created, hasLength(1));
    final body = repo.created.single;
    expect(body, containsPair('name', 'Boutique Awa Bis'));
    expect(body, containsPair('category', 'Kiosque'));
    expect(body, containsPair('force', true));
    // Photo renvoyée avec le même identifiant : le serveur ne la duplique pas.
    expect(repo.uploadedPhotos.map((p) => p.clientId).toSet(), {'c1'});
    expect(body, containsPair('photoId', 'photo-2'));
    expect(body['lat'], 5.32);
    expect(body['clientId'], isA<String>());
    // Fiche ouverte après l'ajout.
    expect(find.text('Changer le statut'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('sans réseau : ajout gardé sur le téléphone puis envoyé', (
    tester,
  ) async {
    _phone(tester);
    final repo = OutletsRepo()
      ..createErrors.add(ApiException('Vous êtes hors ligne.'));
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
        repo: repo,
      ),
    );
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));
    await _tap(tester, find.text('Ajouter'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom du point de vente *'),
      'Kiosque Moov',
    );
    await _tap(tester, find.text('Enregistrer'));
    expect(find.textContaining('envoyé au retour du réseau'), findsOneWidget);
    expect(find.textContaining('1 enregistrement en attente'), findsOneWidget);
    expect(repo.created, isEmpty);

    // Retour du réseau : l'envoi part, la file se vide.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OutletsScreen)),
    );
    await tester.runAsync(() => container.read(syncProvider).flush());
    await _settle(tester);
    expect(repo.created.single['name'], 'Kiosque Moov');
    expect(find.textContaining('en attente'), findsNothing);
    await _close(tester);
  });

  testWidgets(
    'mission de visites : choisir le point de vente, distance et statut',
    (tester) async {
      _phone(tester);
      final repo = VisitsRepo();
      await tester.pumpWidget(
        testApp(
          auth: () => SignedInAuth(
            fakeMe(features: outletFeatures, submissionRequiresDay: false),
          ),
          repo: repo,
        ),
      );
      await _settle(tester);
      await _tap(tester, _tab('Missions'));
      await _tap(tester, find.text('Tournée du Plateau'));
      expect(find.text('Points de vente à visiter'), findsOneWidget);
      await _tap(tester, find.text('Visiter un point de vente'));

      expect(find.text('À visiter (2)'), findsOneWidget);
      expect(find.text('Visités (1)'), findsOneWidget);
      // Le plus proche d'abord.
      expect(
        tester.getTopLeft(find.text('Boutique Awa')).dy,
        lessThan(tester.getTopLeft(find.text('Kiosque du Lycée')).dy),
      );

      // Trop loin : l'agent est prévenu avant d'enregistrer.
      await _tap(tester, find.text('Kiosque du Lycée'));
      expect(
        find.textContaining('rapprochez-vous (50 m au plus)'),
        findsOneWidget,
      );
      await _tap(tester, find.byType(BackButton));

      await _tap(tester, find.text('Boutique Awa'));
      expect(find.text('Visite'), findsOneWidget);
      expect(find.textContaining('Vous êtes sur place'), findsOneWidget);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Client actif'));
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Commentaire sur le point de vente (facultatif)',
        ),
        'Commande passée',
      );
      await tester.pump();
      await _tap(tester, find.text('Enregistrer'));

      final sent = repo.submittedForms.single;
      expect(sent, containsPair('missionId', 'v1'));
      expect(sent, containsPair('outletId', 'o1'));
      expect(sent, containsPair('outletStatus', 'active'));
      expect(sent, containsPair('outletComment', 'Commande passée'));
      expect(sent, containsPair('accuracy', 8.0));
      expect(sent['lat'], 5.32);
      await _close(tester);
    },
  );

  testWidgets('relevé par produit : présence, casiers + bouteilles, prix', (
    tester,
  ) async {
    _phone(tester);
    final repo = ReadingsRepo();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(
          fakeMe(features: outletFeatures, submissionRequiresDay: false),
        ),
        repo: repo,
      ),
    );
    await _settle(tester);
    await _tap(tester, _tab('Missions'));
    await _tap(tester, find.text('Relevé des boissons'));
    await _tap(tester, find.text('Nouveau formulaire'));

    expect(find.text('Coca-Cola 33 cl'), findsOneWidget);
    expect(find.text('Concurrent'), findsOneWidget);
    expect(find.text('0/2 relevé'), findsOneWidget);

    // Rien de relevé : refusé.
    await _tap(tester, find.text('Enregistrer'));
    expect(find.text('Relevez au moins un produit'), findsOneWidget);

    await _tap(tester, find.bySemanticsLabel('Présent').first);
    // Plusieurs conditionnements : on compte en casiers.
    await _tap(tester, find.text('En casiers').first);
    await tester.enterText(
      find.widgetWithText(TextField, 'casiers').first,
      '3',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'bouteilles').first,
      '5',
    );
    await tester.pump();
    expect(find.text('= 41 bouteilles (3 casiers + 5)'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Prix de vente').first,
      '300',
    );
    // Pepsi en rupture : stock et prix disparaissent.
    await _tap(tester, find.bySemanticsLabel('Rupture').last);
    expect(find.widgetWithText(TextField, 'Prix de vente'), findsOneWidget);
    expect(find.text('2/2 relevés'), findsOneWidget);

    await _tap(tester, find.text('Enregistrer'));
    expect(repo.submittedForms.single['data'], {
      'releve': {
        'p-coca': {'presence': true, 'stock': 41, 'price': 300},
        'p-pepsi': {'presence': false},
      },
    });
    await _close(tester);
  });

  testWidgets('chef : tableau de bord produits de son équipe', (tester) async {
    _phone(tester);
    final repo = InsightsRepo();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(
          fakeMe(
            role: 'team_lead',
            features: {...outletFeatures, 'product_audits'},
          ),
        ),
        repo: repo,
      ),
    );
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));
    await _tap(tester, find.text('Tableau de bord produits'));

    expect(find.text('21 %'), findsOneWidget);
    expect(find.text('4 sur 19 relevés'), findsOneWidget);
    expect(find.text('Fanta 33 cl'), findsWidgets);
    expect(find.text('190 bouteilles (15 casiers + 10)'), findsOneWidget);
    // 30 jours par défaut.
    final (from, to) = repo.periods.single;
    expect(DateTime.parse(to).difference(DateTime.parse(from)).inDays, 29);

    // 7 derniers jours : relu pour la nouvelle période.
    await _tap(tester, find.text('7 derniers jours'));
    expect(repo.periods, hasLength(2));
    await tester.scrollUntilVisible(
      find.text('Nous sommes 17 % plus chers'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Nous sommes 17 % plus chers'), findsOneWidget);

    // Une rupture ouvre la fiche du point de vente.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await _settle(tester);
    await _tap(tester, find.text('Boutique Awa · Plateau · 10 oct.'));
    expect(find.text('Changer le statut'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('retards de visite et ma tournée', (tester) async {
    _phone(tester);
    final repo = RouteRepo();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
        repo: repo,
      ),
    );
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));
    expect(find.text('En retard 2'), findsOneWidget);
    expect(find.textContaining('Visité il y a 42 j'), findsOneWidget);
    expect(find.byType(OverduePill), findsNWidgets(2));
    expect(find.text('2 points de vente en retard de visite'), findsOneWidget);

    await _tap(tester, find.text('En retard 2'));
    expect(find.text('Boutique Awa'), findsNothing);
    expect(find.text('Kiosque Orange'), findsOneWidget);

    await _tap(tester, find.text('Ma tournée'));
    expect(repo.routes.single, (5.32, -4.02, null));
    expect(find.text('2 étapes · 1,2 km'), findsOneWidget);
    expect(
      find.text('Environ 21 min de trajet à pied et 20 min de visites'),
      findsOneWidget,
    );
    expect(find.text('Ouvrir l’itinéraire dans Google Maps'), findsOneWidget);
    // Étapes numérotées dans l'ordre.
    expect(
      tester.getTopLeft(find.text('Pharmacie du Port')).dy,
      lessThan(tester.getTopLeft(find.text('Kiosque Orange')).dy),
    );
    await _close(tester);
  });

  testWidgets('points de vente seuls : visite libre depuis la fiche', (
    tester,
  ) async {
    _phone(tester);
    final repo = FreeVisitRepo();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(
          fakeMe(features: outletOnlyFeatures, submissionRequiresDay: false),
        ),
        repo: repo,
      ),
    );
    await _settle(tester);
    expect(_tab('Missions'), findsNothing);
    await _tap(tester, _tab('Points de vente'));
    await _tap(tester, find.text('Boutique Awa'));

    // Deux formulaires proposés : l'agent choisit.
    await _tap(tester, find.text('Visiter'));
    expect(find.text('Quel formulaire remplir ?'), findsOneWidget);
    await _tap(tester, find.text('Audit point de vente'));
    expect(find.text('Visite'), findsOneWidget);
    expect(find.textContaining('Vous êtes sur place'), findsOneWidget);

    // Champ obligatoire vide : rien ne part.
    await _tap(tester, find.text('Enregistrer'));
    expect(repo.freeVisits, isEmpty);
    // Le message d'erreur s'efface avant le second envoi.
    await tester.pump(const Duration(seconds: 6));
    await _settle(tester);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Rayon boissons bien rempli',
    );
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Client actif'));
    await _tap(tester, find.text('Enregistrer'));

    final sent = repo.freeVisits.single;
    expect(sent['path'], 'o1');
    expect(sent, containsPair('typeId', 'f1'));
    expect(sent.containsKey('outletId'), isFalse);
    expect(sent['data'], {'remarque': 'Rayon boissons bien rempli'});
    expect(sent, containsPair('outletStatus', 'active'));
    expect(sent, containsPair('accuracy', 8.0));
    expect(repo.submittedForms, isEmpty);
    expect(find.text('Formulaire envoyé.'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('visite libre : un seul formulaire, ouvert directement', (
    tester,
  ) async {
    _phone(tester);
    final repo = FreeVisitRepo(forms: 1);
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(
          fakeMe(features: outletFeatures, submissionRequiresDay: false),
        ),
        repo: repo,
      ),
    );
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));
    await _tap(tester, find.text('Boutique Awa'));
    await _tap(tester, find.text('Visiter'));
    expect(find.text('Quel formulaire remplir ?'), findsNothing);
    expect(find.text('Audit point de vente'), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
    'sans formulaire de visite ou pour le chef : pas de « Visiter »',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        testApp(
          auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
          repo: OutletsRepo(),
        ),
      );
      await _settle(tester);
      await _tap(tester, _tab('Points de vente'));
      await _tap(tester, find.text('Boutique Awa'));
      expect(find.text('Changer le statut'), findsOneWidget);
      expect(find.text('Visiter'), findsNothing);
      await _close(tester);

      await tester.pumpWidget(
        testApp(
          auth: () =>
              SignedInAuth(fakeMe(role: 'team_lead', features: outletFeatures)),
          repo: FreeVisitRepo(),
        ),
      );
      await _settle(tester);
      await _tap(tester, _tab('Points de vente'));
      await _tap(tester, find.text('Boutique Awa'));
      expect(find.text('Visiter'), findsNothing);
      await _close(tester);
    },
  );

  test('itinéraire Google Maps : départ, étapes, arrivée', () {
    final stops = [
      for (final (i, lat) in [5.33, 5.34, 5.35].indexed)
        RouteStop(
          Outlet.fromJson(outletJson('o$i', 'P$i', lat: lat)),
          i + 1,
          100,
        ),
    ];
    final uri = googleMapsRoute(const LatLng(5.32, -4.02), stops);
    expect(uri.host, 'www.google.com');
    expect(uri.queryParameters['origin'], '5.32,-4.02');
    expect(uri.queryParameters['destination'], '5.35,-4.02');
    expect(uri.queryParameters['waypoints'], '5.33,-4.02|5.34,-4.02');
    expect(uri.queryParameters['travelmode'], 'walking');
  });

  test('avis du matin : ouvre les points de vente en retard', () {
    expect(
      pushRouteFor({'type': 'outlets.overdue'}, leader: true),
      '/outlets?overdue=1',
    );
    expect(
      pushRouteFor({'type': 'visit.rejected', 'outletId': 'o1'}, leader: false),
      '/outlets/o1',
    );
  });
}
