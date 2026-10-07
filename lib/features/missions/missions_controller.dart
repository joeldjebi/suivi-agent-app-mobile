import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/database.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';

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
}) async {
  final db = ref.read(databaseProvider);
  final sync = ref.read(syncProvider);
  final position = await ref.read(trackerProvider).lastKnown();
  final clientId = const Uuid().v4();
  await db
      .into(db.pendingSubmissions)
      .insert(
        PendingSubmissionsCompanion.insert(
          clientId: clientId,
          missionId: mission.id,
          missionTitle: mission.title,
          dataJson: jsonEncode(data),
          lat: Value(position?.latitude),
          lng: Value(position?.longitude),
          submittedAt: DateTime.now().toUtc(),
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
  ref.invalidate(missionProvider(mission.id));
  ref.invalidate(submissionsProvider);
  ref.invalidate(missionsProvider);
  return outcome;
}

/// Formulaires refusés par le serveur, tous missions confondues.
final rejectedSubmissionsProvider = StreamProvider<List<PendingSubmission>>(
  (ref) => ref.watch(databaseProvider).watchRejected(),
);

Future<void> discardSubmission(WidgetRef ref, String clientId) {
  final db = ref.read(databaseProvider);
  return (db.delete(
    db.pendingSubmissions,
  )..where((s) => s.clientId.equals(clientId))).go();
}
