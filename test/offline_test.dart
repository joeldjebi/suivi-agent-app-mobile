import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/app.dart';
import 'package:suivi_agent/core/api_client.dart';
import 'package:suivi_agent/core/network_status.dart';
import 'package:suivi_agent/core/session.dart';
import 'package:suivi_agent/features/shell/offline_banner.dart';

import 'fakes.dart';

/// Serveur simulé : répond, ou ne répond plus (réseau coupé).
class _Adapter implements HttpClientAdapter {
  bool online = true;
  final responses = <String, Object>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!online) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Réseau coupé',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(responses[options.uri.path] ?? {}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryCache implements ResponseCache {
  final store = <String, String>{};

  @override
  Future<String?> get(String key) async => store[key];

  @override
  Future<void> put(String key, String body) async => store[key] = body;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('hors ligne : la dernière réponse reçue est rendue', () async {
    final adapter = _Adapter()
      ..responses['/missions'] = {
        'items': [
          {'id': 'm1'},
        ],
      };
    final dio = Dio(BaseOptions(baseUrl: 'http://serveur.test'))
      ..httpClientAdapter = adapter;
    final api = ApiClient(SessionStore(), dio: dio)..cache = _MemoryCache();
    var reachable = 0;
    var unreachable = 0;
    api.onReachable = () => reachable++;
    api.onUnreachable = () => unreachable++;

    final online = await api.get<Map<String, dynamic>>(
      '/missions',
      query: {'status': 'open', 'limit': 50},
    );
    expect(online['items'], hasLength(1));
    expect(reachable, 1);

    adapter.online = false;
    // Même écran, paramètres dans un autre ordre : même mémoire.
    final offline = await api.get<Map<String, dynamic>>(
      '/missions',
      query: {'limit': 50, 'status': 'open'},
    );
    expect(offline, online);
    expect(unreachable, 1);

    // Écran jamais ouvert avec du réseau : message court.
    await expectLater(
      api.get<Map<String, dynamic>>('/pay/me'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.isNetwork, 'isNetwork', isTrue)
            .having(
              (e) => e.message,
              'message',
              'Vous êtes hors ligne. Réessayez au retour du réseau.',
            ),
      ),
    );
  });

  test('message du bandeau selon l’âge des données', () {
    final now = DateTime(2026, 10, 7, 16);
    expect(
      offlineMessage(DateTime(2026, 10, 7, 14, 32), now),
      'Hors ligne · Données de votre dernière connexion (14:32)',
    );
    expect(
      offlineMessage(DateTime(2026, 10, 6, 18, 10), now),
      'Hors ligne · Données de votre dernière connexion (hier à 18:10)',
    );
    expect(
      offlineMessage(null, now),
      'Hors ligne · Données enregistrées sur le téléphone',
    );
  });

  testWidgets('bandeau discret, écran conservé, retiré au retour du réseau', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(auth: () => SignedInAuth(fakeMe())));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SuiviAgentApp)),
    );
    expect(find.textContaining('Hors ligne'), findsNothing);

    container.read(networkProvider.notifier).unreachable();
    await tester.pump();
    expect(find.textContaining('Hors ligne ·'), findsOneWidget);
    // L'écran reste affiché dessous.
    expect(find.text('Journée'), findsWidgets);

    container.read(networkProvider.notifier).reachable();
    await tester.pump();
    expect(find.textContaining('Hors ligne'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
