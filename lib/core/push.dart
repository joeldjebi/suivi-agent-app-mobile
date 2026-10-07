import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';
import 'local_notifications.dart';
import 'models.dart';
import 'providers.dart';

/// Fonctionnalité de la formule : sans elle, rien n'est envoyé au téléphone.
const pushFeature = 'push_notifications';

extension PushFeature on Me {
  bool get hasPush => features.contains(pushFeature);
}

/// Écran ouvert au toucher d'une notification, selon son type.
String pushRouteFor(Map<String, String> data, {required bool leader}) {
  final type = data['type'] ?? '';
  final missionId = data['missionId'];
  return switch (type) {
    'zone_request.created' ||
    'zone_request.reminder' ||
    'zone_request.reassigned' => leader ? '/requests' : '/day',
    'zone_request.approved' ||
    'zone_request.rejected' ||
    'zone_request.expired' ||
    'zone.deactivated' => '/day',
    'mission.assigned' ||
    'submission.rejected' when missionId != null => '/missions/$missionId',
    'mission.assigned' || 'submission.rejected' => '/missions',
    'pay.paid' || 'pay.validated' || 'pay.draft_ready' => '/profile/earnings',
    'pay.adjustment_proposed' =>
      leader ? '/profile/team-earnings' : '/profile/earnings',
    'team.message' || 'report.daily' => leader ? '/report' : '/notifications',
    _
        when leader &&
            (type.startsWith('alert.') || type.startsWith('zone_exit')) =>
      '/alerts',
    _ => '/notifications',
  };
}

/// Notification touchée (ou bouton choisi), à traiter par l'espace connecté.
class PushOpen {
  const PushOpen(this.data, {this.action});

  final Map<String, String> data;

  /// Bouton choisi (zone_approve, zone_reject), null pour un simple toucher.
  final String? action;
}

/// Dernière notification touchée, en attente de l'espace connecté (l'app a pu démarrer
/// à cette occasion, avant la reprise de session).
class PushInbox extends Notifier<PushOpen?> {
  @override
  PushOpen? build() => null;

  void put(PushOpen open) => state = open;

  PushOpen? take() {
    final open = state;
    state = null;
    return open;
  }
}

final pushInboxProvider = NotifierProvider<PushInbox, PushOpen?>(PushInbox.new);

Map<String, String> _strings(Map<String, dynamic> data) => {
  for (final e in data.entries)
    if (e.value != null) e.key: e.value.toString(),
};

/// Message reçu app fermée ou en arrière-plan. Les notifications ordinaires sont affichées
/// par le téléphone ; celles à boutons (Android) arrivent en données et sont affichées ici.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) return;
  final data = _strings(message.data);
  if (data['title'] == null) return;
  await LocalNotifications.showPush(data);
}

/// Notifications push (Firebase) : enregistrement du téléphone auprès de l'API, affichage
/// app ouverte, ouverture du bon écran au toucher. Inactif sans Firebase (tests).
class PushService {
  PushService(this._ref);

  final Ref _ref;
  bool _started = false;
  String? _token;
  StreamSubscription<String>? _refresh;

  /// Ouvertures rapprochées d'une même notification (toucher et bouton) : le bouton l'emporte.
  final _waiting = <String, PushOpen>{};
  Timer? _flush;

  static const _actions = MethodChannel('suivi_agent/push_actions');
  static const _laterKey = 'push.prompt.later';
  static bool get _disabled =>
      Platform.environment.containsKey('FLUTTER_TEST') ||
      FirebaseConfig.current == null;

