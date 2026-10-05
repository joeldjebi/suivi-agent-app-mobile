import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'zone_guard.dart';

/// Notifications locales du téléphone : l'alerte s'affiche même application en arrière-plan,
/// et en bannière quand elle est ouverte.
class LocalAlerts implements AlertSink {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  static const _channel = AndroidNotificationDetails(
    'zone_alerts',
    'Alertes de zone',
    channelDescription: 'Sortie et retour dans votre zone de travail',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Initialise et demande l'autorisation d'afficher des notifications (une fois).
  Future<bool> ensureReady() => _ready ??= _init();

  /// Tests sur simulateur : pas de fenêtre d'autorisation devant les écrans capturés
  /// (--dart-define=SKIP_NOTIFICATION_PROMPT=true).
  static const _skipPrompt = bool.fromEnvironment('SKIP_NOTIFICATION_PROMPT');

  @override
  Future<void> prepare() async {
    if (!_skipPrompt) await ensureReady();
  }

  Future<bool> _init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(
            alert: true,
            sound: true,
            badge: false,
          ) ??
          await android?.requestNotificationsPermission() ??
          true;
    } catch (e) {
      debugPrint('Notifications locales indisponibles : $e');
      return false;
    }
  }

  @override
  Future<void> show(int id, String title, String body) async {
    if (_skipPrompt || !await ensureReady()) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (_ready == null) return;
    await _plugin.cancel(id: id);
  }
}
