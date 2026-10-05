import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:suivi_agent/core/geo.dart';
import 'package:suivi_agent/core/models.dart';
import 'package:suivi_agent/core/zone_guard.dart';

import 'fakes.dart';

Zone _zone(String id, String name) => Zone(
  id: id,
  name: name,
  capacity: null,
  placesLeft: null,
  isFull: false,
  sensitive: false,
  area: plateauArea,
);

void main() {
  group('distance à la zone', () {
    test('nulle à l’intérieur, en mètres à l’extérieur', () {
      expect(distanceToArea(const LatLng(5.32, -4.02), plateauArea), 0);
      expect(distanceToArea(eastOfPlateau(100), plateauArea), closeTo(100, 2));
      // Au nord-est : distance au coin.
      final corner = distanceToArea(const LatLng(5.3309, -4.0091), plateauArea);
      expect(corner, closeTo(141, 3));
      expect(
        distanceToArea(const LatLng(5.32, -4.02), const []),
        double.infinity,
      );
    });

    test('format lisible', () {
      expect(formatMeters(4), '10 m');
      expect(formatMeters(347), '350 m');
      expect(formatMeters(1240), '1,2 km');
    });
  });

  group('surveillance de la zone', () {
    late FakeAlerts alerts;
    late ZoneGuard guard;
    final t0 = DateTime(2026, 10, 5, 9);
    DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

    setUp(() {
      alerts = FakeAlerts();
      guard = ZoneGuard(alerts)
        ..configure(
          zone: _zone('z1', 'Plateau'),
          tolerance: 30,
          alertMinutes: 5,
        );
    });

    test('tolère la bordure et les points imprécis', () {
      guard.onFix(eastOfPlateau(20), 5, at(0));
      guard.onFix(eastOfPlateau(100), 80, at(1));
      expect(guard.isOutside, isFalse);
      expect(alerts.shown, isEmpty);
      expect(guard.distance, closeTo(100, 2));
    });

    test(
      'alerte à la sortie, au délai du responsable, puis rappel et retour',
      () {
        guard.onFix(eastOfPlateau(500), 10, at(0));
        expect(guard.isOutside, isTrue);
        expect(alerts.shown.single.$1, 'Vous êtes hors de votre zone');
        expect(alerts.shown.single.$2, contains('500 m de Plateau'));

        guard.onFix(eastOfPlateau(550), 10, at(3));
        expect(alerts.shown, hasLength(1));

        guard.onFix(eastOfPlateau(600), 10, at(6));
        expect(guard.leadWarned, isTrue);
        expect(
          alerts.shown.last.$2,
          contains('Votre responsable a été prévenu'),
        );

        guard.onFix(eastOfPlateau(600), 10, at(12));
        expect(alerts.shown, hasLength(2));
        guard.onFix(eastOfPlateau(600), 10, at(22));
        expect(alerts.shown, hasLength(3));
        expect(alerts.shown.last.$2, contains('Depuis 22 min'));

        // Encore à 50 m (au-delà de la marge) : toujours dehors.
        guard.onFix(eastOfPlateau(50), 10, at(23));
        expect(guard.isOutside, isTrue);
        guard.onFix(eastOfPlateau(25), 10, at(24));
        expect(guard.isOutside, isFalse);
        expect(guard.leadWarned, isFalse);
        expect(alerts.shown.last.$1, 'De retour dans votre zone');
      },
    );

    test(
      'changement de zone et fin du suivi : l’alerte en cours est retirée',
      () {
        guard.onFix(eastOfPlateau(500), 10, at(0));
        guard.configure(
          zone: _zone('z1', 'Plateau'),
          tolerance: 30,
          alertMinutes: 5,
        );
        expect(guard.isOutside, isTrue);

        guard.configure(
          zone: _zone('z2', 'Cocody'),
          tolerance: 30,
          alertMinutes: 5,
        );
        expect(guard.isOutside, isFalse);
        expect(alerts.cancelled, 1);

        guard.onFix(eastOfPlateau(500), 10, at(1));
        guard.stop();
        expect(guard.zone, isNull);
        expect(guard.position, isNull);
        expect(alerts.cancelled, 2);
      },
    );

    test('sans contours de zone, aucune alerte', () {
      guard.configure(
        zone: Zone(
          id: 'z9',
          name: 'Sans carte',
          capacity: null,
          placesLeft: null,
          isFull: false,
          sensitive: false,
        ),
        tolerance: 30,
        alertMinutes: 5,
      );
      guard.onFix(eastOfPlateau(5000), 10, at(0));
      expect(guard.isOutside, isFalse);
      expect(guard.position, isNotNull);
    });
  });
}
