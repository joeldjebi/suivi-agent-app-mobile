import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'database.dart';
import 'field_photo.dart';
import 'repository.dart';

/// Envoie les positions et les formulaires enregistrés sur le téléphone.
/// Rien n'est perdu sans réseau : l'envoi reprend dès que la connexion revient.
class SyncService extends ChangeNotifier {
  SyncService(
    this.db,
    this.repo, {
    Stream<List<ConnectivityResult>>? connectivity,
    this.onRejected,
  }) : _connectivity = connectivity ?? Connectivity().onConnectivityChanged;

  /// Un formulaire envoyé en arrière-plan a été refusé : prévenir l'agent.
  final void Function(PendingSubmission row, ApiException error)? onRejected;

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
      await _flushOutlets();
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
              if (r.battery != null) 'batteryLevel': r.battery,
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
        await _send(row);
      } on ApiException catch (e) {
        if (_retryable(e)) rethrow;
        // Refus définitif : conservé avec son motif, l'agent corrige ou supprime.
        await _markRejected(row.clientId, e);
        onRejected?.call(row, e);
      }
    }
  }

  /// Envoi d'un formulaire puis retrait du téléphone. Ses photos partent d'abord ; le
  /// formulaire n'en garde que l'identifiant donné par le serveur.
  Future<void> _send(PendingSubmission row) async {
    final data = (jsonDecode(row.dataJson) as Map<String, dynamic>)
        .cast<String, Object?>();
    final photos = <FieldPhoto>[];
    for (final entry in data.entries.toList()) {
      final photo = FieldPhoto.tryParse(entry.value);
      if (photo == null) continue;
      if (!photo.file.existsSync()) {
        throw ApiException(
          'La photo « ${entry.key} » n’est plus sur le téléphone : reprenez-la.',
          code: 'PHOTO_MISSING',
          status: 400,
        );
      }
      data[entry.key] = await repo.uploadPhoto(photo);
      photos.add(photo);
    }
    final extra = row.extraJson == null
        ? const <String, dynamic>{}
        : jsonDecode(row.extraJson!) as Map<String, dynamic>;
    final body = {
      ...extra,
      'clientId': row.clientId,
      'data': data,
      if (row.lat != null) 'lat': row.lat,
      if (row.lng != null) 'lng': row.lng,
      'submittedAt': row.submittedAt.toUtc().toIso8601String(),
    };
    if (isFreeVisit(row)) {
      // Visite libre : le point de vente est dans l'adresse, pas dans le corps.
      await repo.visitOutlet(body.remove('outletId') as String, body);
    } else {
      await repo.submit(row.missionId, body);
    }
    await (db.delete(
      db.pendingSubmissions,
    )..where((s) => s.clientId.equals(row.clientId))).go();
    await PhotoStore.delete(photos);
  }

  /// Points de vente saisis sans réseau, dans l'ordre. Un refus définitif (doublon,
  /// hors zone) est gardé avec son motif : l'agent décide sur l'écran des points de vente.
  Future<void> _flushOutlets() async {
    final rows =
        await (db.select(db.pendingOutlets)
              ..where((o) => o.error.isNull())
              ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
            .get();
    for (final row in rows) {
      try {
        await _sendOutlet(row);
      } on ApiException catch (e) {
        if (_retryable(e)) rethrow;
        await (db.update(
          db.pendingOutlets,
        )..where((o) => o.clientId.equals(row.clientId))).write(
          PendingOutletsCompanion(
            error: Value(e.message),
            errorCode: Value(e.code),
          ),
        );
      }
    }
  }

  /// Envoi d'un point de vente (photos d'abord), puis retrait de la file d'attente.
  Future<Map<String, dynamic>> _sendOutlet(PendingOutlet row) async {
    final body = (jsonDecode(row.bodyJson) as Map<String, dynamic>);
    final photos = <FieldPhoto>[];
    Future<String> upload(FieldPhoto photo) async {
      if (!photo.file.existsSync()) {
        throw ApiException(
          'Une photo n’est plus sur le téléphone : reprenez-la.',
          code: 'PHOTO_MISSING',
          status: 400,
        );
      }
      photos.add(photo);
      return repo.uploadPhoto(photo);
    }

    final front = FieldPhoto.tryParse(body['photo']);
    body.remove('photo');
    if (front != null) body['photoId'] = await upload(front);
    final data = (body['data'] as Map?)?.cast<String, dynamic>();
    if (data != null) {
      for (final entry in data.entries.toList()) {
        final photo = FieldPhoto.tryParse(entry.value);
        if (photo != null) data[entry.key] = await upload(photo);
      }
      body['data'] = data;
    }
    final result = switch (row.kind) {
      'create' => await repo.createOutlet({...body, 'clientId': row.clientId}),
      'status' => await repo.changeOutletStatus(
        row.outletId!,
        body['status'] as String,
        body['comment'] as String?,
      ),
      _ => await repo.updateOutlet(row.outletId!, body),
    };
    await (db.delete(
      db.pendingOutlets,
    )..where((o) => o.clientId.equals(row.clientId))).go();
    await PhotoStore.delete(photos);
    return result;
  }

  /// Envoi immédiat d'un point de vente saisi. Sans réseau, il attend dans la file ;
  /// refusé (doublon, hors zone…), il est retiré et l'erreur remonte à l'écran.
  Future<(SubmitOutcome, Map<String, dynamic>?)> sendOutletNow(
    String clientId,
  ) async {
    final row = await (db.select(
      db.pendingOutlets,
    )..where((o) => o.clientId.equals(clientId))).getSingleOrNull();
    if (row == null) return (SubmitOutcome.sent, null);
    try {
      return (SubmitOutcome.sent, await _sendOutlet(row));
    } on ApiException catch (e) {
      if (_retryable(e)) {
        if (e.isNetwork) {
          online = false;
          notifyListeners();
        }
        return (SubmitOutcome.queued, null);
      }
      await (db.delete(
        db.pendingOutlets,
      )..where((o) => o.clientId.equals(clientId))).go();
      rethrow;
    }
  }

  /// Réseau, serveur indisponible ou session expirée : on réessaiera plus tard.
  static bool _retryable(ApiException e) =>
      e.isNetwork || (e.status ?? 500) >= 500 || e.status == 401;

  Future<void> _markRejected(String clientId, ApiException e) =>
      (db.update(
        db.pendingSubmissions,
      )..where((s) => s.clientId.equals(clientId))).write(
        PendingSubmissionsCompanion(
          error: Value(e.message),
          errorCode: Value(e.code),
        ),
      );

  /// Envoi immédiat d'un formulaire qui vient d'être saisi. Refusé : il est retiré du
  /// téléphone et l'erreur remonte (l'agent corrige sur place). Sans réseau : il attend.
  Future<SubmitOutcome> submitNow(String clientId) async {
    final row = await (db.select(
      db.pendingSubmissions,
    )..where((s) => s.clientId.equals(clientId))).getSingleOrNull();
    if (row == null) return SubmitOutcome.sent;
    try {
      await _send(row);
      return SubmitOutcome.sent;
    } on ApiException catch (e) {
      if (_retryable(e)) {
        if (e.isNetwork) {
          online = false;
          notifyListeners();
        }
        return SubmitOutcome.queued;
      }
      await (db.delete(
        db.pendingSubmissions,
      )..where((s) => s.clientId.equals(clientId))).go();
      rethrow;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Résultat de l'envoi immédiat d'un formulaire.
enum SubmitOutcome {
  /// Accepté par le serveur.
  sent,

  /// Sans réseau (ou serveur indisponible) : envoyé dès que possible.
  queued,
}

/// Peut-on corriger et renvoyer ce formulaire refusé ? Non si la mission est close ou
/// n'existe plus pour l'agent.
bool canRetrySubmission(String? errorCode) =>
    errorCode != 'MISSION_CLOSED' &&
    errorCode != 'NOT_FOUND' &&
    errorCode != 'VISIT_FORM_NOT_ALLOWED';

/// Visite libre d'un point de vente (sans mission) : gardée dans la même file d'attente que
/// les formulaires de mission, sans mission ; le formulaire et le point de vente sont dans
/// ses champs en plus.
bool isFreeVisit(PendingSubmission row) => row.missionId.isEmpty;

/// Visite libre : point de vente et formulaire.
({String outletId, String typeId})? freeVisitOf(PendingSubmission row) {
  if (!isFreeVisit(row) || row.extraJson == null) return null;
  final extra = jsonDecode(row.extraJson!) as Map<String, dynamic>;
  final outletId = extra['outletId'] as String?;
  final typeId = extra['typeId'] as String?;
  return outletId == null || typeId == null
      ? null
      : (outletId: outletId, typeId: typeId);
}
