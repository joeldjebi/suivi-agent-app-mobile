import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../safety/sos.dart';
import '../../core/app_version.dart';
import '../../core/config.dart';
import '../../core/network_status.dart';
import '../../core/providers.dart';
import '../day/day_controller.dart';
import '../day/week_screen.dart';
import '../missions/mission_editor_screen.dart';
import '../missions/missions_controller.dart';
import '../pay/pay_screens.dart';
import '../profile/my_team.dart';
import '../profile/notifications_screen.dart';
import '../team/alerts_screen.dart';
import '../team/report_screen.dart';
import '../team/team_controller.dart';
import '../../core/platform.dart';
import '../orders/order_screen.dart' show allOutletOrdersProvider;
import '../orders/orders.dart';
import '../outlets/outlet_activity.dart' show outletReadingsProvider;
import '../outlets/outlet_visits.dart';
import '../outlets/outlets_controller.dart';
import '../outlets/product_insights_screen.dart' show productInsightsProvider;
import '../outlets/route_screen.dart' show outletRouteProvider;
import '../outlets/suggestions.dart';
import '../outlets/visit_forms.dart';
import '../van_sales/transfers.dart';
import '../van_sales/van_history.dart' show vanHistoryProvider;
import '../van_sales/van_sales.dart';

/// Écrans à relire, regroupés.
enum LiveArea {
  profile,
  day,
  team,
  missions,
  pay,
  alerts,
  report,

  /// Mon camion, ses ventes, crédits et dépannages (aussi sur la page Journée).
  van,

  /// Points de vente : liste, fiches, tournée, visites, relevés.
  outlets,

  /// Commandes et prix.
  orders,
}

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
  'missions' || 'mission-types' => {
    LiveArea.missions,
    LiveArea.pay,
    // Missions affichées au choix de la zone.
    LiveArea.day,
    // Une mission de visites donne ses points de vente à l'agent.
    LiveArea.outlets,
  },
  // Camion affecté, chargement, vente, dépannage (demande, part, remise, expiration).
  'van-sales' || 'stock' => {LiveArea.van, LiveArea.orders, LiveArea.outlets},
  // Nouveau client, transfert à un autre agent, statut, visite.
  'outlets' => {LiveArea.outlets, LiveArea.missions, LiveArea.orders},
  'orders' => {LiveArea.orders, LiveArea.van, LiveArea.outlets},
  'products' ||
  'product-suggestions' ||
  'insights' => {LiveArea.orders, LiveArea.van, LiveArea.outlets},
  'safety' => {LiveArea.day, LiveArea.alerts},
  'pay' => {LiveArea.pay},
  'alerts' => {LiveArea.alerts, LiveArea.report},
  'reports' || 'team-messages' => {LiveArea.report},
  _ => LiveArea.values.toSet(),
};

/// Notification reçue (son type, ex. « transfer.created ») → écrans à relire. Toujours la
/// journée (bandeaux, cartes) ; un type inconnu relit tout.
Set<LiveArea> areasForNotification(String type) {
  final prefix = type.split('.').first;
  final areas = switch (prefix) {
    'transfer' ||
    'stock' ||
    'van' ||
    'sale' ||
    'payment' => {LiveArea.van, LiveArea.orders},
    'outlets' || 'outlet' || 'visit' => {LiveArea.outlets, LiveArea.orders},
    'order' || 'orders' => {LiveArea.orders, LiveArea.outlets},
    'mission' ||
    'missions' ||
    'submission' => {LiveArea.missions, LiveArea.pay, LiveArea.outlets},
    'zone' || 'zone_request' || 'day' => {LiveArea.team, LiveArea.alerts},
    'pay' || 'payroll' => {LiveArea.pay},
    'alert' || 'sos' => {LiveArea.alerts, LiveArea.team},
    _ => LiveArea.values.toSet(),
  };
  return {...areas, LiveArea.day};
}

/// Mises à jour en direct : quand un administrateur, un chef, un collègue ou une tâche
/// automatique modifie quelque chose (mission, zone, camion, dépannage, point de vente,
/// commande…), le serveur l'annonce et l'app relit les écrans concernés, sans geste de
/// l'utilisateur. Une notification reçue relit aussi tout ce qu'elle peut concerner (camion
/// affecté, dépannage demandé, points de vente confiés…).
class LiveUpdates {
  LiveUpdates(this._ref);

