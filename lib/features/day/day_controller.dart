import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

/// État de la journée de l'agent, et pilotage du suivi de position.
class DayController extends AsyncNotifier<DayState> {
  Timer? _poll;

  @override
  Future<DayState> build() async {
    ref.onDispose(() => _poll?.cancel());
    final state = await ref.read(repositoryProvider).currentDay();
    await _applyTracking(state);
    _schedulePoll(state);
    return state;
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(
      () => ref.read(repositoryProvider).currentDay(),
    );
    // Sans réseau, on garde l'état connu plutôt que d'afficher une erreur.
    if (next.hasValue || !state.hasValue) state = next;
    if (next.hasValue) {
      await _applyTracking(next.requireValue);
      _schedulePoll(next.requireValue);
    }
  }

  Future<ZoneRequest> chooseZone(String zoneId) async {
    final request = await ref.read(repositoryProvider).requestZone(zoneId);
    await refresh();
    return request;
  }

  Future<void> cancelPending(String requestId) async {
    await ref.read(repositoryProvider).cancelRequest(requestId);
    await refresh();
  }

  /// start, pause, resume, end
  Future<void> act(String action) async {
    await ref.read(repositoryProvider).dayAction(action);
    if (action == 'end' || action == 'pause') {
      // Les dernières positions partent avant l'arrêt du suivi.
      unawaited(ref.read(syncProvider).flush());
    }
    await refresh();
  }

  /// Le suivi suit la journée : actif en journée, en pause seulement si la structure l'a choisi.
  Future<void> _applyTracking(DayState s) async {
    final tracker = ref.read(trackerProvider);
    final me = ref.read(meProvider);
    final day = s.day;
    final shouldTrack =
        day != null &&
        (day.status == DayStatus.active ||
            (day.status == DayStatus.paused && me.trackDuringPause));
    if (shouldTrack) {
      await _watchZone(day.zoneId, me);
      final guard = ref.read(zoneGuardProvider);
      tracker.onFix = guard.onFix;
      await tracker.start(
        day.id,
        structure: ref.read(brandingProvider).displayName,
      );
      ref.read(syncProvider).start();
    } else {
      await tracker.stop();
      ref.read(zoneGuardProvider).stop();
    }
  }

  /// Zone du jour pour la surveillance sur le téléphone ; contours chargés au changement.
  Future<void> _watchZone(String? zoneId, Me me) async {
    final guard = ref.read(zoneGuardProvider);
    var zone = guard.zone?.id == zoneId ? guard.zone : null;
    if (zoneId != null && zone == null) {
      try {
        final zones = await ref.read(repositoryProvider).availableZones();
        zone = zones.zones.where((z) => z.id == zoneId).firstOrNull;
      } catch (_) {
        // Sans réseau : la surveillance démarre au prochain rafraîchissement.
      }
      // Autorisation des notifications demandée quand la surveillance démarre.
      if (zone != null) unawaited(ref.read(alertSinkProvider).prepare());
    }
    guard.configure(
      zone: zone,
      tolerance: me.zoneExitToleranceMeters,
      alertMinutes: me.zoneExitAlertMinutes,
    );
  }

  /// En attente d'approbation : vérification fréquente pour afficher la décision sans attendre.
  void _schedulePoll(DayState s) {
    _poll?.cancel();
    _poll = Timer(
      Duration(seconds: s.pending != null ? 10 : 60),
      () => unawaited(refresh()),
    );
  }
}

final dayProvider = AsyncNotifierProvider<DayController, DayState>(
  DayController.new,
);

final availableZonesProvider = FutureProvider.autoDispose<AvailableZones>(
  (ref) => ref.read(repositoryProvider).availableZones(),
);
