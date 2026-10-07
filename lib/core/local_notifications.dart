import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Boutons des notifications de demande de zone (chef d'équipe).
const zoneApproveAction = 'zone_approve';
const zoneRejectAction = 'zone_reject';

/// Notifications affichées par l'app elle-même : alertes de zone, et notifications push
/// reçues app ouverte (ou à boutons sur Android). Un seul point d'initialisation, partagé
/// par l'app et le traitement en arrière-plan.
class LocalNotifications {
  LocalNotifications._();

  static final plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _ready;

  /// Notification touchée (ou bouton) : données de la notification push et bouton choisi.
  static final responses = StreamController<NotificationResponse>.broadcast();

  static const pushChannel = AndroidNotificationChannel(
    'suivi_agent',
    'Notifications',
    description: 'Demandes, missions, alertes et messages de votre structure',
    importance: Importance.high,
  );

  /// Initialise sans demander l'autorisation (demandée au bon moment, avec explication).
  static Future<void> init() => _ready ??= _init();

  static Future<void> _init() async {
    try {
      await plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
            // Boutons des notifications push de demande de zone (catégorie envoyée par le
            // serveur) : ils ouvrent l'app, qui exécute l'action.
            notificationCategories: [
              DarwinNotificationCategory(
                'ZONE_REQUEST',
                actions: [
                  DarwinNotificationAction.plain(
                    zoneApproveAction,
                    'Approuver',
                    options: {DarwinNotificationActionOption.foreground},
                  ),
                  DarwinNotificationAction.plain(
                    zoneRejectAction,
                    'Refuser…',
                    options: {DarwinNotificationActionOption.foreground},
                  ),
                ],
              ),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: responses.add,
      );
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(pushChannel);
    } catch (e) {
      debugPrint('Notifications locales indisponibles : $e');
    }
  }

  /// Notification touchée alors que l'app était fermée (elle démarre à cette occasion).
  static Future<NotificationResponse?> launchResponse() async {
    await init();
    try {
      final details = await plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp ?? false
          ? details!.notificationResponse
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Affiche une notification push : titre et texte, boutons selon sa catégorie ; ses
  /// données reviennent au toucher.
  static Future<void> showPush(
    Map<String, String> data, {
    String? title,
    String? body,
  }) async {
    await init();
    final zoneRequest = data['category'] == 'ZONE_REQUEST';
    await plugin.show(
      id:
          (data['requestId'] ?? data['google.message_id'] ?? jsonEncode(data))
              .hashCode &
          0x7fffffff,
      title: title ?? data['title'],
      body: body ?? data['body'],
      payload: jsonEncode(data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          pushChannel.id,
          pushChannel.name,
          channelDescription: pushChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          actions: zoneRequest
              ? const [
                  AndroidNotificationAction(
                    zoneApproveAction,
                    'Approuver',
                    showsUserInterface: true,
                  ),
                  AndroidNotificationAction(
                    zoneRejectAction,
                    'Refuser…',
                    showsUserInterface: true,
                  ),
                ]
              : null,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          categoryIdentifier: zoneRequest ? 'ZONE_REQUEST' : null,
        ),
      ),
    );
  }
}
