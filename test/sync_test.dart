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

  Future<String> addForm({String id = 'c1'}) async {
    await db
        .into(db.pendingSubmissions)
        .insert(
          PendingSubmissionsCompanion.insert(
            clientId: id,
            missionId: 'm1',
            missionTitle: '120 visites',
            dataJson: '{"commerce":"Boutique Awa"}',
            submittedAt: DateTime.utc(2026, 10, 2, 9),
          ),
        );
    return id;
  }

  test(
    'formulaire refusé en arrière-plan : gardé avec motif et code, agent prévenu',
    () async {
      final notified = <String>[];
      sync = SyncService(
        db,
        repo,
        connectivity: const Stream<List<ConnectivityResult>>.empty(),
        onRejected: (row, e) => notified.add('${row.missionTitle}|${e.code}'),
      );
      await addForm();
      repo.submitError = ApiException(
        'Démarrez votre journée pour envoyer un formulaire',
        status: 409,
        code: 'DAY_REQUIRED',
      );
      await sync.flush();
      final rows = await db.select(db.pendingSubmissions).get();
      expect(
        rows.single.error,
        'Démarrez votre journée pour envoyer un formulaire',
      );
      expect(rows.single.errorCode, 'DAY_REQUIRED');
      expect(notified, ['120 visites|DAY_REQUIRED']);
      expect(await db.watchRejected().first, hasLength(1));
      // Refusé : plus jamais renvoyé automatiquement, plus compté « en attente ».
      repo.submitError = null;
      await sync.flush();
      expect(repo.submittedForms, isEmpty);
      expect(await db.watchPendingCount().first, 0);
      expect(canRetrySubmission('DAY_REQUIRED'), isTrue);
      expect(canRetrySubmission('MISSION_CLOSED'), isFalse);
    },
  );

  test(
    'sans réseau ou serveur en panne : le formulaire attend, sans refus',
    () async {
      await addForm();
      repo.submitError = ApiException('Pas de connexion');
      await sync.flush();
      repo.submitError = ApiException('Erreur serveur', status: 503);
      await sync.flush();
      final rows = await db.select(db.pendingSubmissions).get();
      expect(rows.single.error, isNull);
      repo.submitError = null;
      await sync.flush();
      expect(repo.submittedForms.single['clientId'], 'c1');
      expect(await db.select(db.pendingSubmissions).get(), isEmpty);
    },
  );

  test(
    'envoi immédiat : accepté, en attente, ou refusé et retiré du téléphone',
    () async {
      expect(await sync.submitNow(await addForm(id: 'ok')), SubmitOutcome.sent);
      repo.submitError = ApiException('Pas de connexion');
      expect(
        await sync.submitNow(await addForm(id: 'off')),
        SubmitOutcome.queued,
      );
      expect(sync.online, isFalse);
      repo.submitError = ApiException(
        'Cette mission se fait à : Plateau',
        status: 409,
        code: 'WRONG_ZONE',
      );
      await expectLater(
        sync.submitNow(await addForm(id: 'ko')),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'WRONG_ZONE'),
        ),
      );
      final left = await db.select(db.pendingSubmissions).get();
      expect(left.map((r) => r.clientId), ['off']);
    },
  );
}
