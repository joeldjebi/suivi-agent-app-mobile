import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:drift/drift.dart' show Value;

import 'database.dart';

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
    error = null;
    _subscription =
        Geolocator.getPositionStream(
          locationSettings: _settings(structure),
        ).listen(
          _record,
          onError: (Object e) {
            error = 'Position indisponible';
            notifyListeners();
          },
        );
    _heartbeat = Timer.periodic(heartbeat, (_) => _checkIn());
    unawaited(_checkIn());
    notifyListeners();
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
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 30),
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
          ),
        );
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
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        intervalDuration: const Duration(seconds: 20),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Journée en cours',
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
        accuracy: LocationAccuracy.best,
        distanceFilter: distanceFilterMeters,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilterMeters,
    );
  }
}
