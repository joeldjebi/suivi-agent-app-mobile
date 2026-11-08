import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/api_client.dart';
import 'package:suivi_agent/core/providers.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/features/van_sales/van_sales.dart';

import 'fakes.dart';
import 'outlet_fakes.dart';
import 'van_fakes.dart';

Finder _tab(String label) =>
    find.descendant(of: find.byType(AppNavBar), matching: find.text(label));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Listes paresseuses : fait défiler jusqu'à l'élément s'il n'est pas encore construit.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await _scrollTo(tester, finder);
    await _settle(tester);
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await _scrollTo(tester, finder);
  }
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

Widget _app(VanRepo repo, {FakeSharer? sharer}) => testApp(
  auth: () => SignedInAuth(fakeMe(features: vanFeatures)),
  repo: repo,
  overrides: [fileSharerProvider.overrideWithValue(sharer ?? FakeSharer())],
);

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

  testWidgets('onglet Camion selon la formule', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(features: orderFeatures)),
        repo: VanRepo(),
      ),
    );
    await _settle(tester);
    expect(_tab('Camion'), findsNothing);
    await _close(tester);

    await tester.pumpWidget(_app(VanRepo()));
    await _settle(tester);
    expect(_tab('Camion'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('mon camion : stock, journée, chargement reçu avec un écart', (
    tester,
  ) async {
    _phone(tester);
    final repo = VanRepo();
    await tester.pumpWidget(_app(repo));
    await _settle(tester);
    await _tap(tester, _tab('Camion'));

    expect(find.text('Mon camion'), findsOneWidget);
    expect(find.text('CAMION 1 · AB 1234 CI'), findsOneWidget);
    expect(find.text('Chargement à confirmer'), findsOneWidget);
    await _reveal(tester, find.textContaining('Remettez l’argent liquide'));
    expect(find.textContaining('Remettez l’argent liquide'), findsOneWidget);
    await _reveal(tester, find.text('24 bouteilles (2 casiers)'));
    expect(find.text('24 bouteilles (2 casiers)'), findsOneWidget);

    // Deux bouteilles cassées : l'agent corrige la quantité reçue.
    await _tap(tester, find.text('Vérifier et confirmer'));
    expect(find.text('Réception du chargement'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '22');
    await _settle(tester);
    await _tap(tester, find.text('Confirmer la réception'));
    expect(find.textContaining('1 écart signalé'), findsOneWidget);
    await _tap(tester, find.text('Confirmer').last);

    expect(repo.confirmBodies.single.$1, 'm-load');
    expect(repo.confirmBodies.single.$2['lines'], [
      {'productId': 'p-coca', 'received': 22},
    ]);
    expect(find.textContaining('Chargement reçu'), findsOneWidget);
    expect(find.text('Chargement à confirmer'), findsNothing);
    await _reveal(tester, find.text('46 bouteilles (3 casiers + 10)'));
    expect(find.text('46 bouteilles (3 casiers + 10)'), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
    'camion : vendre à un client, bientôt vide, épuisés, argent à remettre',
    (tester) async {
      _phone(tester);
      final repo = VanRepo()
        ..loadPending = false
        ..stock = {'p-coca': 24, 'p-fanta': 6, 'p-sprite': 0}
        ..outToday = {'p-coca': 12, 'p-sprite': 24};
      await tester.pumpWidget(_app(repo));
      await _settle(tester);
      await _tap(tester, _tab('Camion'));

      // L'argent liquide à remettre ressort.
      await _reveal(tester, find.textContaining('À remettre :'));
      expect(find.textContaining('À remettre :'), findsOneWidget);
      // Fanta : moins d'un casier ; Sprite : tout vendu, replié.
      await _reveal(tester, find.text('Bientôt vide'));
      expect(find.text('Bientôt vide'), findsOneWidget);
      expect(find.text('Tout vendu aujourd’hui'), findsNothing);
      await _tap(tester, find.text('Épuisés aujourd’hui (1)'));
      await _reveal(tester, find.text('Tout vendu aujourd’hui'));
      expect(find.text('Tout vendu aujourd’hui'), findsOneWidget);
      // Coca : 24 restent sur 36 de la journée.
      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((b) => b.value)
          .toList();
      expect(bars, contains(closeTo(24 / 36, 0.001)));

      // Vendre : les clients proches, puis la vente du client choisi.
      await _tap(tester, find.text('Vendre à un client'));
      expect(find.text('LES PLUS PROCHES'), findsOneWidget);
      await _tap(tester, find.text('Boutique Awa'));
      expect(
        find.textContaining('camion : 24 bouteilles (2 casiers)'),
        findsOneWidget,
      );
      await _close(tester);
    },
  );

  testWidgets('vente payée sur place, puis reçu partagé', (tester) async {
    _phone(tester);
    final repo = VanRepo();
    final sharer = FakeSharer();
    await tester.pumpWidget(_app(repo, sharer: sharer));
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));
    await _tap(tester, find.text('Boutique Awa'));
    await _tap(tester, find.text('Vendre'));

    // Le stock du camion à côté de chaque produit ; le payé suit le total.
    expect(
      find.textContaining('camion : 24 bouteilles (2 casiers)'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Casier (12)').first);
    expect(find.text('Payée en entier'), findsOneWidget);
    await _tap(tester, find.textContaining('Valider · 3'));
    await _tap(tester, find.text('Valider la vente').last);

    expect(repo.saleBodies.single['paidAmount'], 3600);
    expect(repo.saleBodies.single['paymentMethod'], 'cash');
    expect(repo.saleBodies.single['lines'], [
      {'productId': 'p-coca', 'quantity': 12},
    ]);
    // Le total ne part pas : le serveur recalcule.
    expect(repo.saleBodies.single.containsKey('total'), isFalse);
    expect(find.text('Vente CMD-000001'), findsOneWidget);

    await _tap(tester, find.text('Partager le reçu'));
    expect(sharer.shared.single, ('recu-CMD-000001.pdf', 4));
    await _close(tester);
  });

  testWidgets('crédit : refusé sans plafond, accepté dans la limite', (
    tester,
  ) async {
    _phone(tester);
    final repo = VanRepo();
    await tester.pumpWidget(_app(repo));
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));
    await _tap(tester, find.text('Boutique Awa'));
    await _reveal(tester, find.text('Pas de crédit'));
    expect(find.text('Pas de crédit'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Vendre'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await _settle(tester);
    await _tap(tester, find.text('Vendre'));
    await _tap(tester, find.text('Casier (12)').first);
    await tester.enterText(
      find.widgetWithText(TextField, 'Payé maintenant'),
      '1000',
    );
    await _settle(tester);
    await _reveal(
      tester,
      find.text(
        'Ce client n’a pas droit au crédit : la vente doit être payée en entier.',
      ),
    );
    expect(
      find.text(
        'Ce client n’a pas droit au crédit : la vente doit être payée en entier.',
      ),
      findsOneWidget,
    );
    expect(repo.saleBodies, isEmpty);
    await _close(tester);

    // Plafond de 5 000 F : 2 600 F à crédit passent.
    final withCredit = VanRepo()..creditLimit = 5000;
    await tester.pumpWidget(_app(withCredit));
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));
    await _tap(tester, find.text('Boutique Awa'));
    await _tap(tester, find.text('Vendre'));
    await _tap(tester, find.text('Casier (12)').first);
    await tester.enterText(
      find.widgetWithText(TextField, 'Payé maintenant'),
      '1000',
    );
    await _settle(tester);
    expect(
      find.textContaining(RegExp(r'À crédit : 2[\s\u202f\u00a0]600')),
      findsOneWidget,
    );
    await _tap(tester, find.textContaining('Valider · 3'));
    await _tap(tester, find.text('Valider la vente').last);
    expect(withCredit.saleBodies.single['paidAmount'], 1000);
    expect(find.text('Reste à payer'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('vente sans réseau : gardée, stock déduit, puis envoyée', (
    tester,
  ) async {
    _phone(tester);
    final repo = VanRepo()..saleError = ApiException('Vous êtes hors ligne.');
    await tester.pumpWidget(_app(repo));
    await _settle(tester);
    await _tap(tester, _tab('Points de vente'));
    await _tap(tester, find.text('Boutique Awa'));
    await _tap(tester, find.text('Vendre'));
    await _tap(tester, find.text('Casier (12)').first);
    await _tap(tester, find.textContaining('Valider · 3'));
    await _tap(tester, find.text('Valider la vente').last);
    expect(find.textContaining('envoyée au retour du réseau'), findsOneWidget);
    expect(repo.saleBodies, isEmpty);

    // Le camion tient compte de la vente pas encore envoyée.
    await _tap(tester, _tab('Camion'));
    expect(find.textContaining('1 opération en attente'), findsOneWidget);
    await _reveal(tester, find.text('12 bouteilles (1 casier)'));
    expect(find.text('12 bouteilles (1 casier)'), findsOneWidget);

    repo.saleError = null;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.runAsync(() => container.read(syncProvider).flush());
    await _settle(tester);
    expect(repo.saleBodies.single['paidAmount'], 3600);
    expect(repo.saleBodies.single.containsKey('total'), isFalse);
    expect(repo.saleBodies.single['clientId'], isNotNull);
    await _close(tester);
  });

  testWidgets('casse : motif obligatoire, stock du camion à jour', (
    tester,
  ) async {
    _phone(tester);
    final repo = VanRepo()..loadPending = false;
    await tester.pumpWidget(_app(repo));
    await _settle(tester);
    await _tap(tester, _tab('Camion'));
    await _tap(tester, find.text('Casse ou perte'));
    await tester.enterText(find.byType(TextField).first, '2');
    await _settle(tester);
    await _tap(tester, find.text('Déclarer la casse'));
    expect(find.textContaining('Indiquez le motif'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Motif'),
      'Bouteilles cassées',
    );
    await _settle(tester);
    await _tap(tester, find.text('Déclarer la casse'));
    await _tap(tester, find.text('Déclarer').last);
    expect(repo.lossBodies.single['note'], 'Bouteilles cassées');
    expect(repo.lossBodies.single['lines'], [
      {'productId': 'p-coca', 'quantity': 2},
    ]);
    await _close(tester);
  });
}
