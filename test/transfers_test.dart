import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/features/van_sales/transfers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:suivi_agent/features/shell/live_updates.dart';
import 'package:suivi_agent/features/van_sales/van_sales.dart';

import 'fakes.dart';
import 'van_fakes.dart';

/// Dépannage entre camions et vente d'urgence hors zone, dans l'onglet Camion.

Finder _tab(String label) =>
    find.descendant(of: find.byType(AppNavBar), matching: find.text(label));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await _scrollTo(tester, finder);
  }
  // Au milieu de l'écran : jamais caché par la barre d'onglets.
  await Scrollable.ensureVisible(tester.element(finder.first), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder.first);
  await _settle(tester);
}

Future<void> _see(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await _scrollTo(tester, finder);
    await _settle(tester);
  }
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

/// Lecteur de code simulé : rend le contenu prévu.
class _FakeScanner implements CodeScanner {
  _FakeScanner(this.value);
  final String? value;
  int scans = 0;

  @override
  Future<String?> scan(BuildContext context) async {
    scans++;
    return value;
  }
}

Widget _app(VanRepo repo, {CodeScanner? scanner}) => testApp(
  auth: () => SignedInAuth(fakeMe(features: vanFeatures)),
  repo: repo,
  overrides: [
    fileSharerProvider.overrideWithValue(FakeSharer()),
    if (scanner != null) codeScannerProvider.overrideWithValue(scanner),
  ],
);

const _coca = {
  'id': 'p-coca',
  'name': 'Coca-Cola',
  'format': '33 cl',
  'own': true,
  'unit': 'Bouteille',
  'packagings': [
    {'name': 'Casier', 'units': 12},
  ],
};

