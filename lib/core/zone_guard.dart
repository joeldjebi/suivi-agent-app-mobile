import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'geo.dart';
import 'models.dart';

/// Affiche une alerte à l'agent, même application en arrière-plan.
abstract interface class AlertSink {
  /// Demande l'autorisation d'afficher des alertes (une seule fois).
  Future<void> prepare();
  Future<void> show(int id, String title, String body);
  Future<void> cancel(int id);
}

/// Imprécision maximale prise en compte : au-delà, le point ne fait pas sortir l'agent.
const _maxAccuracy = 100.0;

/// Rappel tant que l'agent reste dehors, après l'alerte de son responsable.
const reminderEvery = Duration(minutes: 15);

/// Surveille la position de l'agent par rapport à sa zone du jour, sur le téléphone :
/// l'alerte part tout de suite, même sans réseau. Mêmes seuils que le serveur :
/// - sortie : distance à la zone > marge + imprécision du point (plafonnée) ;
/// - retour : distance à la zone ≤ marge.
class ZoneGuard extends ChangeNotifier {
  ZoneGuard(this.sink);

  final AlertSink sink;

  static const alertId = 1001;

  Zone? _zone;
  int _tolerance = 30;
  int _alertMinutes = 5;

  LatLng? position;
  double? accuracy;

  /// Distance à la zone au dernier relevé, en mètres (0 dedans).
  double? distance;
  DateTime? outsideSince;
  DateTime? _lastAlert;
  bool _leadWarned = false;

  Zone? get zone => _zone;
  int get alertMinutes => _alertMinutes;
  bool get isOutside => outsideSince != null;

  /// Le responsable est prévenu (sortie plus longue que le délai de la structure).
  bool get leadWarned => _leadWarned;

  /// Zone du jour et réglages de la structure ; un changement de zone repart de zéro.
  void configure({
    required Zone? zone,
    required int tolerance,
    required int alertMinutes,
  }) {
    _tolerance = tolerance;
    _alertMinutes = alertMinutes;
    if (zone?.id == _zone?.id) {
      _zone = zone;
      return;
    }
    _zone = zone;
    _clearOutside();
    notifyListeners();
  }

  /// Fin du suivi (pause, fin de journée, déconnexion).
  void stop() {
    _zone = null;
    position = null;
    accuracy = null;
    distance = null;
    _clearOutside();
    notifyListeners();
  }

  void _clearOutside() {
    if (outsideSince != null) unawaited(sink.cancel(alertId));
    outsideSince = null;
    _lastAlert = null;
    _leadWarned = false;
  }

  void onFix(LatLng point, double accuracy, DateTime at) {
    position = point;
    this.accuracy = accuracy;
    final zone = _zone;
    if (zone == null || zone.area.isEmpty) {
      notifyListeners();
      return;
    }
    final d = distanceToArea(point, zone.area);
    distance = d;
    final since = outsideSince;

    if (since == null) {
      final margin = _tolerance + math.min(math.max(accuracy, 0), _maxAccuracy);
      if (d > margin) {
        outsideSince = at;
        _lastAlert = at;
        _alert(
          'Vous êtes hors de votre zone',
          'Vous êtes à ${formatMeters(d)} de ${zone.name}. Au-delà de $_alertMinutes min, votre responsable est prévenu.',
        );
      }
    } else if (d <= _tolerance) {
      outsideSince = null;
      _lastAlert = null;
      _leadWarned = false;
      _alert(
        'De retour dans votre zone',
        'Vous êtes de nouveau dans ${zone.name}.',
      );
    } else {
      final out = at.difference(since);
      final minutes = math.max(1, out.inMinutes);
      if (!_leadWarned && out >= Duration(minutes: _alertMinutes)) {
        _leadWarned = true;
        _lastAlert = at;
        _alert(
          'Toujours hors de votre zone',
          'Depuis $minutes min, à ${formatMeters(d)} de ${zone.name}. Votre responsable a été prévenu.',
        );
      } else if (_leadWarned &&
          _lastAlert != null &&
          at.difference(_lastAlert!) >= reminderEvery) {
        _lastAlert = at;
        _alert(
          'Toujours hors de votre zone',
          'Depuis $minutes min, à ${formatMeters(d)} de ${zone.name}. Revenez dès que possible.',
        );
      }
    }
    notifyListeners();
  }

  void _alert(String title, String body) =>
      unawaited(sink.show(alertId, title, body));
}
