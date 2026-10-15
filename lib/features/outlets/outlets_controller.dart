import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../core/database.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';
import 'outlet_models.dart';

/// Fiche définie par la structure (champs, types de commerce).
final outletFormProvider = FutureProvider<OutletForm>(
  (ref) async =>
      OutletForm.fromJson(await ref.read(repositoryProvider).outletForm()),
);

/// Recherche et filtre de la liste des points de vente.
class OutletFilter {
  const OutletFilter({this.q = '', this.status, this.overdue = false});

  final String q;
  final OutletStatus? status;

  /// En retard de visite seulement.
  final bool overdue;
}

class OutletFilterController extends Notifier<OutletFilter> {
  @override
  OutletFilter build() => const OutletFilter();

  void search(String q) =>
      state = OutletFilter(q: q, status: state.status, overdue: state.overdue);

  void status(OutletStatus? status) =>
      state = OutletFilter(q: state.q, status: status, overdue: state.overdue);

  void overdue(bool on) =>
      state = OutletFilter(q: state.q, status: state.status, overdue: on);
}

final outletFilterProvider =
    NotifierProvider<OutletFilterController, OutletFilter>(
      OutletFilterController.new,
    );

/// Position du téléphone pour trier les points de vente du plus proche au plus loin.
final herePositionProvider = FutureProvider.autoDispose<LatLng?>((ref) async {
  final p = await ref.read(trackerProvider).lastKnown();
  return p == null ? null : LatLng(p.latitude, p.longitude);
});

class OutletList {
  OutletList({
    required this.items,
    required this.total,
    required this.counts,
    required this.here,
    this.overdueCount = 0,
  });

  /// Points de vente en retard de visite (avec les autres filtres).
  final int overdueCount;

  final List<Outlet> items;
  final int total;
  final Map<OutletStatus, int> counts;

  /// Position utilisée pour le tri (null : tri par nom).
  final LatLng? here;
}

/// Points de vente visibles (zones de l'agent, ou de l'équipe du chef), les plus proches
/// d'abord ; ceux « à localiser » à la fin.
final outletsProvider = FutureProvider.autoDispose<OutletList>((ref) async {
  final filter = ref.watch(outletFilterProvider);
  final here = await ref.watch(herePositionProvider.future);
  final repo = ref.read(repositoryProvider);
  final json = await repo.outlets(
    q: filter.q.trim(),
    status: filter.status?.code,
    lat: here?.latitude,
    lng: here?.longitude,
    overdue: filter.overdue,
    limit: 200,
  );
  final items = [
    for (final o in json['items'] as List)
      Outlet.fromJson(o as Map<String, dynamic>),
  ];
  // Autour d'une position, l'API ne renvoie que les points localisés : on ajoute ceux à localiser.
  if (here != null) {
    final unlocated = await repo.outlets(
      q: filter.q.trim(),
      status: filter.status?.code,
      unlocated: true,
      overdue: filter.overdue,
      limit: 50,
    );
    items.addAll([
      for (final o in unlocated['items'] as List)
        Outlet.fromJson(o as Map<String, dynamic>),
    ]);
  }
  final counts = (json['counts'] as Map?)?.cast<String, dynamic>() ?? {};
  return OutletList(
    items: items,
    total: items.length,
    counts: {
      for (final s in OutletStatus.values)
        s: (counts[s.code] as num?)?.toInt() ?? 0,
    },
    here: here,
    overdueCount: (json['overdue'] as num?)?.toInt() ?? 0,
  );
});

final outletProvider = FutureProvider.autoDispose.family<OutletDetail, String>(
  (ref, id) async =>
      OutletDetail.fromJson(await ref.read(repositoryProvider).outlet(id)),
);

/// Photo envoyée, gardée en mémoire le temps de la session.
final photoBytesProvider = FutureProvider.family<List<int>?, String>(
  (ref, id) => ref.read(repositoryProvider).photoBytes(id),
);

/// Ajouts et mises à jour en attente d'envoi (ou refusés).
final pendingOutletsProvider = StreamProvider<List<PendingOutlet>>(
  (ref) => ref.watch(databaseProvider).watchPendingOutlets(),
);

/// Résultat d'un envoi : accepté (avec la fiche à jour) ou en attente du réseau.
class OutletSaved {
  OutletSaved(this.outcome, this.outlet);

  final SubmitOutcome outcome;
  final Outlet? outlet;
}

/// Enregistre une action sur le téléphone puis l'envoie aussitôt si le réseau le permet.
/// Un refus du serveur (doublon, hors zone…) remonte en [ApiException].
Future<OutletSaved> sendOutletAction(
  WidgetRef ref, {
  required String kind,
  required String name,
  required Map<String, dynamic> body,
  String? outletId,
}) async {
  final db = ref.read(databaseProvider);
  final sync = ref.read(syncProvider);
  final clientId = const Uuid().v4();
  await db
      .into(db.pendingOutlets)
      .insert(
        PendingOutletsCompanion.insert(
          clientId: clientId,
          kind: kind,
          outletId: Value(outletId),
          name: name,
          bodyJson: jsonEncode(body),
          createdAt: DateTime.now().toUtc(),
        ),
      );
  final (outcome, json) = await sync.sendOutletNow(clientId);
  ref.invalidate(outletsProvider);
  if (outletId != null) ref.invalidate(outletProvider(outletId));
  return OutletSaved(
    outcome,
    json == null || json['id'] == null ? null : Outlet.fromJson(json),
  );
}
