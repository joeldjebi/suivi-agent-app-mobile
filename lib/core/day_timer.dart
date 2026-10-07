import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'format.dart';
import 'local_notifications.dart';

/// Journée affichée sur l'écran verrouillé.
class DayTimerInfo {
  const DayTimerInfo({
    required this.paused,
    required this.worked,
    required this.objective,
    required this.structure,
    this.pausedAt,
    this.zone,
  });

  final bool paused;

  /// Temps travaillé à l'instant de l'affichage, pauses déduites.
  final Duration worked;
  final Duration objective;
  final DateTime? pausedAt;
  final String? zone;
  final String structure;

  @override
  bool operator ==(Object other) =>
      other is DayTimerInfo &&
      other.paused == paused &&
      // Le chrono avance seul : seul un écart réel (pause, reprise) impose une mise à jour.
      (other.worked - worked).inSeconds.abs() < 5 &&
      other.objective == objective &&
      other.pausedAt == pausedAt &&
      other.zone == zone &&
      other.structure == structure;

  @override
  int get hashCode => Object.hash(paused, objective, pausedAt, zone, structure);
}

/// Chrono de la journée hors de l'app (remplacé dans les tests).
abstract interface class DayTimer {
  Future<void> show(DayTimerInfo info);
  Future<void> clear();
}

class NoDayTimer implements DayTimer {
  const NoDayTimer();

  @override
  Future<void> show(DayTimerInfo info) async {}

  @override
  Future<void> clear() async {}
}

/// Android : notification permanente avec chronomètre et progression vers l'objectif.
/// iPhone : Live Activity sur l'écran verrouillé et dans la Dynamic Island (iOS 16.2+).
class DeviceDayTimer implements DayTimer {
  static const _id = 7001;
  static const _activity = MethodChannel('suivi_agent/day_activity');
  static const _channel = AndroidNotificationChannel(
    'day_timer',
    'Chrono de la journée',
    description: 'Temps travaillé et objectif, pendant la journée',
    importance: Importance.low,
    showBadge: false,
  );

  DayTimerInfo? _last;

  /// Au lancement, une activité d'une session précédente peut rester affichée (journée
  /// terminée depuis le web, app fermée) : le premier retrait s'applique toujours.
  bool _fresh = true;

  @override
  Future<void> show(DayTimerInfo info) async {
    if (info == _last) return;
    _last = info;
    _fresh = false;
    try {
      if (Platform.isIOS) {
        await _activity.invokeMethod<bool>('show', {
          'status': info.paused ? 'paused' : 'active',
          'workedSeconds': info.worked.inSeconds,
          'pausedAtMs': info.pausedAt?.millisecondsSinceEpoch,
          'objectiveSeconds': info.objective.inSeconds,
          'zone': info.zone,
          'structure': info.structure,
        });
      } else if (Platform.isAndroid) {
        await _showAndroid(info);
      }
    } catch (e) {
      debugPrint('Chrono de la journée indisponible : $e');
    }
  }

  Future<void> _showAndroid(DayTimerInfo info) async {
    await LocalNotifications.init();
    final plugin = LocalNotifications.plugin;
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    final now = DateTime.now();
    final objectiveMinutes = info.objective.inMinutes.clamp(1, 24 * 60);
    final workedMinutes = info.worked.inMinutes.clamp(0, objectiveMinutes);
    final where = info.zone == null ? '' : ' · ${info.zone}';
    await plugin.show(
      id: _id,
      title: info.paused ? 'En pause$where' : 'Journée en cours$where',
      body: info.paused
          ? '${formatDuration(info.worked)} travaillées · objectif ${formatDuration(info.objective)}'
          : 'Objectif ${formatDuration(info.objective)} · ${(workedMinutes * 100 / objectiveMinutes).round()} %',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          silent: true,
          category: AndroidNotificationCategory.progress,
          // Le chronomètre tourne seul : temps travaillé en journée, durée de la pause en pause.
          showWhen: true,
          usesChronometer: true,
          when: info.paused
              ? (info.pausedAt ?? now).millisecondsSinceEpoch
              : now.subtract(info.worked).millisecondsSinceEpoch,
          showProgress: true,
          maxProgress: objectiveMinutes,
          progress: workedMinutes,
          subText: info.paused ? 'durée de la pause' : 'temps travaillé',
        ),
      ),
    );
  }

  @override
  Future<void> clear() async {
    if (_last == null && !_fresh) return;
    _last = null;
    _fresh = false;
    try {
      if (Platform.isIOS) {
        await _activity.invokeMethod<bool>('end');
      } else if (Platform.isAndroid) {
        await LocalNotifications.plugin.cancel(id: _id);
      }
    } catch (_) {
      // Rien à retirer.
    }
  }
}