/// Fait défiler jusqu'à l'élément, vers le bas puis vers le haut (police agrandie : il peut
/// être au-dessus ou au-dessous de l'écran).
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  final list = find.byType(Scrollable).first;
  try {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: list,
      maxScrolls: 30,
    );
  } on StateError {
    await tester.scrollUntilVisible(
      finder,
      -200,
      scrollable: list,
      maxScrolls: 60,
    );
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'demande de dépannage : produits, envoi, code à montrer, clôture',
    (tester) async {
      _phone(tester);
      final repo = VanRepo()
        ..loadPending = false
        ..productsJson = [_coca];
      await tester.pumpWidget(_app(repo));
      await _settle(tester);
      await _tap(tester, _tab('Camion'));
      await _tap(tester, find.text('Demander un dépannage'));

      // Rien de saisi : refusé.
      await _tap(tester, find.text('Envoyer la demande'));
      expect(
        find.text('Saisissez la quantité d’au moins un produit.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Casier (12)'));
      await _tap(tester, find.text('Casier (12)'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Note (facultatif)'),
        'Rupture chez la Supérette',
      );
      await _tap(tester, find.text('Envoyer la demande'));
      expect(repo.transferBodies.single['lines'], [
        {'productId': 'p-coca', 'quantity': 24},
      ]);
      expect(repo.transferBodies.single['note'], 'Rupture chez la Supérette');
      // Le code à faire scanner s'ouvre aussitôt.
      expect(find.text('Mon code de dépannage'), findsOneWidget);
      Navigator.of(tester.element(find.text('Mon code de dépannage'))).pop();
      // Le message de confirmation disparaît.
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);

      // Dans « Mon camion » : la demande, le code, la clôture.
      await _see(tester, find.textContaining('Ma demande'));
      expect(find.textContaining('24 encore cherché'), findsOneWidget);
      await _tap(tester, find.text('J’ai ce qu’il me faut'));
      await _tap(tester, find.text('J’ai ce qu’il me faut').last);
      expect(repo.closed, ['t-mine']);
      await _close(tester);
    },
  );

  testWidgets('prendre une part puis la remettre en scannant le code', (
    tester,
  ) async {
    _phone(tester);
    final repo = VanRepo()
      ..loadPending = false
      ..nearbyJson = [
        transferJson(
          id: 't-awa',
          requesterId: 'u-awa',
          requesterName: 'Aminata Diallo',
          distanceM: 300,
          myStock: {'p-coca': 24},
          lines: [
            {
              'productId': 'p-coca',
              'name': 'Coca-Cola 33 cl',
              'requested': 30,
              'reserved': 0,
              'given': 0,
              'remaining': 30,
            },
          ],
        ),
      ];
    final scanner = _FakeScanner('autre-chose');
    await tester.pumpWidget(_app(repo, scanner: scanner));
    await _settle(tester);
    await _tap(tester, _tab('Camion'));
    await _see(tester, find.textContaining('Aminata Diallo (à 300 m)'));
    expect(find.textContaining('vous en avez 24'), findsOneWidget);
    await _tap(tester, find.text('Prendre une part'));
    // Proposé : au plus ce qui manque et ce que j'ai (24).
    await _tap(tester, find.text('Prendre cette part'));
    expect(repo.acceptBodies.single.$1, 't-awa');
    expect(repo.acceptBodies.single.$2, [
      {'productId': 'p-coca', 'quantity': 24},
    ]);
    expect(find.textContaining('Part réservée pour 1 h'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);

    // Ma part à remettre : un code qui n'est pas un dépannage est refusé.
    await _see(tester, find.text('Dépanner Aminata Diallo'));
    await _tap(tester, find.text('Remettre (scanner son code)'));
    await _tap(tester, find.text('Scanner le code et remettre'));
    expect(scanner.scans, 1);
    expect(
      find.textContaining('n’est pas un code de dépannage'),
      findsOneWidget,
    );
    expect(repo.handoverBodies, isEmpty);
    await _close(tester);

    // Bon code : la remise part avec le code et les quantités.
    final repo2 = VanRepo()
      ..loadPending = false
      ..myTransfersJson = [
        transferJson(
          id: 't-awa',
          requesterId: 'u-awa',
          requesterName: 'Aminata Diallo',
          lines: [
            {
              'productId': 'p-coca',
              'name': 'Coca-Cola 33 cl',
              'requested': 30,
              'reserved': 24,
              'given': 0,
              'remaining': 6,
            },
          ],
          legs: [
            {
              'id': 'leg-1',
              'giverId': 'u1',
              'giverName': 'Koffi Brou',
              'status': 'accepted',
              'statusLabel': 'Réservée',
              'crossTeam': false,
              'expiresAt': '2026-11-07T15:30:00.000Z',
              'lines': [
                {
                  'productId': 'p-coca',
                  'name': 'Coca-Cola 33 cl',
                  'quantity': 24,
                },
              ],
            },
          ],
        ),
      ];
    await tester.pumpWidget(
      _app(repo2, scanner: _FakeScanner('${transferQrPrefix}CODE-AWA')),
    );
    await _settle(tester);
    await _tap(tester, _tab('Camion'));
    await _tap(tester, find.text('Remettre (scanner son code)'));
    await _tap(tester, find.text('Scanner le code et remettre'));
    expect(repo2.handoverBodies.single['token'], 'CODE-AWA');
    expect(repo2.handoverBodies.single['lines'], [
      {'productId': 'p-coca', 'quantity': 24},
    ]);
    expect(find.textContaining('Remis à Aminata Diallo'), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
    'page Journée : la demande d’un collègue proche apparaît en direct',
    (tester) async {
      _phone(tester);
      final repo = VanRepo()..loadPending = false;
      await tester.pumpWidget(_app(repo));
      await _settle(tester);
      expect(find.text('DÉPANNAGES EN COURS'), findsNothing);

      // Un collègue demande un dépannage : le serveur l'annonce, la journée se relit seule.
      repo.nearbyJson = [
        transferJson(
          id: 't-awa',
          requesterId: 'u-awa',
          requesterName: 'Aminata Diallo',
          distanceM: 300,
          myStock: {'p-coca': 24},
          lines: [
            {
              'productId': 'p-coca',
              'name': 'Coca-Cola 33 cl',
              'requested': 30,
              'reserved': 0,
              'given': 0,
              'remaining': 30,
            },
          ],
        ),
      ];
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppNavBar)),
      );
      container
          .read(liveUpdatesProvider)
          .refresh(areasForNotification('transfer.requested'));
      await _settle(tester);
      await _see(tester, find.text('DÉPANNAGES EN COURS'));
      await _see(tester, find.textContaining('Aminata Diallo (à 300 m)'));
      expect(find.textContaining('vous en avez 24'), findsOneWidget);
      await _tap(tester, find.text('Prendre une part'));
      expect(find.text('Prendre cette part'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets(
    'vente hors zone : client trouvé, motif obligatoire, vente marquée',
    (tester) async {
      _phone(tester);
      final repo = VanRepo()..loadPending = false;
      await tester.pumpWidget(_app(repo));
      await _settle(tester);
      await _tap(tester, _tab('Camion'));
      await _tap(tester, find.text('Vente hors zone'));
      await tester.enterText(find.byType(TextField).first, 'maquis');
      await tester.pump(const Duration(milliseconds: 500));
      await _settle(tester);
      await _see(tester, find.text('Maquis Cocody'));
      expect(find.text('Maquis Cocody'), findsOneWidget);
      expect(find.textContaining('Zone Cocody'), findsOneWidget);
      await _tap(tester, find.text('Maquis Cocody'));

      expect(
        find.textContaining('Client hors de votre secteur (zone Cocody)'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Casier (12)'));
      // Sans motif : refusé avant l'envoi.
      await _tap(tester, find.textContaining('Valider · 3'));
      // Le message est en haut de l'écran.
      await tester.scrollUntilVisible(
        find.text('Indiquez le motif de cette vente hors zone.'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Indiquez le motif de cette vente hors zone.'),
        findsOneWidget,
      );
      expect(repo.saleBodies, isEmpty);

      await _see(
        tester,
        find.widgetWithText(TextField, 'Motif de la vente hors zone *'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Motif de la vente hors zone *'),
        'Rupture urgente',
      );
      await _settle(tester);
      await _tap(tester, find.textContaining('Valider · 3'));
      await _tap(tester, find.text('Valider la vente').last);
      expect(repo.saleBodies.single['outOfZoneReason'], 'Rupture urgente');
      expect(repo.saleBodies.single['outletId'], 'o-maquis');
      expect(repo.saleBodies.single['lines'], [
        {'productId': 'p-coca', 'quantity': 12},
      ]);
      await _close(tester);
    },
  );
}
