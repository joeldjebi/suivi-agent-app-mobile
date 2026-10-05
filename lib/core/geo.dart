import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const _earthRadius = 6371000.0;

/// Distance en mètres entre un point et une zone (ses anneaux extérieurs) : 0 à l'intérieur.
///
/// Projection locale autour du point : précise à quelques mètres près à l'échelle d'un
/// quartier, ce qui suffit pour comparer à une marge de tolérance.
double distanceToArea(LatLng point, List<List<LatLng>> rings) {
  if (rings.every((r) => r.length < 3)) return double.infinity;
  final cosLat = math.cos(point.latitude * math.pi / 180);
  math.Point<double> project(LatLng p) => math.Point(
    (p.longitude - point.longitude) * math.pi / 180 * _earthRadius * cosLat,
    (p.latitude - point.latitude) * math.pi / 180 * _earthRadius,
  );

  var best = double.infinity;
  for (final ring in rings) {
    if (ring.length < 3) continue;
    final pts = ring.map(project).toList();
    if (_contains(pts)) return 0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      best = math.min(best, _toSegment(a, b));
    }
  }
  return best;
}

/// Le point (origine de la projection) est-il dans l'anneau ? Lancer de rayon.
bool _contains(List<math.Point<double>> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    if ((a.y > 0) != (b.y > 0) &&
        0 < (b.x - a.x) * (0 - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// Distance de l'origine au segment [a, b].
double _toSegment(math.Point<double> a, math.Point<double> b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final length2 = dx * dx + dy * dy;
  final t = length2 == 0
      ? 0.0
      : (-(a.x * dx + a.y * dy) / length2).clamp(0.0, 1.0);
  final x = a.x + t * dx;
  final y = a.y + t * dy;
  return math.sqrt(x * x + y * y);
}

/// « 350 m », « 1,2 km ».
String formatMeters(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }
  return '${math.max(10, (meters / 10).round() * 10)} m';
}
