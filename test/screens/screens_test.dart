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
}
