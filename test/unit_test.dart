import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivi_agent/core/branding.dart';
import 'package:suivi_agent/core/models.dart';
import 'package:suivi_agent/core/phone_format.dart';

void main() {
  group('Saisie du numéro', () {
    final formatter = PhoneInputFormatter();
    String format(String input) => formatter
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: input))
        .text;

    test('groupe les chiffres par paires', () {
      expect(format('0707070707'), '07 07 07 07 07');
      expect(format('07a07-07'), '07 07 07');
    });

    test('conserve le format international', () {
      expect(format('+2250707070707'), '+225 07 07 07 07 07');
    });

    test('valide la longueur', () {
      expect(isPlausiblePhone('07 07 07 07 07'), isTrue);
      expect(isPlausiblePhone('0707'), isFalse);
    });
  });

  group('Journée', () {
    test('le temps travaillé déduit les pauses terminées et en cours', () {
      final start = DateTime(2026, 10, 2, 8);
      final day = WorkDay.fromJson({
        'id': 'd1',
        'status': 'paused',
        'zoneId': null,
        'startedAt': start.toUtc().toIso8601String(),
        'endedAt': null,
        'pauses': [
          {
            'startedAt': start
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
            'endedAt': start
                .add(const Duration(hours: 1, minutes: 30))
                .toUtc()
                .toIso8601String(),
          },
          {
            'startedAt': start
                .add(const Duration(hours: 3))
                .toUtc()
                .toIso8601String(),
            'endedAt': null,
          },
        ],
      });
      // 4 h écoulées - 30 min de pause terminée - 1 h de pause en cours
      expect(
        day.worked(start.add(const Duration(hours: 4))),
        const Duration(hours: 2, minutes: 30),
      );
    });
  });

  group('Missions et équipe', () {
    test('lit le statut « in_progress » et les contributions', () {
      final m = Mission.fromJson({
        'id': 'm1',
        'title': 'Collecte',
        'status': 'in_progress',
        'progressMethod': 'field_sum',
        'dueDate': null,
        'assigneeGroupId': 'g1',
        'progress': {'current': 1500, 'target': 3000, 'percent': 50},
        'contributions': [
          {'firstName': 'Koffi', 'lastName': 'Brou', 'value': 1500},
        ],
      });
      expect(m.status, MissionStatus.inProgress);
      expect(m.forGroup, isTrue);
      expect(m.contributions.single.name, 'Koffi Brou');
    });

    test('une alerte agent : signal perdu, hors zone ou position simulée', () {
      LiveAgent agent({bool lost = false, bool outside = false}) =>
          LiveAgent.fromJson({
            'dayId': 'd',
            'agent': {'id': 'a', 'firstName': 'A', 'lastName': 'B'},
            'status': 'active',
            'zoneId': null,
            'startedAt': DateTime.now().toUtc().toIso8601String(),
            'position': outside
                ? {
                    'lat': 5.32,
                    'lng': -4.02,
                    'recordedAt': DateTime.now().toUtc().toIso8601String(),
                    'outsideZone': true,
                  }
                : null,
            'signalLost': lost,
          });
      expect(agent().hasAlert, isFalse);
      expect(agent(lost: true).hasAlert, isTrue);
      expect(agent(outside: true).hasAlert, isTrue);
      expect(agent(outside: true).position?.latitude, 5.32);
      expect(agent().position, isNull);
    });

    test('contour de zone : Polygon et MultiPolygon GeoJSON', () {
      Zone zone(Map<String, dynamic> area) => Zone.fromJson({
        'id': 'z',
        'name': 'Z',
        'isFull': false,
        'area': area,
      });
      final poly = zone({
        'type': 'Polygon',
        'coordinates': [
          [
            [-4.0, 5.34],
            [-3.96, 5.34],
            [-3.96, 5.37],
            [-4.0, 5.34],
          ],
        ],
      });
      // GeoJSON : [longitude, latitude].
      expect(poly.area.single.first.latitude, 5.34);
      expect(poly.area.single.first.longitude, -4.0);
      expect(poly.center, isNotNull);
      final multi = zone({
        'type': 'MultiPolygon',
        'coordinates': [
          [
            [
              [-4.0, 5.3],
              [-3.9, 5.3],
              [-3.9, 5.4],
            ],
          ],
          [
            [
              [-3.8, 5.3],
              [-3.7, 5.3],
              [-3.7, 5.4],
            ],
          ],
        ],
      });
      expect(multi.area, hasLength(2));
    });
  });

  group('Personnalisation', () {
    test('lit la couleur de la structure et revient au défaut si invalide', () {
      final b = Branding.fromJson({
        'displayName': 'X',
        'primaryColor': '#0F766E',
        'onPrimaryColor': '#FFFFFF',
      });
      expect(b.primary, const Color(0xFF0F766E));
      expect(Branding.toHex(b.primary), '#0F766E');
      final invalid = Branding.fromJson({
        'displayName': 'X',
        'primaryColor': 'rouge',
        'onPrimaryColor': '#FFFFFF',
      });
      expect(invalid.primary, Branding.defaults.primary);
    });
  });
}
