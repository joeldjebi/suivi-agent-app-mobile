import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

/// Vue d'équipe du chef : agents en journée, agents pas encore partis, noms des zones.
class TeamOverview {
  TeamOverview({
    required this.live,
    required this.idle,
    required this.zones,
    required this.members,
  });

  final List<LiveAgent> live;
  final List<TeamMember> idle;
  final List<Zone> zones;
  final Map<String, TeamMember> members;

  List<LiveAgent> get alerts => live.where((a) => a.hasAlert).toList();
  List<LiveAgent> get working => live.where((a) => !a.hasAlert).toList();
  int get active => live.where((a) => a.status == DayStatus.active).length;
  int get paused => live.where((a) => a.status == DayStatus.paused).length;

  String zoneName(String? id) =>
      zones.where((z) => z.id == id).firstOrNull?.name ?? 'Sans zone';
}

/// « Hors zone · 12 min ».
String outsideLabel(LiveAgent a) {
  final since = a.outsideSince;
  if (since == null) return 'Hors de sa zone';
  final minutes = DateTime.now().difference(since).inMinutes.clamp(1, 1 << 20);
  return minutes < 60
      ? 'Hors zone · $minutes min'
      : 'Hors zone · ${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

class TeamController extends AsyncNotifier<TeamOverview> {
  Timer? _timer;

  @override
  Future<TeamOverview> build() async {
    // Rafraîchissement régulier : le statut « signal perdu » dépend du temps qui passe.
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
    ref.onDispose(() => _timer?.cancel());
    return _load();
  }

  Future<TeamOverview> _load() async {
    final repo = ref.read(repositoryProvider);
    final live = await repo.live();
    final team = await repo.team();
    final zones = await repo.leaderZones();
    final inDay = live.map((a) => a.agentId).toSet();
    live.sort((a, b) => a.name.compareTo(b.name));
    return TeamOverview(
      live: live,
      idle: team.where((m) => !inDay.contains(m.id)).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName)),
      zones: zones,
      members: {for (final m in team) m.id: m},
    );
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(_load);
    // Sans réseau, on garde la dernière vue connue.
    if (next.hasValue || !state.hasValue) state = next;
  }

  Future<void> reassign(String agentId, String zoneId) async {
    await ref.read(repositoryProvider).reassign(agentId, zoneId);
    await refresh();
  }
}

final teamProvider = AsyncNotifierProvider<TeamController, TeamOverview>(
  TeamController.new,
);

/// Demandes de zone en attente de décision.
class RequestsController extends AsyncNotifier<List<PendingRequest>> {
  Timer? _timer;

  @override
  Future<List<PendingRequest>> build() async {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(refresh()),
    );
    ref.onDispose(() => _timer?.cancel());
    return ref.read(repositoryProvider).pendingRequests();
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(
      () => ref.read(repositoryProvider).pendingRequests(),
    );
    if (next.hasValue || !state.hasValue) state = next;
  }

  Future<void> decide(
    String id, {
    required bool approve,
    String? reason,
  }) async {
    await ref
        .read(repositoryProvider)
        .decide(id, approve: approve, reason: reason);
    // Retrait immédiat de la liste, puis rechargement.
    state = AsyncData([...?state.value?.where((r) => r.id != id)]);
    unawaited(refresh());
    unawaited(ref.read(teamProvider.notifier).refresh());
  }
}

final requestsProvider =
    AsyncNotifierProvider<RequestsController, List<PendingRequest>>(
      RequestsController.new,
    );