  bool get available => _started;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// Au lancement : Firebase, réception app ouverte, notification qui a lancé l'app.
  Future<void> start() async {
    if (_started || _disabled) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: FirebaseConfig.current);
      }
      _started = true;
    } catch (e) {
      debugPrint('Notifications push indisponibles : $e');
      return;
    }
    FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
    await LocalNotifications.init();
    // iPhone : affichée par le système même app ouverte (avec ses boutons) ; Android :
    // affichée par l'app.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      sound: true,
    );
    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => _open(_strings(m.data), id: m.messageId),
    );
    LocalNotifications.responses.stream.listen(_onLocalResponse);
    _actions.setMethodCallHandler((call) async {
      if (call.method == 'ready') await _takeNativeActions();
    });

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _open(_strings(initial.data), id: initial.messageId);
    final launch = await LocalNotifications.launchResponse();
    if (launch != null) _onLocalResponse(launch);
    await _takeNativeActions();
  }

  void _onForeground(RemoteMessage message) {
    final notification = message.notification;
    // Les écrans se mettent à jour par la connexion en direct ; seul l'affichage manque.
    if (Platform.isIOS && notification != null) return;
    unawaited(
      LocalNotifications.showPush(
        _strings(message.data),
        title: notification?.title,
        body: notification?.body,
      ),
    );
  }

  void _onLocalResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return; // alerte de zone : rien à ouvrir
    try {
      final data = _strings(jsonDecode(payload) as Map<String, dynamic>);
      _open(
        data,
        id: data['google.message_id'] ?? payload,
        action: response.actionId,
      );
    } catch (_) {
      // Notification d'une ancienne version : ignorée.
    }
  }

  /// Boutons touchés sur une notification push de l'iPhone (transmis par l'app native).
  Future<void> _takeNativeActions() async {
    if (!Platform.isIOS) return;
    try {
      final pending = await _actions.invokeListMethod<Map>('takePending');
      for (final item in pending ?? const <Map>[]) {
        final data = _strings((item['data'] as Map).cast<String, dynamic>());
        _open(
          data,
          id: data['gcm.message_id'],
          action: item['action'] as String?,
        );
      }
    } catch (_) {
      // Ancienne version de l'app native : pas de boutons.
    }
  }

  void _open(Map<String, String> data, {String? id, String? action}) {
    final key = id ?? jsonEncode(data);
    final current = _waiting[key];
    if (current == null || action != null) {
      _waiting[key] = PushOpen(data, action: action);
    }
    _flush?.cancel();
    _flush = Timer(const Duration(milliseconds: 400), () {
      final opens = [..._waiting.values];
      _waiting.clear();
      if (opens.isNotEmpty) {
        _ref.read(pushInboxProvider.notifier).put(opens.last);
      }
    });
  }

  /// État de l'autorisation : null sans Firebase.
  Future<AuthorizationStatus?> permission() async {
    if (!_started) return null;
    return (await _messaging.getNotificationSettings()).authorizationStatus;
  }

  /// Faut-il expliquer puis demander l'autorisation ? Pas plus d'une fois par semaine.
  Future<bool> shouldAsk(Me me) async {
    if (!me.hasPush ||
        await permission() != AuthorizationStatus.notDetermined) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final later = prefs.getInt(_laterKey);
    return later == null ||
        DateTime.now().millisecondsSinceEpoch - later >
            const Duration(days: 7).inMilliseconds;
  }

  Future<void> askLater() async => (await SharedPreferences.getInstance())
      .setInt(_laterKey, DateTime.now().millisecondsSinceEpoch);

  /// Demande l'autorisation puis enregistre le téléphone ; vrai si accordée.
  Future<bool> enable() async {
    if (!_started) return false;
    final settings = await _messaging.requestPermission(
      alert: true,
      sound: true,
      badge: false,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (granted) await register();
    return granted;
  }

  /// Espace connecté affiché : téléphone enregistré si l'autorisation est déjà accordée.
  Future<void> attach(Me me) async {
    if (!me.hasPush) return;
    final status = await permission();
    if (status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional) {
      await register();
    }
  }

  /// Envoie le jeton du téléphone à l'API (et ses renouvellements).
  Future<void> register() async {
    if (!_started) return;
    try {
      if (Platform.isIOS) {
        // Le jeton Firebase attend celui d'Apple, attribué peu après le lancement.
        for (
          var i = 0;
          i < 10 && await _messaging.getAPNSToken() == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      final token = await _messaging.getToken();
      if (token != null) await _send(token);
      _refresh ??= _messaging.onTokenRefresh.listen((t) => unawaited(_send(t)));
    } catch (e) {
      debugPrint('Enregistrement push impossible : $e');
    }
  }

  Future<void> _send(String token) async {
    try {
      await _ref.read(repositoryProvider).api.post<void>('/devices', {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      _token = token;
    } catch (_) {
      // Hors connexion : nouvel essai au prochain affichage de l'espace connecté.
    }
  }

  /// Déconnexion (session encore valide) : le téléphone ne reçoit plus rien pour ce compte.
  Future<void> unregister() async {
    final token = _token;
    if (token == null) return;
    try {
      await _ref
          .read(repositoryProvider)
          .api
          .delete<void>('/devices/${Uri.encodeComponent(token)}');
    } catch (_) {
      // Hors connexion : le jeton est invalidé ci-dessous.
    }
  }

  /// Fin de session : jeton invalidé chez Firebase, le serveur l'oubliera au prochain envoi.
  Future<void> forget() async {
    await _refresh?.cancel();
    _refresh = null;
    _token = null;
    if (!_started) return;
    try {
      await _messaging.deleteToken();
    } catch (_) {
      // Sans réseau : sera remplacé à la prochaine connexion.
    }
  }
}

final pushProvider = Provider<PushService>((ref) => PushService(ref));
