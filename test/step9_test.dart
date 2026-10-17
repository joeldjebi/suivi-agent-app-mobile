import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/app.dart';
import 'package:suivi_agent/core/app_version.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/sync.dart';
import 'package:suivi_agent/core/tracking.dart';
import 'package:suivi_agent/design/components.dart';

import 'fakes.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('GPS adaptatif : économie, immobilité, mouvement', () {
    PowerMode mode({double? battery, bool charging = false, int still = 0}) =>
        LocationTracker.decideMode(
          battery: battery,
          charging: charging,
          stillFor: Duration(minutes: still),
        );
    expect(mode(battery: 0.8), PowerMode.normal);
    expect(mode(battery: 0.8, still: 6), PowerMode.still);
    expect(mode(battery: 0.15), PowerMode.saver);
    // En charge : pas d'économie.
    expect(mode(battery: 0.15, charging: true), PowerMode.normal);
    // Batterie inconnue : suivi normal.
    expect(mode(), PowerMode.normal);
  });

  test('versions comparées partie par partie', () {
    expect(compareVersions('1.10.0', '1.9.3'), greaterThan(0));
    expect(compareVersions('1.2.0', '1.2.0'), 0);
    expect(compareVersions('1.0.0', '1.2.0'), lessThan(0));
  });

  test('la batterie part avec chaque position', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FakeRepository();
    final sync = SyncService(
      db,
      repo,
      connectivity: const Stream<List<ConnectivityResult>>.empty(),
    );
    await db
        .into(db.pendingPositions)
        .insert(
          PendingPositionsCompanion.insert(
            dayId: 'd1',
            lat: 5.32,
            lng: -4.02,
            accuracy: 10,
            recordedAt: DateTime.utc(2026, 10, 7, 9),
            battery: const Value(0.42),
          ),
        );
    await sync.flush();
    expect(repo.positions.single.single['batteryLevel'], 0.42);
  });

  testWidgets('mise à jour obligatoire : l’app est bloquée sur son écran', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SuiviAgentApp)),
    );
    container
        .read(updateProvider.notifier)
        .requireUpdate(
          storeUrl: 'https://exemple.ci/app.apk',
          version: '1.2.0',
        );
    await _settle(tester);
    expect(find.text('Mise à jour nécessaire'), findsOneWidget);
    expect(find.textContaining('version 1.2.0'), findsOneWidget);
    expect(find.text('Télécharger la mise à jour'), findsOneWidget);
    expect(find.byType(AppNavBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('nouvelle version disponible : invitation dans le profil', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SuiviAgentApp)),
    );
    container.read(updateProvider.notifier).state = const UpdateInfo(
      required: false,
      version: '1.3.0',
      storeUrl: 'https://exemple.ci/app.apk',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AppNavBar),
        matching: find.text('Profil'),
      ),
    );
    await _settle(tester);
    expect(find.text('Nouvelle version 1.3.0 disponible.'), findsOneWidget);
    expect(find.text('Mettre à jour'), findsOneWidget);
    // L'app reste utilisable.
    expect(find.byType(AppNavBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  test('importance de la mise à jour : bandeau, fenêtre ou blocage', () {
    Map<String, dynamic> info({
      String? min,
      String? latest = '1.3.0',
      String importance = 'minor',
      String? notes,
    }) => {
      'minVersion': min,
      'latestVersion': latest,
      'importance': importance,
      'releaseNotes': notes,
      'androidUrl': 'https://exemple.ci/app.apk',
      'iosUrl': 'https://apps.apple.com/app/id1',
    };
    // À jour : rien.
    expect(updateFor('1.3.0', info(), ios: false), isNull);
    // Mineure : proposée, sans fenêtre.
    final minor = updateFor('1.2.0', info(), ios: false)!;
    expect((minor.required, minor.prompt), (false, false));
    expect(minor.storeUrl, 'https://exemple.ci/app.apk');
    // Recommandée : fenêtre, avec les nouveautés.
    final recommended = updateFor(
      '1.2.0',
      info(importance: 'recommended', notes: '  Carte plus rapide. '),
      ios: true,
    )!;
    expect((recommended.required, recommended.prompt), (false, true));
    expect(recommended.releaseNotes, 'Carte plus rapide.');
    expect(recommended.storeUrl, 'https://apps.apple.com/app/id1');
    // Critique : bloquée, même sans version minimale reçue.
    expect(
      updateFor('1.2.0', info(importance: 'critical'), ios: false)!.required,
      isTrue,
    );
    // Sous la version minimale : bloquée, on propose la dernière version.
    final old = updateFor('1.0.0', info(min: '1.1.0'), ios: false)!;
    expect((old.required, old.version), (true, '1.3.0'));
    // Importance inconnue (ancienne API) : mineure.
    expect(
      updateFor('1.2.0', info(importance: 'autre'), ios: false)!.importance,
      UpdateImportance.minor,
    );
  });

  testWidgets(
    'mise à jour recommandée : fenêtre une fois par jour, « Plus tard »',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
      await _settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SuiviAgentApp)),
      );
      const update = UpdateInfo(
        required: false,
        version: '1.4.0',
        storeUrl: 'https://exemple.ci/app.apk',
        importance: UpdateImportance.recommended,
        releaseNotes: 'Envoi des commandes plus rapide.',
      );
      container.read(updateProvider.notifier).state = update;
      await _settle(tester);
      expect(find.text('Nouvelle version 1.4.0'), findsOneWidget);
      expect(find.text('Envoi des commandes plus rapide.'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsOneWidget);
      // Grande police : la fenêtre défile jusqu'au bouton.
    await tester.ensureVisible(find.text('Plus tard'));
    await _settle(tester);
    await tester.tap(find.text('Plus tard'));
      await _settle(tester);
      expect(find.text('Nouvelle version 1.4.0'), findsNothing);
      // L'app reste utilisable ; la fenêtre ne revient pas le même jour.
      expect(find.byType(AppNavBar), findsOneWidget);
      container.read(updateProvider.notifier).state = null;
      await _settle(tester);
      container.read(updateProvider.notifier).state = update;
      await _settle(tester);
      expect(find.text('Nouvelle version 1.4.0'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('mise à jour critique : écran bloquant avec les nouveautés', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SuiviAgentApp)),
    );
    container.read(updateProvider.notifier).state = const UpdateInfo(
      required: true,
      version: '1.4.0',
      storeUrl: 'https://exemple.ci/app.apk',
      importance: UpdateImportance.critical,
      releaseNotes: 'Correction de sécurité.',
    );
    await _settle(tester);
    expect(find.text('Mise à jour nécessaire'), findsOneWidget);
    expect(find.text('Nouveautés'), findsOneWidget);
    expect(find.text('Correction de sécurité.'), findsOneWidget);
    expect(find.text('Plus tard'), findsNothing);
    expect(find.byType(AppNavBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
