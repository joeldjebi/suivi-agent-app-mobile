import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../core/config.dart';
import '../../core/providers.dart';
import '../day/day_controller.dart';
import '../missions/mission_editor_screen.dart';
import '../missions/missions_controller.dart';
import '../pay/pay_screens.dart';
import '../profile/my_team.dart';
import '../profile/notifications_screen.dart';
import '../team/alerts_screen.dart';
import '../team/report_screen.dart';
import '../team/team_controller.dart';

/// Écrans à relire, regroupés.
enum LiveArea { profile, day, team, missions, pay, alerts, report }

/// Sujet annoncé par le serveur (premier segment de l'adresse modifiée) → écrans à relire.
/// Un sujet inconnu relit tout.
Set<LiveArea> areasFor(String topic) => switch (topic) {
  'settings' ||
  'subscription' ||
  'billing' => {LiveArea.profile, LiveArea.day, LiveArea.team},
  'branding' => {LiveArea.profile},
  'users' || 'groups' || 'team-leads' => {
    LiveArea.profile,
    LiveArea.day,
    LiveArea.team,
    LiveArea.missions,
  },
  'zones' ||
  'zone-requests' ||
  'days' => {LiveArea.day, LiveArea.team, LiveArea.alerts},
  'missions' || 'mission-types' => {LiveArea.missions, LiveArea.pay},
  'pay' => {LiveArea.pay},
  'alerts' => {LiveArea.alerts, LiveArea.report},
  'reports' || 'team-messages' => {LiveArea.report},
  _ => LiveArea.values.toSet(),
};

/// Mises à jour en direct : quand un administrateur ou un chef d'équipe modifie quelque chose
/// (mission, zone, groupe, paie…), le serveur l'annonce et l'app relit les écrans concernés,
/// sans geste de l'utilisateur. Les notifications reçues mettent à jour la liste et le badge.
class LiveUpdates {
  LiveUpdates(this._ref);

  final Ref _ref;
  io.Socket? _socket;
  Timer? _debounce;
  Timer? _retry;
  final Set<LiveArea> _pending = {};
  bool _wasConnected = false;
  int _failures = 0;

  void start() {
    final session = _ref.read(sessionProvider);
    final socket = io.io(
      serverOrigin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          // Nouvelle connexion à chaque session (pas de réutilisation après déconnexion).
          .enableForceNew()
          .disableAutoConnect()
          // Jeton relu à chaque (re)connexion : il change au fil des rafraîchissements.
          .setAuthFn((send) => send({'token': session.accessToken}))
          .build(),
    );
    _socket = socket;
    socket.onConnect((_) {
      _failures = 0;
      // Reconnexion : des annonces ont pu être manquées, on relit tout.
      if (_wasConnected) schedule(LiveArea.values);
      _wasConnected = true;
    });
    socket.onDisconnect((reason) {
      // Refus du serveur (jeton expiré) : pas de reconnexion automatique. On renouvelle le
      // jeton par un appel à l'API, puis on réessaie, de plus en plus espacé.
      if (reason == 'io server disconnect') _reconnectLater();
    });
    socket.on('sync', (data) {
      final topic = data is Map ? data['topic'] : null;
      schedule(topic is String ? areasFor(topic) : LiveArea.values);
    });
    socket.on('notification', (_) {
      _ref.invalidate(unreadCountProvider);
      _ref.invalidate(notificationsProvider);
      schedule(const [LiveArea.day]);
    });
    socket.connect();
  }

  /// Retour au premier plan : le téléphone a pu couper la connexion en arrière-plan. On relit
  /// tout et on se reconnecte si besoin.
  void resume() {
    schedule(LiveArea.values);
    final socket = _socket;
    if (socket != null && !socket.connected) {
      _retry?.cancel();
      socket.connect();
    }
  }

  void _reconnectLater() {
    _retry?.cancel();
    _failures++;
    final seconds = (5 * _failures).clamp(5, 60);
    _retry = Timer(Duration(seconds: seconds), () async {
      try {
        await _ref.read(repositoryProvider).meJson();
      } catch (_) {
        // Hors connexion : la tentative suivante réessaiera.
      }
      _socket?.connect();
    });
  }

  /// Regroupe les annonces rapprochées (une modification en déclenche souvent plusieurs).
  void schedule(Iterable<LiveArea> areas) {
    _pending.addAll(areas);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final areas = {..._pending};
      _pending.clear();
      refresh(areas);
    });
  }

  /// Relit les écrans : les écrans ouverts se mettent à jour en gardant l'affichage en cours,
  /// les autres seront relus à leur ouverture.
  void refresh(Set<LiveArea> areas) {
    final ref = _ref;
    for (final area in areas) {
      switch (area) {
        case LiveArea.profile:
          unawaited(ref.read(authProvider.notifier).refresh());
          ref.invalidate(myTeamProvider);
        case LiveArea.day:
          ref.invalidate(myTeamProvider);
          if (ref.exists(dayProvider)) {
            unawaited(ref.read(dayProvider.notifier).refresh());
          }
          ref.invalidate(availableZonesProvider);
        case LiveArea.team:
          if (ref.exists(teamProvider)) {
            unawaited(ref.read(teamProvider.notifier).refresh());
          }
          if (ref.exists(requestsProvider)) {
            unawaited(ref.read(requestsProvider.notifier).refresh());
          }
          ref.invalidate(leaderGroupsProvider);
          ref.invalidate(teamMembersProvider);
        case LiveArea.missions:
          ref.invalidate(missionsProvider);
          ref.invalidate(missionProvider);
          ref.invalidate(submissionsProvider);
          ref.invalidate(missionTypesProvider);
        case LiveArea.pay:
          ref.invalidate(myPayProvider);
          ref.invalidate(draftRunProvider);
          ref.invalidate(teamPayProvider);
        case LiveArea.alerts:
          if (ref.exists(openAlertsProvider)) {
            unawaited(ref.read(openAlertsProvider.notifier).refresh());
          }
          ref.invalidate(resolvedAlertsProvider);
        case LiveArea.report:
          ref.invalidate(dailyReportProvider);
      }
    }
  }

  void dispose() {
    _debounce?.cancel();
    _retry?.cancel();
    _socket?.dispose();
    _socket = null;
  }
}

/// Actif tant que l'espace connecté est affiché (il le surveille). Pas de connexion pendant
/// les tests automatisés.
final liveUpdatesProvider = Provider.autoDispose<LiveUpdates>((ref) {
  final live = LiveUpdates(ref);
  if (!Platform.environment.containsKey('FLUTTER_TEST')) live.start();
  ref.onDispose(live.dispose);
  return live;
});
