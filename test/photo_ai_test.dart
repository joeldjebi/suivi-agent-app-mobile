import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/models.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/features/missions/mission_form_screen.dart';

import 'fakes.dart';
import 'outlet_fakes.dart';

/// IA photo dans l'app : photo du rayon analysée sur place, relevé pré-rempli à vérifier.

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
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await _settle(tester);
}

/// Remonte la liste jusqu'à l'élément (le relevé est au-dessus de la photo).
Future<void> _up(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    finder,
    -200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
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

const _shelfField = {
  'key': 'rayon',
  'label': 'Photo du rayon',
  'type': 'photo',
  'required': false,
  'shelf': true,
};

Future<void> _openForm(WidgetTester tester) async {
  await _tap(
    tester,
    find.descendant(
      of: find.byType(AppNavBar),
      matching: find.text('Missions'),
    ),
  );
  await _tap(tester, find.text('Relevé des boissons'));
  await _tap(tester, find.text('Nouveau formulaire'));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    PhotoInput.pollInterval = const Duration(milliseconds: 50);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'photo du rayon : analyse sur place, relevé pré-rempli, correction, envoi',
    (tester) async {
      _phone(tester);
      final repo = ReadingsRepo()..moreFields = [_shelfField];
      repo.shelfAnalyses['photo-1'] = [
        const ShelfAnalysis(status: 'running'),
        const ShelfAnalysis(
          status: 'done',
          score: 72,
          notes: 'Coca bien placé, Pepsi absent.',
          products: [
            ShelfProduct(
              productId: 'p-coca',
              present: true,
              facings: 6,
              price: 300,
            ),
            ShelfProduct(productId: 'p-pepsi', present: false),
            // Produit hors de ce relevé : ignoré.
            ShelfProduct(productId: 'p-autre', present: true),
          ],
        ),
      ];
      await tester.pumpWidget(
        testApp(
          auth: () => SignedInAuth(
            fakeMe(
              features: {...outletFeatures, 'photo_ai'},
              submissionRequiresDay: false,
            ),
          ),
          repo: repo,
          photos: FakePhotoCapture(),
        ),
      );
      await _settle(tester);
      await _openForm(tester);
      expect(find.text('0/2 relevé'), findsOneWidget);

      await _tap(tester, find.text('Prendre la photo'));
      await _tap(tester, find.text('Analyser le rayon avec l’IA'));
      await _settle(tester);

      // Photo envoyée tout de suite, marquée « rayon » ; résultat de l'IA.
      expect(repo.photoKinds['photo-1'], 'shelf');
      expect(find.text('Score du rayon : 72 / 100'), findsOneWidget);
      expect(find.text('Coca bien placé, Pepsi absent.'), findsOneWidget);
      await _up(tester, find.text('2/2 relevés'));
      expect(find.text('2/2 relevés'), findsOneWidget);
      expect(find.text('Proposé par l’IA, à vérifier'), findsNWidgets(2));
      expect(
        find.widgetWithText(TextField, '300'),
        findsOneWidget,
        reason: 'prix lu par l’IA pré-rempli',
      );

      // L'agent corrige le prix du Coca : la marque « IA » disparaît pour ce produit.
      await tester.enterText(find.widgetWithText(TextField, '300'), '350');
      await _settle(tester);
      expect(find.text('Proposé par l’IA, à vérifier'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await _tap(tester, find.text('Enregistrer'));
      // Même photo réutilisée à l'envoi : pas de doublon.
      expect(repo.uploadedPhotos, hasLength(1));
      expect(repo.submittedForms.single['data'], {
        'releve': {
          'p-coca': {'presence': true, 'price': 350},
          'p-pepsi': {'presence': false},
        },
        'rayon': 'photo-1',
      });
      await _close(tester);
    },
  );

  testWidgets(
    'saisie de l’agent jamais remplacée ; analyse impossible : explication',
    (tester) async {
      _phone(tester);
      final repo = ReadingsRepo()..moreFields = [_shelfField];
      repo.shelfAnalyses['photo-1'] = [
        const ShelfAnalysis(
          status: 'done',
          score: 40,
          products: [
            ShelfProduct(productId: 'p-coca', present: false),
            ShelfProduct(productId: 'p-pepsi', present: true, price: 250),
          ],
        ),
      ];
      repo.shelfAnalyses['photo-2'] = [
        const ShelfAnalysis(
          status: 'skipped',
          skipLabel: 'Quota mensuel de photos analysées atteint',
        ),
      ];
      final camera = FakePhotoCapture();
      await tester.pumpWidget(
        testApp(
          auth: () => SignedInAuth(
            fakeMe(
              features: {...outletFeatures, 'photo_ai'},
              submissionRequiresDay: false,
            ),
          ),
          repo: repo,
          photos: camera,
        ),
      );
      await _settle(tester);
      await _openForm(tester);
      // L'agent a déjà relevé le Coca présent.
      await _tap(tester, find.bySemanticsLabel('Présent').first);
      await _tap(tester, find.text('Prendre la photo'));
      await _tap(tester, find.text('Analyser le rayon avec l’IA'));
      await _settle(tester);
      // Le relevé est au-dessus de la photo.
      await _up(tester, find.text('Proposé par l’IA, à vérifier'));
      expect(find.text('Proposé par l’IA, à vérifier'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));

      // Nouvelle photo : quota atteint, l'agent remplit lui-même.
      await _tap(tester, find.text('Reprendre'));
      await _tap(tester, find.text('Analyser le rayon avec l’IA'));
      await _settle(tester);
      expect(
        find.text('Pas d’analyse : Quota mensuel de photos analysées atteint.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await _tap(tester, find.text('Enregistrer'));
      expect(repo.submittedForms.single['data'], {
        'releve': {
          'p-coca': {'presence': true},
          'p-pepsi': {'presence': true, 'price': 250},
        },
        'rayon': 'photo-2',
      });
      await _close(tester);
    },
  );

  testWidgets('sans l’IA photo dans la formule : pas de bouton d’analyse', (
    tester,
  ) async {
    _phone(tester);
    final repo = ReadingsRepo()..moreFields = [_shelfField];
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(
          fakeMe(features: outletFeatures, submissionRequiresDay: false),
        ),
        repo: repo,
        photos: FakePhotoCapture(),
      ),
    );
    await _settle(tester);
    await _openForm(tester);
    await _tap(tester, find.text('Prendre la photo'));
    expect(find.text('Analyser le rayon avec l’IA'), findsNothing);
    await _close(tester);
  });
}
