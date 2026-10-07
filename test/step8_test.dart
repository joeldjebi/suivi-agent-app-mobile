import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/app.dart';
import 'package:suivi_agent/core/api_client.dart';
import 'package:suivi_agent/core/app_lock.dart';
import 'package:suivi_agent/core/push.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/features/safety/sos.dart';

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

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

/// Maintient le bouton d'alerte le temps voulu.
Future<void> _hold(WidgetTester tester, Duration duration) async {
  final button = find.byType(SosButton);
  await tester.ensureVisible(button);
  await tester.pump();
  final gesture = await tester.startGesture(tester.getCenter(button));
  for (var t = 0; t < duration.inMilliseconds; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await gesture.up();
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('notification d’alerte sécurité : l’agent ouvre son alerte', () {
    expect(pushRouteFor({'type': 'alert.sos_ack'}, leader: false), '/sos');
    expect(pushRouteFor({'type': 'alert.sos_closed'}, leader: false), '/sos');
    expect(pushRouteFor({'type': 'alert.sos'}, leader: true), '/alerts');
  });

  testWidgets(
    'alerte sécurité : maintien, envoi avec la position, annulation',
    (tester) async {
      _phone(tester);
      final repo = FakeRepository();
      await tester.pumpWidget(
        testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      );
      await _settle(tester);

      // Un appui bref ne déclenche rien.
      await _hold(tester, const Duration(milliseconds: 600));
      expect(repo.sosRaised, isEmpty);

      await _hold(tester, const Duration(milliseconds: 2200));
      expect(repo.sosRaised.single, {
        'lat': 5.32,
        'lng': -4.02,
        'accuracy': 8.0,
      });
      expect(find.text('Alerte envoyée'), findsOneWidget);
      expect(
        find.text('Votre chef et votre structure sont prévenus.'),
        findsOneWidget,
      );
      expect(find.text('Position transmise'), findsOneWidget);
      expect(find.text('Appeler Yao (mon chef)'), findsOneWidget);

      // Fausse alerte.
      await tester.ensureVisible(find.text('Fausse alerte ? Annuler l’alerte'));
      await tester.tap(find.text('Fausse alerte ? Annuler l’alerte'));
      await _settle(tester);
      await tester.tap(find.text('Annuler l’alerte').last);
      await _settle(tester);
      expect(repo.sosCancelled, 1);
      await _close(tester);
    },
  );

  testWidgets(
    'alerte sécurité sans réseau : en attente, appel direct proposé',
    (tester) async {
      _phone(tester);
      final repo = FakeRepository()
        ..sosError = ApiException('Pas de connexion');
      await tester.pumpWidget(
        testApp(auth: () => SignedInAuth(fakeMe()), repo: repo),
      );
      await _settle(tester);
      await _hold(tester, const Duration(milliseconds: 2200));
      expect(find.text('Pas de réseau'), findsOneWidget);
      expect(find.text('Appeler Yao (mon chef)'), findsOneWidget);

      // Le réseau revient : l'alerte part au nouvel essai.
      repo.sosError = null;
      await tester.pump(const Duration(seconds: 16));
      await _settle(tester);
      expect(repo.sosRaised, hasLength(1));
      expect(find.text('Alerte envoyée'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets('chef : alerte sécurité en tête, clôture', (tester) async {
    _phone(tester);
    final repo = FakeRepository()
      ..extraAlerts = [
        {
          'id': 'sosA',
          'type': 'sos',
          'agent': {
            'id': 'a9',
            'firstName': 'Rokia',
            'lastName': 'Touré',
            'phone': '+2250799000008',
          },
          'dayId': 'd9',
          'startedAt': DateTime.now()
              .subtract(const Duration(minutes: 3))
              .toUtc()
              .toIso8601String(),
          'resolvedAt': null,
          'data': {'lat': 5.32, 'lng': -4.02, 'message': 'Agression'},
          'acknowledgedAt': null,
          'acknowledgedBy': null,
          'note': null,
        },
      ];
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
        repo: repo,
      ),
    );
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SuiviAgentApp)),
    );
    container
        .read(pushInboxProvider.notifier)
        .put(const PushOpen({'type': 'alert.sos'}));
    await _settle(tester);
    await _settle(tester);
    // En tête de liste.
    final names = find.textContaining(RegExp(r'^(Rokia|Aminata|Koffi|Serge)'));
    expect((names.evaluate().first.widget as Text).data, 'Rokia Touré');
    await tester.tap(find.text('Rokia Touré'));
    await _settle(tester);
    expect(find.text('« Agression »'), findsOneWidget);
    await tester.ensureVisible(find.text('Clore l’alerte (agent en sécurité)'));
    await tester.tap(find.text('Clore l’alerte (agent en sécurité)'));
    await _settle(tester);
    expect(repo.closedAlerts, ['sosA']);
    await _close(tester);
  });

  testWidgets(
    'Face ID : activation, verrouillage au lancement, déverrouillage',
    (tester) async {
      _phone(tester);
      final bio = FakeBiometrics(isAvailable: true);
      await tester.pumpWidget(
        testApp(auth: () => SignedInAuth(fakeMe()), biometrics: bio),
      );
      await _settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.text('Profil'),
        ),
      );
      await _settle(tester);
      await tester.scrollUntilVisible(
        find.text('Déverrouiller avec Face ID'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Déverrouiller avec Face ID'));
      await _settle(tester);
      expect(bio.prompts, 1);
      expect(
        (await SharedPreferences.getInstance()).getBool(AppLock.key),
        isTrue,
      );
      await _close(tester);

      // Relance de l'app : verrouillée ; refus puis acceptation.
      bio.accept = false;
      await tester.pumpWidget(
        testApp(auth: () => SignedInAuth(fakeMe()), biometrics: bio),
      );
      await _settle(tester);
      expect(find.text('Vérification annulée ou refusée.'), findsOneWidget);
      bio.accept = true;
      await tester.tap(find.text('Déverrouiller avec Face ID'));
      await _settle(tester);
      expect(find.text('Application verrouillée'), findsNothing);
      expect(find.text('Vérification annulée ou refusée.'), findsNothing);
      await _close(tester);
    },
  );
}
