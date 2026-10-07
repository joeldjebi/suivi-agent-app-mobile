import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:drift/drift.dart' show Value;

import 'database.dart';

/// Rythme du suivi, adapté à la situation pour ménager la batterie.
enum PowerMode {
  /// En mouvement : précision maximale.
  normal,

  /// Immobile depuis quelques minutes : relevés espacés, précision moyenne.
  still,

  /// Batterie faible (hors charge) : suivi allégé.
  saver,
}

enum LocationAccess {
  granted,
  needsAlways,
  denied,
  deniedForever,
  serviceDisabled,
}

/// Suivi de position pendant la journée (RG-11, RG-12).
///
/// La fréquence suit le déplacement (filtre de distance) ; un relevé de contrôle est fait
/// régulièrement quand l'agent ne bouge pas, pour ne pas apparaître en « signal perdu ».
/// Sur Android, un service de premier plan (notification permanente) maintient le suivi
/// écran éteint ; sur iOS, le mode « localisation en arrière-plan ».
class LocationTracker extends ChangeNotifier {
  LocationTracker(this.db);

  final AppDatabase db;

  StreamSubscription<Position>? _subscription;
  Timer? _heartbeat;
  String? _dayId;
  DateTime? lastFixAt;
  String? error;

  /// Dernière position relevée pendant la journée.
  LatLng? lastPosition;

  /// Appelé à chaque relevé (surveillance de la zone).
  void Function(LatLng position, double accuracy, DateTime at)? onFix;

  bool get isTracking => _subscription != null;

  static const distanceFilterMeters = 25;
  static const heartbeat = Duration(minutes: 3);

  /// GPS adaptatif : immobile au-delà de [stillAfter] dans un rayon de [stillRadius],
  /// économie sous [saverBelow] de batterie (hors charge).
  static const stillAfter = Duration(minutes: 5);
  static const stillRadius = 40.0;
  static const saverBelow = 0.2;

  PowerMode mode = PowerMode.normal;
  String _structure = '';
  LatLng? _anchor;
  DateTime? _anchorAt;

  /// Batterie : relue au plus une fois par minute.
  final _batteryApi = Battery();
  double? battery;
  bool charging = false;
  DateTime? _batteryAt;

  Future<LocationAccess> access({bool request = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (request && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    // Le suivi écran éteint demande « Toujours » ; on le redemande après « Pendant l'utilisation ».
    if (request && permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always => LocationAccess.granted,
      LocationPermission.whileInUse => LocationAccess.needsAlways,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  /// Démarre (ou reprend) le suivi pour la journée [dayId].
  Future<void> start(String dayId, {required String structure}) async {
    if (_dayId == dayId && isTracking) return;
    await stop();
    _dayId = dayId;
    _structure = structure;
    error = null;
    mode = PowerMode.normal;
    _anchor = null;
    _anchorAt = null;
    _listen();
    _heartbeat = Timer.periodic(heartbeat, (_) => _checkIn());
    unawaited(_checkIn());
    notifyListeners();
  }

  void _listen() {
    _subscription =
        Geolocator.getPositionStream(
          locationSettings: _settings(_structure),
        ).listen(
          _record,
          onError: (Object e) {
            error = 'Position indisponible';
            notifyListeners();
          },
        );
  }

  /// Nouveau rythme : le flux de positions repart avec les réglages adaptés.
  Future<void> _switchMode(PowerMode next) async {
    if (next == mode || _subscription == null) return;
    mode = next;
    await _subscription?.cancel();
    _listen();
    notifyListeners();
  }

  Future<void> _readBattery() async {
    final now = DateTime.now();
    if (_batteryAt != null &&
        now.difference(_batteryAt!) < const Duration(minutes: 1)) {
      return;
    }
    _batteryAt = now;
    try {
      battery = (await _batteryApi.batteryLevel) / 100;
      final state = await _batteryApi.batteryState;
      charging = state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {
      // Batterie illisible (simulateur, tests) : pas d'économie automatique.
    }
  }

  /// Rythme voulu d'après la batterie et l'immobilité.
  PowerMode _wantedMode(LatLng at, DateTime now) {
    final anchor = _anchor;
    if (anchor == null ||
        const Distance().as(LengthUnit.Meter, anchor, at) > stillRadius) {
      _anchor = at;
      _anchorAt = now;
    }
    return decideMode(
      battery: battery,
      charging: charging,
      stillFor: now.difference(_anchorAt!),
    );
  }

  /// Batterie faible hors charge : économie ; immobile assez longtemps : relevés espacés.
  static PowerMode decideMode({
    required double? battery,
    required bool charging,
    required Duration stillFor,
  }) {
    if (battery != null && battery < saverBelow && !charging) {
      return PowerMode.saver;
    }
    return stillFor >= stillAfter ? PowerMode.still : PowerMode.normal;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _dayId = null;
    lastPosition = null;
    notifyListeners();
  }

  /// Relevé ponctuel si aucune position récente (agent immobile).
  Future<void> _checkIn() async {
    if (lastFixAt != null &&
        DateTime.now().difference(lastFixAt!) < heartbeat) {
      return;
    }
    try {
      _record(
        await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: mode == PowerMode.normal
                ? LocationAccuracy.high
                : LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 30),
          ),
        ),
      );
    } catch (_) {
      // Pas de signal : réessai au prochain contrôle.
    }
  }

  Future<void> _record(Position p) async {
    final dayId = _dayId;
    if (dayId == null) return;
    lastFixAt = DateTime.now();
    error = null;
    lastPosition = LatLng(p.latitude, p.longitude);
    await _readBattery();
    onFix?.call(lastPosition!, p.accuracy, p.timestamp.toLocal());
    await db
        .into(db.pendingPositions)
        .insert(
          PendingPositionsCompanion.insert(
            dayId: dayId,
            lat: p.latitude,
            lng: p.longitude,
            accuracy: p.accuracy,
            speed: Value(p.speed >= 0 ? p.speed : null),
            isMocked: Value(p.isMocked),
            recordedAt: p.timestamp.toUtc(),
            battery: Value(battery),
          ),
        );
    unawaited(_switchMode(_wantedMode(lastPosition!, lastFixAt!)));
    notifyListeners();
  }

  /// Dernière position connue (pour géolocaliser un formulaire).
  Future<Position?> lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 8),
            ),
          );
    } catch (_) {
      return null;
    }
  }

  LocationSettings _settings(String structure) {
    final (accuracy, distance, interval) = switch (mode) {
      PowerMode.normal => (
        LocationAccuracy.high,
        distanceFilterMeters,
        const Duration(seconds: 20),
      ),
      PowerMode.still => (
        LocationAccuracy.medium,
        50,
        const Duration(seconds: 60),
      ),
      PowerMode.saver => (
        LocationAccuracy.medium,
        75,
        const Duration(seconds: 90),
      ),
    };
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distance,
        intervalDuration: interval,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Position partagée',
          notificationText:
              'Votre position est partagée avec $structure jusqu’à la fin de votre journée.',
          notificationChannelName: 'Suivi de la journée',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: mode == PowerMode.normal ? LocationAccuracy.best : accuracy,
        distanceFilter: distance,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: distance);
  }
}
