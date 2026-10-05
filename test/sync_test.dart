import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivi_agent/core/api_client.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/sync.dart';

import 'fakes.dart';

void main() {
  late AppDatabase db;
  late FakeRepository repo;
  late SyncService sync;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = FakeRepository();
    sync = SyncService(
      db,
      repo,
      connectivity: const Stream<List<ConnectivityResult>>.empty(),
    );
  });

  tearDown(() => db.close());

  Future<void> addPositions(int n, {String day = 'd1'}) async {
    for (var i = 0; i < n; i++) {
      await db
          .into(db.pendingPositions)
          .insert(
            PendingPositionsCompanion.insert(
              dayId: day,
              lat: 5.32,
              lng: -4.02,
              accuracy: 10,
              isMocked: const Value(false),
              recordedAt: DateTime.utc(2026, 10, 2, 8, 0, i),
            ),
          );
    }
  }

  test('envoie les positions par lots de 200 puis les supprime', () async {
    await addPositions(250);
    await sync.flush();
    expect(repo.positions.map((b) => b.length), [200, 50]);
    expect(await db.countPendingPositions(), 0);
    expect(sync.online, isTrue);
  });

  test('sans réseau, garde les positions pour plus tard', () async {
    await addPositions(3);
    repo.positionsError = ApiException('Pas de connexion');
    await sync.flush();
    expect(await db.countPendingPositions(), 3);
    expect(sync.online, isFalse);

    repo.positionsError = null;
    await sync.flush();
    expect(await db.countPendingPositions(), 0);
  });

  test(
    'un lot refusé définitivement (journée inconnue) est abandonné',
    () async {
      await addPositions(2);
      repo.positionsError = ApiException(
        'Journée introuvable',
        status: 404,
        code: 'NOT_FOUND',
      );
      await sync.flush();
      expect(await db.countPendingPositions(), 0);
    },
  );
}