  final Ref _ref;
  io.Socket? _socket;
  Timer? _debounce;
  Timer? _retry;
  Timer? _fallback;
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
      // Couleurs ou logo changés par la structure : appliqués aussitôt, sans attendre.
      if (topic == 'branding') {
        unawaited(_ref.read(authProvider.notifier).reloadBranding());
      }
      schedule(topic is String ? areasFor(topic) : LiveArea.values);
    });
    // L'éditeur publie une version : fenêtre de mise à jour, ou blocage si elle est critique.
    socket.on('app_version', (data) {
      if (data is Map) {
        _ref
            .read(updateProvider.notifier)
            .apply(Map<String, dynamic>.from(data));
      }
    });
    socket.on('notification', (data) {
      _ref.invalidate(unreadCountProvider);
      _ref.invalidate(notificationsProvider);
      final type = data is Map ? data['type'] : null;
      schedule(type is String ? areasForNotification(type) : LiveArea.values);
    });
    socket.connect();
    // Filet de sécurité : connexion en direct coupée (réseau mobile instable, serveur
    // redémarré), les écrans essentiels sont relus régulièrement.
    _fallback = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!(_socket?.connected ?? false)) {
        schedule(const [LiveArea.day, LiveArea.team, LiveArea.alerts]);
        // Apparence : le logo n'est retéléchargé que s'il a changé.
        unawaited(_ref.read(authProvider.notifier).reloadBranding());
      }
    });
  }

  /// Retour au premier plan : le téléphone a pu couper la connexion en arrière-plan. On relit
  /// tout et on se reconnecte si besoin.
  void resume() {
    schedule(LiveArea.values);
    // Version publiée pendant que l'app était en arrière-plan.
    _ref.read(updateProvider.notifier).check();
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
          ref.invalidate(weekProvider);
          if (ref.exists(sosProvider)) {
            unawaited(ref.read(sosProvider.notifier).refresh());
          }
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
        case LiveArea.van:
          invalidateVanData(ref);
          ref.invalidate(myTransfersProvider);
          ref.invalidate(nearbyTransfersProvider);
          ref.invalidate(ownProductsProvider);
          ref.invalidate(outOfZoneContextProvider);
          ref.invalidate(vanHistoryProvider);
        case LiveArea.outlets:
          ref.invalidate(outletsProvider);
          ref.invalidate(outletProvider);
          ref.invalidate(outletRouteProvider);
          ref.invalidate(outletVisitsProvider);
          ref.invalidate(visitDetailProvider);
          ref.invalidate(outletReadingsProvider);
          ref.invalidate(visitFormsProvider);
          ref.invalidate(suggestionsProvider);
          ref.invalidate(competitorProductsProvider);
          ref.invalidate(productInsightsProvider);
        case LiveArea.orders:
          ref.invalidate(orderCatalogProvider);
          ref.invalidate(outletOrdersProvider);
          ref.invalidate(orderProvider);
          ref.invalidate(allOutletOrdersProvider);
      }
    }
  }

  void dispose() {
    _debounce?.cancel();
    _retry?.cancel();
    _fallback?.cancel();
    _socket?.dispose();
    _socket = null;
  }
}

/// Actif tant que l'espace connecté est affiché (il le surveille). Pas de connexion pendant
/// les tests automatisés.
final liveUpdatesProvider = Provider.autoDispose<LiveUpdates>((ref) {
  final live = LiveUpdates(ref);
  if (!AppPlatform.isTest) live.start();
  // Retour du réseau (téléphone ou serveur de nouveau joignable) : tout est relu en
  // arrière-plan, les données gardées hors ligne sont remplacées.
  ref.listen(networkProvider.select((n) => n.online), (was, online) {
    if (online && was == false) live.resume();
  });
  ref.listen(syncProvider.select((s) => s.online), (was, online) {
    if (online && was == false) live.resume();
  });
  // Notification reçue app ouverte : sa source a changé, on relit.
  ref.listen(refreshRequestProvider, (_, _) => live.schedule(LiveArea.values));
  ref.onDispose(live.dispose);
  return live;
});
