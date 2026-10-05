import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'database.dart';
import 'repository.dart';

/// Envoie les positions et les formulaires enregistrés sur le téléphone.
/// Rien n'est perdu sans réseau : l'envoi reprend dès que la connexion revient.
class SyncService extends ChangeNotifier {
  SyncService(
    this.db,
    this.repo, {
    Stream<List<ConnectivityResult>>? connectivity,
  }) : _connectivity = connectivity ?? Connectivity().onConnectivityChanged;

  final AppDatabase db;
  final Repository repo;
  final Stream<List<ConnectivityResult>> _connectivity;

  static const batchSize = 200;
  static const interval = Duration(seconds: 30);

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Future<void>? _running;
  bool online = true;
  DateTime? lastSyncAt;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(flush()));
    _connectivitySub ??= _connectivity.listen((results) {
      final wasOffline = !online;
      online = results.any((r) => r != ConnectivityResult.none);
      notifyListeners();
      if (online && wasOffline) unawaited(flush());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
  }

  /// Un seul envoi à la fois.
  Future<void> flush() =>
      _running ??= _flush().whenComplete(() => _running = null);

  Future<void> _flush() async {
    try {
      await _flushPositions();
      await _flushSubmissions();
      lastSyncAt = DateTime.now();
      online = true;
    } on ApiException catch (e) {
      if (e.isNetwork) online = false;
    }
    notifyListeners();
  }

  Future<void> _flushPositions() async {
    while (true) {
      final rows =
          await (db.select(db.pendingPositions)
                ..orderBy([(p) => OrderingTerm.asc(p.id)])
                ..limit(batchSize))
              .get();
      if (rows.isEmpty) return;
      final dayId = rows.first.dayId;
      final batch = rows.where((r) => r.dayId == dayId).toList();
      try {
        await repo.sendPositions(dayId, [
          for (final r in batch)
            {
              'lat': r.lat,
              'lng': r.lng,
              'accuracy': r.accuracy,
              if (r.speed != null) 'speed': r.speed,
              'isMocked': r.isMocked,
              'recordedAt': r.recordedAt.toUtc().toIso8601String(),
            },
        ]);
      } on ApiException catch (e) {
        // Journée inconnue ou lot refusé : ces points ne pourront jamais être acceptés.
        if (e.isNetwork || (e.status ?? 500) >= 500 || e.status == 401) rethrow;
      }
      // Acceptés, doublons ou hors journée : le serveur a tranché, on supprime.
      await (db.delete(
        db.pendingPositions,
      )..where((p) => p.id.isIn(batch.map((b) => b.id)))).go();
    }
  }

  Future<void> _flushSubmissions() async {
    final rows = await (db.select(
      db.pendingSubmissions,
    )..where((s) => s.error.isNull())).get();
    for (final row in rows) {
      try {
        await repo.submit(row.missionId, {
          'clientId': row.clientId,
          'data': jsonDecode(row.dataJson),
          if (row.lat != null) 'lat': row.lat,
          if (row.lng != null) 'lng': row.lng,
          'submittedAt': row.submittedAt.toUtc().toIso8601String(),
        });
        await (db.delete(
          db.pendingSubmissions,
        )..where((s) => s.clientId.equals(row.clientId))).go();
      } on ApiException catch (e) {
        if (e.isNetwork || (e.status ?? 500) >= 500 || e.status == 401) rethrow;
        // Refus définitif (formulaire invalide, mission close) : conservé avec le motif.
        await (db.update(db.pendingSubmissions)
              ..where((s) => s.clientId.equals(row.clientId)))
            .write(PendingSubmissionsCompanion(error: Value(e.message)));
      }
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
