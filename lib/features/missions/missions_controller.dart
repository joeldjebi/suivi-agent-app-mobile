import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/database.dart';
import '../../core/field_photo.dart';
import '../../core/form_drafts.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';
import '../outlets/outlets_controller.dart';
import '../outlets/route_screen.dart' show outletRouteProvider;

/// Missions de l'agent. Mises en cache : consultables et remplissables hors connexion.
final missionsProvider = FutureProvider.autoDispose<List<Mission>>((ref) async {
  final repo = ref.read(repositoryProvider);
  try {
    final items = await repo.missionsJson();
    final cache = await MissionCache.read();
    await MissionCache.write({...cache, 'list': items});
    return items.map(Mission.fromJson).toList();
  } on ApiException catch (e) {
    final cached = (await MissionCache.read())['list'] as List?;
    if (e.isNetwork && cached != null) {
      return cached
          .map((m) => Mission.fromJson(m as Map<String, dynamic>))
          .toList();
    }
    rethrow;
  }
});

/// Détail d'une mission, avec les champs de son formulaire.
final missionProvider = FutureProvider.autoDispose.family<Mission, String>((
  ref,
  id,
) async {
  final repo = ref.read(repositoryProvider);
  try {
    final json = await repo.missionJson(id);
    final cache = await MissionCache.read();
    await MissionCache.write({...cache, 'mission:$id': json});
    return Mission.fromJson(json);
  } on ApiException catch (e) {
    final cached = (await MissionCache.read())['mission:$id'];
    if (e.isNetwork && cached != null) {
      return Mission.fromJson(cached as Map<String, dynamic>);
    }
    rethrow;
  }
});

/// Formulaires envoyés d'une mission, selon les filtres du chef d'équipe.
final submissionsProvider = FutureProvider.autoDispose
    .family<List<Submission>, ({String missionId, SubmissionFilter filter})>(
      (ref, key) => ref
          .read(repositoryProvider)
          .submissions(key.missionId, filter: key.filter),
    );

/// Filtres choisis par le chef sur une mission (oubliés en quittant l'écran).
class SubmissionFilterController extends Notifier<SubmissionFilter> {
  SubmissionFilterController(this.missionId);

  final String missionId;

  @override
  SubmissionFilter build() => const SubmissionFilter();

  void set(SubmissionFilter filter) => state = filter;
}

final submissionFilterProvider = NotifierProvider.autoDispose
    .family<SubmissionFilterController, SubmissionFilter, String>(
      SubmissionFilterController.new,
    );

/// Formulaires de cette mission encore sur le téléphone (en attente ou refusés).
final localSubmissionsProvider = StreamProvider.autoDispose
    .family<List<PendingSubmission>, String>((ref, id) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.pendingSubmissions)
            ..where((s) => s.missionId.equals(id))
            ..orderBy([(s) => OrderingTerm.desc(s.submittedAt)]))
          .watch();
    });

/// Enregistre le formulaire sur le téléphone puis l'envoie aussitôt. Refusé par le serveur :
/// [ApiException] (le formulaire reste à l'écran pour être corrigé). Sans réseau : il
/// attend sur le téléphone. `replacing` : formulaire refusé que celui-ci remplace.
Future<SubmitOutcome> saveSubmission(
  WidgetRef ref,
  Mission mission,
  Map<String, dynamic> data, {
  String? replacing,
  String? outletId,
  String? outletStatus,
  String? outletComment,
}) async {
  final outcome = await _queueAndSend(
    ref,
    missionId: mission.id,
    title: mission.title,
    data: data,
    replacing: replacing,
    outletId: outletId,
    outletStatus: outletStatus,
    outletComment: outletComment,
  );
  ref.invalidate(missionProvider(mission.id));
  if (outletId != null) ref.invalidate(missionOutletsProvider(mission.id));
  ref.invalidate(submissionsProvider);
  ref.invalidate(missionsProvider);
  return outcome;
}

/// Visite libre d'un point de vente (sans mission) avec un formulaire de visite : même file
/// d'attente, mêmes règles d'envoi que les formulaires de mission.
Future<SubmitOutcome> saveFreeVisit(
  WidgetRef ref, {
  required String typeId,
  required String title,
  required String outletId,
  required Map<String, dynamic> data,
  String? replacing,
  String? outletStatus,
  String? outletComment,
}) => _queueAndSend(
  ref,
  missionId: '',
  typeId: typeId,
  title: title,
  data: data,
  replacing: replacing,
  outletId: outletId,
  outletStatus: outletStatus,
  outletComment: outletComment,
);

