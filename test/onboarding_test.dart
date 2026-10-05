import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/features/onboarding/onboarding_data.dart';
import 'package:suivi_agent/features/onboarding/onboarding_screen.dart';

class _Source implements OnboardingSource {
  _Source(this.content);
  OnboardingContent? content;

  @override
  Future<OnboardingContent?> fetch() async => content;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OnboardingContent _content(int version, {bool enabled = true}) =>
    OnboardingContent(
      enabled: enabled,
      version: version,
      slides: OnboardingContent.defaults.slides,
    );

Future<OnboardingState> _settled(ProviderContainer c) async {
  c.read(onboardingProvider);
  for (var i = 0; i < 50; i++) {
    final s = c.read(onboardingProvider);
    if (s is! OnboardingChecking) return s;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('vérification trop longue');
}

void main() {
  test('montré au premier lancement, puis à chaque nouvelle version', () async {
    SharedPreferences.setMockInitialValues({});
    final source = _Source(_content(1));
    var c = ProviderContainer(
      overrides: [onboardingSourceProvider.overrideWithValue(source)],
    );
    expect(await _settled(c), isA<OnboardingPending>());
    await c.read(onboardingProvider.notifier).complete();
    expect(c.read(onboardingProvider), isA<OnboardingDone>());
    c.dispose();

    // Même version : plus montré ; nouvelle version publiée : montré une fois.
    c = ProviderContainer(
      overrides: [onboardingSourceProvider.overrideWithValue(source)],
    );
    expect(await _settled(c), isA<OnboardingDone>());
    c.dispose();
    source.content = _content(2);
    c = ProviderContainer(
      overrides: [onboardingSourceProvider.overrideWithValue(source)],
    );
    expect(await _settled(c), isA<OnboardingPending>());
    c.dispose();

    // Désactivé par l'éditeur : jamais montré.
    source.content = _content(3, enabled: false);
    c = ProviderContainer(
      overrides: [onboardingSourceProvider.overrideWithValue(source)],
    );
    expect(await _settled(c), isA<OnboardingDone>());
    c.dispose();
  });

  test('premier lancement sans réseau : pages d’origine', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(
      overrides: [onboardingSourceProvider.overrideWithValue(_Source(null))],
    );
    final state = await _settled(c);
    expect(state, isA<OnboardingPending>());
    expect((state as OnboardingPending).content.slides, hasLength(3));
    c.dispose();
  });

  testWidgets('pages qui défilent, « Passer » masqué à la fin, « Commencer »', (
    tester,
  ) async {
    var done = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OnboardingScreen(
            content: OnboardingContent.defaults,
            onDone: () => done++,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Votre journée, en un geste'), findsOneWidget);
    expect(find.text('Suivant'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Vos missions sur le terrain'), findsOneWidget);

    // Glissement vers la dernière page.
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Toute l’équipe, en temps réel'), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);

    await tester.tap(find.text('Commencer'));
    expect(done, 1);
  });

  testWidgets('« Passer » termine dès la première page', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OnboardingScreen(
            content: OnboardingContent.defaults,
            onDone: () => done++,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Passer'));
    expect(done, 1);
  });
}
