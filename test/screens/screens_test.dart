@Tags(['screens'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/app.dart';
import 'package:suivi_agent/core/models.dart';
import 'package:suivi_agent/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../fakes.dart';
import '../outlet_fakes.dart';

/// Rendus d'écrans à la taille d'un iPhone (390 × 844), police et icônes réelles.
/// flutter test --tags screens --run-skipped --update-goldens  → test/screens/goldens/*.png
Future<void> _loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans')
    ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
  await jakarta.load();
  final root = Platform.environment['FLUTTER_ROOT']!;
  final bytes = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytesSync();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await icons.load();
}

Future<void> _capture(
  WidgetTester tester,
  Widget app,
  String name, {
  Brightness brightness = Brightness.light,
  Future<void> Function()? then,
  // Feuilles modales : elles s'affichent hors du Scaffold, on capture toute l'app.
  bool wholeApp = false,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(app);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (then != null) {
    await then();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await expectLater(
    wholeApp ? find.byType(MaterialApp) : find.byType(Scaffold).first,
    matchesGoldenFile('goldens/$name.png'),
  );
  await tester.pumpWidget(const SizedBox());
  // Laisse l'arrêt des services (minuteries) se terminer après le démontage.
  await tester.pump(const Duration(seconds: 1));
}

DayState _activeDay() => DayState(
  day: WorkDay(
    id: 'd1',
    status: DayStatus.active,
    zoneId: 'z1',
    startedAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 42)),
    endedAt: null,
    pausedSeconds: 1800,
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await _loadFonts();
  });

  testWidgets(
    'connexion',
    (tester) =>
        _capture(tester, testApp(auth: SignedOutAuth.new), '01-connexion'),
  );

  testWidgets('agent - prêt', (tester) {
    final repo = FakeRepository()
      ..day = DayState(
        approved: ZoneRequest(
          id: 'r1',
          zoneId: 'z1',
          status: RequestStatus.approved,
          expiresAt: null,
          isChange: false,
        ),
      );
    return _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      '02-agent-pret',
    );
  });

  testWidgets('accueil avec notifications non lues', (tester) {
    final repo = FakeRepository()
      ..notificationsList = [
        for (var i = 0; i < 3; i++)
          AppNotification(
            id: 'n$i',
            title: 'Demande de zone approuvée',
            body: null,
            createdAt: DateTime(2026, 10, 16, 8, i),
            read: false,
          ),
      ];
    return _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      '02b-agent-notifications-non-lues',
    );
  });

  testWidgets('agent - journée interrompue', (tester) {
    final today = DateTime.now();
    final repo = FakeRepository()
      ..day = DayState(
        resumable: ResumableDay(
          id: 'd1',
          endedAt: DateTime(today.year, today.month, today.day, 13, 5),
          workedSeconds: 5 * 3600 + 10 * 60,
        ),
        approved: ZoneRequest(
          id: 'r1',
          zoneId: 'z1',
          status: RequestStatus.approved,
          expiresAt: null,
          isChange: false,
        ),
      );
    return _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      '55-agent-journee-interrompue',
    );
  });

  testWidgets(
    'agent - sans zone',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe())),
      '03-agent-sans-zone',
    ),
  );

  testWidgets('agent - en journée', (tester) {
    final repo = FakeRepository()..day = _activeDay();
    return _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      '04-agent-en-journee',
    );
  });

  testWidgets('agent - en journée (sombre)', (tester) {
    final repo = FakeRepository()..day = _activeDay();
    return _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      '05-agent-sombre',
      brightness: Brightness.dark,
    );
  });

  testWidgets(
    'agent - missions',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe())),
      '06-agent-missions',
      then: () async => tester.tap(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.text('Missions'),
        ),
      ),
    ),
  );

  testWidgets(
    'agent - détail de mission',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe())),
      '06b-mission',
      then: () async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppNavBar),
            matching: find.text('Missions'),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('120 visites cette semaine'));
      },
    ),
  );

  testWidgets(
    'agent - choix de zone',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe())),
      '07-choix-zone',
      then: () async => tester.tap(find.text('Choisir ma zone').last),
    ),
  );

  testWidgets(
    'chef - équipe',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '08-chef-equipe',
    ),
  );

  testWidgets(
    'chef - demandes',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '09-chef-demandes',
      then: () async => tester.tap(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.text('Demandes'),
        ),
      ),
    ),
  );

  testWidgets(
    'profil',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe())),
      '10-profil',
      then: () async => tester.tap(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.text('Profil'),
        ),
      ),
    ),
  );

  testWidgets(
    'chef - carte',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '11-chef-carte',
      then: () async => tester.tap(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.text('Carte'),
        ),
      ),
    ),
  );

  testWidgets(
    'chef - carte, itinéraire',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '12-chef-carte-itineraire',
      then: () async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppNavBar),
            matching: find.text('Carte'),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Koffi Brou'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Itinéraire du jour'));
      },
    ),
  );

  testWidgets(
    'chef - options de la carte',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '13-chef-carte-options',
      then: () async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppNavBar),
            matching: find.text('Carte'),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.byIcon(Icons.layers_outlined));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Noms des agents'));
      },
    ),
  );

  Future<void> openMission(WidgetTester tester, String tab) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AppNavBar),
        matching: find.text('Missions'),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('120 visites cette semaine'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is AppSegmented),
        matching: find.text(tab),
      ),
    );
  }

  testWidgets(
    'chef - formulaires d’une mission',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '14-chef-mission-formulaires',
      then: () => openMission(tester, 'Formulaires'),
    ),
  );

  testWidgets(
    'chef - équipe d’une mission',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '15-chef-mission-equipe',
      then: () => openMission(tester, 'Équipe'),
    ),
  );

  testWidgets(
    'profil - mot de passe',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe())),
      '16-profil-mot-de-passe',
      then: () async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppNavBar),
            matching: find.text('Profil'),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.ensureVisible(find.text('Mon compte'));
        await tester.pump();
        await tester.tap(find.text('Mon compte'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Mot de passe'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.enterText(find.byType(TextFormField).at(1), 'Nouveau2026');
      },
    ),
  );

  Future<void> openProfileRow(WidgetTester tester, String row) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AppNavBar),
        matching: find.text('Profil'),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text(row));
  }

  Me payMe(String role, String first) =>
      fakeMe(role: role, first: first, features: const {'missions', 'payroll'});

  testWidgets(
    'profil - rémunération',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(payMe('agent', 'Koffi'))),
      '17-profil-remuneration',
      then: () async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppNavBar),
            matching: find.text('Profil'),
          ),
        );
      },
    ),
  );

  testWidgets(
    'agent - mes gains',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(payMe('agent', 'Koffi'))),
      '18-agent-mes-gains',
      then: () => openProfileRow(tester, 'Mes gains'),
    ),
  );

  testWidgets(
    'agent - mes gains, paies validées',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(payMe('agent', 'Koffi'))),
      '19-agent-mes-gains-historique',
      then: () async {
        await openProfileRow(tester, 'Mes gains');
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      },
    ),
  );

  testWidgets(
    'agent - reçu de paie',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(payMe('agent', 'Koffi'))),
      '20-agent-recu',
      then: () async {
        await openProfileRow(tester, 'Mes gains');
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.drag(find.byType(ListView).last, const Offset(0, -600));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Septembre 2026'));
      },
    ),
  );

  testWidgets(
    'chef - gains de l’équipe',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(payMe('team_lead', 'Yao'))),
      '21-chef-gains-equipe',
      then: () => openProfileRow(tester, 'Gains de l’équipe'),
    ),
  );

  testWidgets(
    'agent - mes gains (sombre)',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(payMe('agent', 'Koffi'))),
      '22-agent-mes-gains-sombre',
      brightness: Brightness.dark,
      then: () => openProfileRow(tester, 'Mes gains'),
    ),
  );

  Future<void> openMissions(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AppNavBar),
        matching: find.text('Missions'),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'chef - nouvelle mission',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '23-chef-nouvelle-mission',
      then: () async {
        await openMissions(tester);
        await tester.tap(find.text('Nouvelle mission'));
      },
    ),
  );

  testWidgets(
    'chef - gérer une mission',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '24-chef-gerer-mission',
      wholeApp: true,
      then: () async {
        await openMissions(tester);
        await tester.tap(find.text('120 visites cette semaine'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.byTooltip('Gérer la mission'));
      },
    ),
  );

  testWidgets(
    'chef - paie à valider',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(payMe('team_lead', 'Yao'))),
      '25-chef-paie-a-valider',
      then: () async {
        await openProfileRow(tester, 'Gains de l’équipe');
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
      },
    ),
  );

  testWidgets(
    'chef - proposer une prime',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(payMe('team_lead', 'Yao'))),
      '26-chef-proposer-prime',
      wholeApp: true,
      then: () async {
        await openProfileRow(tester, 'Gains de l’équipe');
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Koffi Brou').last);
      },
    ),
  );

  FakeTracker trackerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
            tester.element(find.byType(SuiviAgentApp)),
          ).read(trackerProvider)
          as FakeTracker;

  testWidgets('agent - hors de sa zone', (tester) {
    final repo = FakeRepository()..day = _activeDay();
    return _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      '27-agent-hors-zone',
      then: () async {
        trackerOf(tester).emit(
          eastOfPlateau(420),
          at: DateTime.now().subtract(const Duration(minutes: 7)),
        );
        trackerOf(tester).emit(eastOfPlateau(430));
      },
    );
  });

  testWidgets('agent - ma zone (plein écran)', (tester) {
    final repo = FakeRepository()..day = _activeDay();
    return _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      '28-agent-ma-zone',
      then: () async {
        trackerOf(tester).emit(const LatLng(5.3235, -4.0172), accuracy: 40);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        GoRouter.of(tester.element(find.text('Ma journée'))).push('/day/zone');
      },
    );
  });

  testWidgets(
    'agent - ce que rapporte la mission',
    (tester) => _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe())),
      '29-agent-gains-mission',
      then: () async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppNavBar),
            matching: find.text('Missions'),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('120 visites cette semaine'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -520));
      },
    ),
  );

  testWidgets('agent - style de la carte de sa zone', (tester) {
    final repo = FakeRepository()..day = _activeDay();
    return _capture(
      tester,
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      '30-agent-ma-zone-style',
      wholeApp: true,
      then: () async {
        trackerOf(tester).emit(const LatLng(5.3235, -4.0172));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        GoRouter.of(tester.element(find.text('Ma journée'))).push('/day/zone');
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.byIcon(Icons.layers_outlined));
      },
    );
  });

  testWidgets(
    'chef - alertes',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '31-chef-alertes',
      then: () async {
        await tester.tap(
          find.ancestor(
            of: find.text('Alertes'),
            matching: find.byType(SurfaceCard),
          ),
        );
      },
    ),
  );

  testWidgets(
    'chef - alertes d’un agent',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '32-chef-alertes-agent',
      wholeApp: true,
      then: () async {
        await tester.tap(
          find.ancestor(
            of: find.text('Alertes'),
            matching: find.byType(SurfaceCard),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Aminata Diallo'));
      },
    ),
  );

  testWidgets(
    'chef - bilan du jour',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '33-chef-bilan',
      then: () async => tester.tap(find.text('Bilan du jour')),
    ),
  );

  testWidgets(
    'chef - message à l’équipe',
    (tester) => _capture(
      tester,
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
      ),
      '34-chef-message',
      wholeApp: true,
      then: () async {
        await tester.tap(find.text('Message à l’équipe'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.enterText(
          find.byType(TextField).last,
          'Réunion à 17 h au bureau du Plateau.',
        );
      },
    ),
  );

  group('points de vente', () {
    OutletsRepo repo() => OutletsRepo()
      ..outletList.addAll([
        outletJson(
          'o4',
          'Maquis Le Bonheur',
          category: 'Maquis / Bar',
          status: 'active',
          distance: 520,
          lat: 5.3248,
          lng: -4.0161,
        ),
        outletJson(
          'o5',
          'Kiosque Orange',
          category: 'Kiosque',
          status: 'closed',
          distance: 780,
          lat: 5.3155,
          lng: -4.0242,
        ),
        outletJson(
          'o6',
          'Superette Bon Prix',
          category: 'Supérette',
          status: 'inactive',
          distance: 1250,
          lat: 5.3262,
          lng: -4.0263,
        ),
      ]);
    Widget app() => testApp(
      auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
      repo: repo(),
    );
    Finder tab(String label) =>
        find.descendant(of: find.byType(AppNavBar), matching: find.text(label));

    testWidgets(
      'liste',
      (tester) => _capture(
        tester,
        app(),
        '35-agent-points-de-vente',
        then: () => tester.tap(tab('Points de vente')),
      ),
    );
    testWidgets(
      'carte',
      (tester) => _capture(
        tester,
        app(),
        '36-agent-points-de-vente-carte',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Carte'));
        },
      ),
    );
    testWidgets(
      'fiche',
      (tester) => _capture(
        tester,
        app(),
        '37-agent-fiche-point-de-vente',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Boutique Awa'));
        },
      ),
    );
    testWidgets(
      'agent mes produits',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(
            fakeMe(features: {...outletFeatures, 'product_audits'}),
          ),
          repo: InsightsRepo(),
        ),
        '49-agent-mes-produits',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Mes statistiques'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -700),
          );
        },
      ),
    );
    testWidgets('agent mes ventes par commandes', (tester) async {
      final repo = OrdersRepo();
      await repo.createOrder({
        'outletId': 'o1',
        'lines': [
          {'productId': 'p-coca', 'quantity': 30},
        ],
      });
      await repo.changeOrderStatus('ord-1', 'paid');
      await repo.createOrder({
        'outletId': 'o1',
        'lines': [
          {'productId': 'p-coca', 'quantity': 12},
        ],
      });
      await repo.changeOrderStatus('ord-2', 'delivered');
      await _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: orderFeatures)),
          repo: repo,
        ),
        '51-agent-mes-ventes',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Mes statistiques'));
        },
      );
    });
    testWidgets(
      'statistiques des formulaires',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
          repo: FormStatsRepo(),
        ),
        '52-agent-statistiques-formulaires',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Mes statistiques'));
        },
      ),
    );
    testWidgets(
      'detail d une visite',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: auditFeatures)),
          repo: HistoryRepo(),
        ),
        '50-agent-detail-visite',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Boutique Awa'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.scrollUntilVisible(
            find.text('Voir toutes les visites'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          // Au milieu de l'écran : pas sous la barre d'onglets.
          await tester.ensureVisible(find.text('Voir toutes les visites'));
          await Scrollable.ensureVisible(
            tester.element(find.text('Voir toutes les visites')),
            alignment: 0.5,
          );
          await tester.pump();
          await tester.tap(find.text('Voir toutes les visites'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.textContaining('2 produits relevés'));
        },
      ),
    );
    testWidgets(
      'signalement avec recherche dans le catalogue',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: auditFeatures)),
          repo: ActivityRepo()
            ..productsJson = [
              {
                'id': 'h65',
                'name': 'Heineken',
                'format': '65 cl',
                'brand': 'Brasivoire',
                'category': 'Bières',
                'own': false,
              },
              {
                'id': 'h33',
                'name': 'Heineken',
                'format': '33 cl',
                'brand': 'Brasivoire',
                'category': 'Bières',
                'own': false,
              },
            ],
        ),
        '54-agent-signalement-recherche',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Boutique Awa'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Concurrent'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Nom du produit *'),
            'heine',
          );
        },
      ),
    );
    testWidgets(
      'fiche chargee',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: auditFeatures)),
          repo: BusyOutletRepo(),
        ),
        '53-agent-fiche-sections',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Boutique Awa'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -560),
          );
        },
      ),
    );
    testWidgets(
      'fiche avec visite et commande',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: orderFeatures)),
          repo: OrdersRepo(),
        ),
        '48-agent-fiche-actions',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Boutique Awa'));
        },
      ),
    );
    testWidgets(
      'prise de commande',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: orderFeatures)),
          repo: OrdersRepo(),
        ),
        '47-agent-prise-de-commande',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Boutique Awa'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.ensureVisible(find.text('Commander'));
          await tester.pump();
          await tester.tap(find.text('Commander'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.enterText(
            find.widgetWithText(TextField, 'bouteilles').first,
            '30',
          );
        },
      ),
    );
    testWidgets(
      'fiche avec produits et visites',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: auditFeatures)),
          repo: ActivityRepo(),
        ),
        '46-agent-fiche-produits-visites',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Boutique Awa'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -620),
          );
        },
      ),
    );
    testWidgets(
      'ajout',
      (tester) => _capture(
        tester,
        app(),
        '38-agent-ajout-point-de-vente',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Ajouter'));
        },
      ),
    );
    testWidgets(
      'statut',
      (tester) => _capture(
        tester,
        app(),
        '39-agent-changer-statut',
        wholeApp: true,
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Boutique Awa'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Statut'));
        },
      ),
    );

    Widget visits() => testApp(
      auth: () => SignedInAuth(
        fakeMe(features: outletFeatures, submissionRequiresDay: false),
      ),
      repo: VisitsRepo(),
    );
    Future<void> openVisits(WidgetTester tester) async {
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.tap(tab('Missions'));
      await settle();
      await tester.tap(find.text('Tournée du Plateau'));
      await settle();
      await tester.tap(find.text('Visiter un point de vente'));
      await settle();
    }

    testWidgets(
      'mission de visites',
      (tester) => _capture(
        tester,
        visits(),
        '40-agent-mission-visites',
        then: () => openVisits(tester),
      ),
    );
    testWidgets(
      'visite',
      (tester) => _capture(
        tester,
        visits(),
        '41-agent-visite',
        then: () async {
          await openVisits(tester);
          await tester.tap(find.text('Boutique Awa'));
        },
      ),
    );

    testWidgets(
      'relevé',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(
            fakeMe(features: outletFeatures, submissionRequiresDay: false),
          ),
          repo: ReadingsRepo(),
        ),
        '42-agent-releve-produits',
        then: () async {
          Future<void> settle() async {
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }

          await tester.tap(tab('Missions'));
          await settle();
          await tester.tap(find.text('Relevé des boissons'));
          await settle();
          await tester.tap(find.text('Nouveau formulaire'));
          await settle();
          await tester.tap(find.bySemanticsLabel('Présent').first);
          await settle();
          await tester.enterText(
            find.widgetWithText(TextField, 'casiers').first,
            '3',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'bouteilles').first,
            '5',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Prix de vente').first,
            '300',
          );
          FocusManager.instance.primaryFocus?.unfocus();
        },
      ),
    );

    testWidgets(
      'tableau de bord',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(
            fakeMe(
              role: 'team_lead',
              features: {...outletFeatures, 'product_audits'},
            ),
          ),
          repo: InsightsRepo(),
        ),
        '43-chef-tableau-de-bord-produits',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Statistiques de l’équipe'));
        },
      ),
    );

    testWidgets(
      'tournée',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
          repo: RouteRepo(),
        ),
        '44-agent-ma-tournee',
        then: () async {
          await tester.tap(tab('Points de vente'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Ma tournée'));
        },
      ),
    );
    testWidgets(
      'retards',
      (tester) => _capture(
        tester,
        testApp(
          auth: () => SignedInAuth(fakeMe(features: outletFeatures)),
          repo: RouteRepo(),
        ),
        '45-agent-points-de-vente-retards',
        then: () => tester.tap(tab('Points de vente')),
      ),
    );
  });
}