Future<SubmitOutcome> _queueAndSend(
  WidgetRef ref, {
  required String missionId,
  required String title,
  required Map<String, dynamic> data,
  String? typeId,
  String? replacing,
  String? outletId,
  String? outletStatus,
  String? outletComment,
}) async {
  final db = ref.read(databaseProvider);
  final sync = ref.read(syncProvider);
  // Visite : la position mesurée maintenant (contrôle de distance au point de vente).
  final tracker = ref.read(trackerProvider);
  final position = outletId != null
      ? await tracker.freshPosition()
      : await tracker.lastKnown();
  final extra = {
    'typeId': ?typeId,
    'outletId': ?outletId,
    if (outletId != null && position != null) 'accuracy': position.accuracy,
    'outletStatus': ?outletStatus,
    if (outletComment != null && outletComment.isNotEmpty)
      'outletComment': outletComment,
  };
  final clientId = const Uuid().v4();
  await db
      .into(db.pendingSubmissions)
      .insert(
        PendingSubmissionsCompanion.insert(
          clientId: clientId,
          missionId: missionId,
          missionTitle: title,
          dataJson: jsonEncode(data),
          lat: Value(position?.latitude),
          lng: Value(position?.longitude),
          submittedAt: DateTime.now().toUtc(),
          extraJson: Value(extra.isEmpty ? null : jsonEncode(extra)),
        ),
      );
  final outcome = await sync.submitNow(clientId);
  // Accepté ou en attente : l'ancien formulaire refusé n'a plus lieu d'être.
  if (replacing != null) {
    await (db.delete(
      db.pendingSubmissions,
    )..where((s) => s.clientId.equals(replacing))).go();
  }
  unawaited(sync.flush());
  if (outletId != null) {
    ref.invalidate(outletProvider(outletId));
    ref.invalidate(outletsProvider);
    ref.invalidate(outletRouteProvider);
  }
  return outcome;
}

/// Formulaires refusés par le serveur, tous missions confondues.
final rejectedSubmissionsProvider = StreamProvider<List<PendingSubmission>>(
  (ref) => ref.watch(databaseProvider).watchRejected(),
);

Future<void> discardSubmission(WidgetRef ref, String clientId) async {
  final db = ref.read(databaseProvider);
  final row = await (db.select(
    db.pendingSubmissions,
  )..where((s) => s.clientId.equals(clientId))).getSingleOrNull();
  await (db.delete(
    db.pendingSubmissions,
  )..where((s) => s.clientId.equals(clientId))).go();
  // Ses photos ne partiront plus.
  if (row != null) {
    await PhotoStore.delete(
      FieldPhoto.inData(
        (jsonDecode(row.dataJson) as Map<String, dynamic>)
            .cast<String, Object?>(),
      ),
    );
  }
}

/// Brouillon du formulaire d'une mission (relu à chaque retour sur la mission).
final draftProvider = FutureProvider.autoDispose.family<FormDraft?, String>(
  (ref, missionId) => FormDrafts.read(missionId),
);

/// Point de vente d'une mission de visites, avec ses visites.
class MissionOutlet {
  MissionOutlet({
    required this.id,
    required this.name,
    required this.status,
    required this.visits,
    this.category,
    this.position,
    this.lastVisitAt,
    this.lastVisitBy,
    this.distance,
  });

  final String id;
  final String name;
  final String? category;
  final String status;
  final LatLng? position;
  final int visits;
  final DateTime? lastVisitAt;
  final String? lastVisitBy;
  final int? distance;

  bool get visited => visits > 0;

  factory MissionOutlet.fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lng = (j['lng'] as num?)?.toDouble();
    return MissionOutlet(
      id: j['id'] as String,
      name: j['name'] as String,
      category: j['category'] as String?,
      status: j['status'] as String,
      position: lat != null && lng != null ? LatLng(lat, lng) : null,
      visits: (j['visits'] as num?)?.toInt() ?? 0,
      lastVisitAt: j['lastVisitAt'] == null
          ? null
          : DateTime.parse(j['lastVisitAt'] as String).toLocal(),
      lastVisitBy: j['lastVisitBy'] as String?,
      distance: (j['distance'] as num?)?.toInt(),
    );
  }
}

/// Mission de visites : ses points de vente, à visiter d'abord (les plus proches en tête).
final missionOutletsProvider = FutureProvider.autoDispose
    .family<List<MissionOutlet>, String>((ref, id) async {
      final here = await ref.read(trackerProvider).lastKnown();
      final rows = await ref
          .read(repositoryProvider)
          .missionOutlets(id, lat: here?.latitude, lng: here?.longitude);
      return [
        for (final r in rows) MissionOutlet.fromJson(r as Map<String, dynamic>),
      ];
    });
