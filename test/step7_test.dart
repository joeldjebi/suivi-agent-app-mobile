import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/form_drafts.dart';
import 'package:suivi_agent/core/models.dart';
import 'package:suivi_agent/core/sync.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/features/day/week_screen.dart';

import 'fakes.dart';

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

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppNavBar),
      matching: find.text('Missions'),
    ),
  );
  await _settle(tester);
  await _tapText(tester, '120 visites cette semaine');
}

const _photoField = {
  'key': 'vitrine',
  'label': 'Photo de la vitrine',
  'type': 'photo',
  'required': true,
};

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('type de champ inconnu : l’app reste utilisable', () {
    final field = MissionField.fromJson({
      'key': 'signature',
      'label': 'Signature',
      'type': 'signature',
      'required': false,
    });
    expect(field.type, FieldType.unsupported);
    expect(MissionField.fromJson({..._photoField}).type, FieldType.photo);
  });

  test(
    'envoi : la photo part avant le formulaire, qui n’en garde que l’identifiant',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FakeRepository();
      final sync = SyncService(
        db,
        repo,
        connectivity: const Stream<List<ConnectivityResult>>.empty(),
      );
      final photo = (await FakePhotoCapture().take())!;
      await db
          .into(db.pendingSubmissions)
          .insert(
            PendingSubmissionsCompanion.insert(
              clientId: 's1',
              missionId: 'm1',
              missionTitle: 'Vitrines',
              dataJson: jsonEncode({
                'commerce': 'Boutique Awa',
                'vitrine': photo.toJson(),
              }),
              submittedAt: DateTime.utc(2026, 10, 7, 14, 33),
              lat: const Value(5.32),
              lng: const Value(-4.02),
            ),
          );
      await sync.flush();
      expect(repo.uploadedPhotos.single.clientId, photo.clientId);
      expect(repo.submittedForms.single['data'], {
        'commerce': 'Boutique Awa',
        'vitrine': 'photo-1',
      });
      // Envoyée : retirée du téléphone.
      expect(File(photo.path).existsSync(), isFalse);
      expect(await db.countPendingPositions(), 0);
    },
  );

  test('photo disparue du téléphone : refusé avec un motif clair', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FakeRepository();
    final sync = SyncService(
      db,
      repo,
      connectivity: const Stream<List<ConnectivityResult>>.empty(),
    );
    final photo = (await FakePhotoCapture().take())!;
    File(photo.path).deleteSync();
    await db
        .into(db.pendingSubmissions)
        .insert(
          PendingSubmissionsCompanion.insert(
            clientId: 's2',
            missionId: 'm1',
            missionTitle: 'Vitrines',
            dataJson: jsonEncode({'vitrine': photo.toJson()}),
            submittedAt: DateTime.utc(2026, 10, 7),
          ),
        );
    await sync.flush();
    final row = (await db.select(db.pendingSubmissions).get()).single;
    expect(row.errorCode, 'PHOTO_MISSING');
    expect(repo.submittedForms, isEmpty);
  });

  testWidgets('champ photo : prise, aperçu avec la position, envoi', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository()..extraFields = [_photoField];
    final camera = FakePhotoCapture();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(submissionRequiresDay: false)),
        repo: repo,
        photos: camera,
      ),
    );
    await _settle(tester);
    await _openForm(tester);
    await _tapText(tester, 'Nouveau formulaire');
    await tester.enterText(find.byType(TextFormField).first, 'Boutique Awa');
    await tester.tap(find.text('Oui'));
    await _settle(tester);

    // Photo obligatoire.
    await _tapText(tester, 'Enregistrer');
    expect(find.text('Photo obligatoire'), findsOneWidget);

    // Le message de champs manquants disparaît avant la suite.
    await tester.pump(const Duration(seconds: 5));
    await _tapText(tester, 'Prendre la photo');
    expect(camera.taken, 1);
    expect(find.textContaining('position à 8 m près'), findsOneWidget);
    expect(find.text('Retirer'), findsOneWidget);

    await _tapText(tester, 'Enregistrer');
    await _settle(tester);
    expect(find.text('Formulaire envoyé.'), findsOneWidget);
    expect(repo.submittedForms.single['data'], {
      'commerce': 'Boutique Awa',
      'interesse': true,
      'vitrine': 'photo-1',
    });
    // Envoyé : plus de brouillon.
    expect(await FormDrafts.read('m1'), isNull);
    await _close(tester);
  });

  testWidgets('brouillon : saisie gardée, reprise puis effacée', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository();
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(submissionRequiresDay: false)),
        repo: repo,
      ),
    );
    await _settle(tester);
    await _openForm(tester);
    await _tapText(tester, 'Nouveau formulaire');
    await tester.enterText(find.byType(TextFormField).first, 'Boutique Awa');
    await _settle(tester);
    // On quitte sans envoyer.
    await tester.tap(find.byType(BackButton));
    await _settle(tester);

    expect(find.text('Reprendre mon brouillon'), findsOneWidget);
    expect(find.textContaining('1 champ rempli'), findsOneWidget);
    await _tapText(tester, 'Reprendre mon brouillon');
    expect(find.textContaining('Brouillon repris'), findsOneWidget);
    expect(find.text('Boutique Awa'), findsOneWidget);

    await _tapText(tester, 'Effacer');
    // Confirmation dans la feuille.
    await tester.tap(find.text('Effacer').last);
    await _settle(tester);
    expect(find.text('Boutique Awa'), findsNothing);
    expect(await FormDrafts.read('m1'), isNull);
    await _close(tester);
  });

  testWidgets('ma semaine : heures, objectif, comparaison et missions', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository()
      ..weekJson = {
        'from': '2026-10-05',
        'to': '2026-10-11',
        'today': '2026-10-07',
        'objectiveMinutes': 480,
        'days': [
          for (final (i, s) in [27000, 30600, 9000, 0, 0, 0, 0].indexed)
            {
              'date': '2026-10-${(5 + i).toString().padLeft(2, '0')}',
              'workedSeconds': s,
              'zones': s > 0 ? ['Plateau'] : [],
              'forms': s > 0 ? 4 : 0,
              'rejected': i == 1 ? 1 : 0,
              'future': i > 2,
            },
        ],
        'totals': {
          'workedSeconds': 66600,
          'daysWorked': 3,
          'forms': 12,
          'rejected': 1,
          'objectiveSeconds': 86400,
        },
        'previous': {
          'workedSeconds': 59400,
          'daysWorked': 3,
          'forms': 9,
          'rejected': 0,
        },
        'missions': [
          {'id': 'm1', 'title': '120 visites cette semaine', 'forms': 12},
        ],
      };
    await tester.pumpWidget(
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
    );
    await _settle(tester);
    // Raccourci depuis « Ma journée ».
    expect(find.byType(WeekShortcut), findsOneWidget);
    expect(find.textContaining('18 h 30 · 3 jours'), findsOneWidget);
    await _tapText(tester, 'Ma semaine');

    expect(find.text('Cette semaine'), findsOneWidget);
    expect(find.text('18 h 30'), findsWidgets);
    expect(find.text('sur 24 h visées'), findsOneWidget);
    expect(
      find.text('+2 h par rapport à la semaine précédente'),
      findsOneWidget,
    );
    expect(find.text('1 rejeté'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('12 formulaires'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('12 formulaires'), findsOneWidget);
    await _close(tester);
  });
}
