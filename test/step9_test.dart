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
import 'package:suivi_agent/core/providers.dart';
import 'package:suivi_agent/core/sync.dart';
import 'package:suivi_agent/core/tracking.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/features/shell/update_screen.dart';

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
    await _settle(tester);
    // Mineure : fenêtre affichée tout de suite, qu'on peut fermer.
    expect(find.text('Nouvelle version 1.3.0'), findsOneWidget);
    await tester.ensureVisible(find.text('Plus tard'));
    await _settle(tester);
    await tester.tap(find.text('Plus tard'));
    await _settle(tester);
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
    // Mineure : fenêtre qu'on peut fermer, de nouveau proposée le lendemain.
    final minor = updateFor('1.2.0', info(), ios: false)!;
    expect((minor.required, minor.prompt), (false, true));
    expect(minor.remindEvery, const Duration(days: 1));
    expect(minor.storeUrl, 'https://exemple.ci/app.apk');
    // Recommandée : fenêtre, avec les nouveautés.
    final recommended = updateFor(
      '1.2.0',
      info(importance: 'recommended', notes: '  Carte plus rapide. '),
      ios: true,
    )!;
    expect((recommended.required, recommended.prompt), (false, true));
    expect(recommended.releaseNotes, 'Carte plus rapide.');
    expect(recommended.remindEvery, const Duration(hours: 1));
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

  test('fenêtre de mise à jour : tout de suite, puis selon l’importance', () {
    final now = DateTime(2026, 10, 17, 10);
    String mark(String version, String importance, DateTime at) =>
        '$version|$importance|${at.millisecondsSinceEpoch}';
    const minor = UpdateInfo(required: false, version: '1.4.0');
    const recommended = UpdateInfo(
      required: false,
      version: '1.4.0',
      importance: UpdateImportance.recommended,
    );
    // Jamais proposée : tout de suite.
    expect(UpdatePrompt.due(minor, null, now), isTrue);
    // Mineure : une fois par jour.
    final earlier = now.subtract(const Duration(hours: 2));
    expect(
      UpdatePrompt.due(minor, mark('1.4.0', 'minor', earlier), now),
      isFalse,
    );
    expect(
      UpdatePrompt.due(
        minor,
        mark('1.4.0', 'minor', now.subtract(const Duration(days: 1))),
        now,
      ),
      isTrue,
    );
    // Recommandée : toutes les heures.
    expect(
      UpdatePrompt.due(
        recommended,
        mark('1.4.0', 'recommended', now.subtract(const Duration(minutes: 30))),
        now,
      ),
      isFalse,
    );
    expect(
      UpdatePrompt.due(recommended, mark('1.4.0', 'recommended', earlier), now),
      isTrue,
    );
    // L'éditeur change la version ou l'importance : tout de suite.
    expect(
      UpdatePrompt.due(recommended, mark('1.4.0', 'minor', now), now),
      isTrue,
    );
    expect(UpdatePrompt.due(minor, mark('1.3.0', 'minor', now), now), isTrue);
  });

  testWidgets('couleur changée par la structure : appliquée sans redémarrer', (
    tester,
  ) async {
    _phone(tester);
    final repo = _BrandingRepository();
    await tester.pumpWidget(
      testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
    );
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SuiviAgentApp)),
    );
    Color primary() =>
        Theme.of(tester.element(find.byType(AppNavBar))).colorScheme.primary;
    final before = primary();

    // Annonce « branding » : l'app relit l'apparence et change de thème.
    repo.color = '#B42318';
    await container.read(authProvider.notifier).reloadBranding();
    await _settle(tester);
    expect(container.read(brandingProvider).primary, const Color(0xFFB42318));
    expect(primary(), isNot(before));

    // Relecture de contrôle sans changement : même apparence, rien n'est reconstruit.
    final same = container.read(brandingProvider);
    await container.read(authProvider.notifier).reloadBranding();
    expect(identical(container.read(brandingProvider), same), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

/// Apparence servie par la structure, modifiable pendant le test.
class _BrandingRepository extends FakeRepository {
  String color = '#0F766E';
  int version = 1;
  String? _last;

  @override
  Future<Map<String, dynamic>> branding() async {
    if (_last != null && _last != color) version++;
    _last = color;
    return {
      'displayName': 'Démo Abidjan',
      'primaryColor': color,
      'onPrimaryColor': '#FFFFFF',
      'welcomeMessage': 'Bonne journée sur le terrain !',
      'supportPhone': null,
      'logoUrl': null,
      'version': version,
    };
  }
}
