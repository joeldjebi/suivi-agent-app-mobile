import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models.dart';
import 'outlet_activity.dart' show OutletVisitEntry;

/// Statut commercial d'un point de vente (mêmes couleurs que le site).
enum OutletStatus {
  newOutlet('new', 'Nouveau', Color(0xFF2563EB), 'sparkles'),
  prospect('prospect', 'Prospect', Color(0xFFD97706), 'target'),
  active('active', 'Client actif', Color(0xFF16A34A), 'circleCheck'),
  inactive('inactive', 'Inactif', Color(0xFF64748B), 'circlePause'),
  closed('closed', 'Fermé', Color(0xFFDC2626), 'circleSlash');

  const OutletStatus(this.code, this.label, this.color, this.icon);

  final String code;
  final String label;
  final Color color;

  /// Icône Lucide (la même que sur le site).
  final String icon;

  static OutletStatus from(String? code) => OutletStatus.values.firstWhere(
    (s) => s.code == code,
    orElse: () => OutletStatus.newOutlet,
  );
}

String _plain(String s) {
  const from = 'àâäéèêëîïôöùûüç';
  const to = 'aaaeeeeiioouuuc';
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}

/// Icône Lucide du type de commerce (mêmes icônes et mêmes règles que le site).
String categoryIcon(String? category) {
  final text = _plain(category ?? '');
  bool has(List<String> words) => words.any(text.contains);
  if (has(['pharma'])) return 'pill';
  if (has(['maquis', 'bar', 'cave', 'buvette'])) return 'beer';
  if (has(['restau', 'cantine', 'fast', 'snack'])) return 'utensilsCrossed';
  if (has(['station', 'carburant', 'essence'])) return 'fuel';
  if (has(['grossiste'])) return 'warehouse';
  if (has(['superette', 'supermarche', 'alimentation', 'epicerie'])) {
    return 'shoppingCart';
  }
  if (has(['kiosque', 'mobile money', 'cabine'])) return 'smartphone';
  if (has(['marche', 'etal'])) return 'shoppingBasket';
  return 'store';
}

class Outlet {
  Outlet({
    required this.id,
    required this.name,
    required this.status,
    required this.statusChangedAt,
    this.category,
    this.managerName,
    this.phone,
    this.landmark,
    this.position,
    this.photoId,
    this.data = const {},
    this.zoneName,
    this.createdBy,
    this.distance,
    this.lastVisitAt,
    this.daysSinceVisit,
    this.dueAt,
    this.overdue = false,
    this.frequencyDays = 0,
    this.visitFrequencyDays,
  });

  /// Dernière visite acceptée (null : jamais visité).
  final DateTime? lastVisitAt;
  final int? daysSinceVisit;

  /// Visite attendue au plus tard (null : pas de suivi).
  final DateTime? dueAt;

  /// En retard de visite (fréquence dépassée).
  final bool overdue;

  /// Fréquence appliquée en jours (0 : pas de suivi).
  final int frequencyDays;

  /// Fréquence propre au point de vente ; null : celle de la structure.
  final int? visitFrequencyDays;

  /// « Visité il y a 12 j », « Visité aujourd'hui », « Jamais visité ».
  String get visitLabel => lastVisitAt == null || daysSinceVisit == null
      ? 'Jamais visité'
      : daysSinceVisit == 0
      ? 'Visité aujourd’hui'
      : 'Visité il y a $daysSinceVisit j';

  final String id;
  final String name;
  final String? category;
  final String? managerName;
  final String? phone;
  final String? landmark;

  /// Absente : point de vente importé « à localiser ».
  final LatLng? position;
  final OutletStatus status;
  final DateTime statusChangedAt;
  final String? photoId;
  final Map<String, dynamic> data;
  final String? zoneName;
  final String? createdBy;

  /// Distance en mètres (liste autour de l'agent).
  final int? distance;

  bool get located => position != null;

  factory Outlet.fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lng = (j['lng'] as num?)?.toDouble();
    return Outlet(
      id: j['id'] as String,
      name: j['name'] as String,
      category: j['category'] as String?,
      managerName: j['managerName'] as String?,
      phone: j['phone'] as String?,
      landmark: j['landmark'] as String?,
      position: lat != null && lng != null ? LatLng(lat, lng) : null,
      status: OutletStatus.from(j['status'] as String?),
      statusChangedAt: DateTime.parse(j['statusChangedAt'] as String),
      photoId: j['photoId'] as String?,
      data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      zoneName: (j['zone'] as Map?)?['name'] as String?,
      createdBy: (j['createdBy'] as Map?)?['name'] as String?,
      distance: (j['distance'] as num?)?.round(),
      lastVisitAt: j['lastVisitAt'] == null
          ? null
          : DateTime.parse(j['lastVisitAt'] as String).toLocal(),
      daysSinceVisit: (j['daysSinceVisit'] as num?)?.toInt(),
      dueAt: j['dueAt'] == null
          ? null
          : DateTime.parse(j['dueAt'] as String).toLocal(),
      overdue: j['overdue'] as bool? ?? false,
      frequencyDays: (j['frequencyDays'] as num?)?.toInt() ?? 0,
      visitFrequencyDays: (j['visitFrequencyDays'] as num?)?.toInt(),
    );
  }
}

class OutletChange {
  OutletChange({
    required this.from,
    required this.to,
    required this.at,
    this.comment,
    this.user,
  });

  final OutletStatus? from;
  final OutletStatus to;
  final DateTime at;
  final String? comment;
  final String? user;

  factory OutletChange.fromJson(Map<String, dynamic> j) => OutletChange(
    from: j['fromStatus'] == null
        ? null
        : OutletStatus.from(j['fromStatus'] as String),
    to: OutletStatus.from(j['toStatus'] as String),
    at: DateTime.parse(j['createdAt'] as String).toLocal(),
    comment: j['comment'] as String?,
    user: (j['user'] as Map?)?['name'] as String?,
  );
}

class OutletDetail {
  OutletDetail(this.outlet, this.history, [this.visits = const []]);

  final Outlet outlet;
  final List<OutletChange> history;

  /// Dernières visites (missions et visites libres).
  final List<OutletVisitEntry> visits;

  factory OutletDetail.fromJson(Map<String, dynamic> j) => OutletDetail(
    Outlet.fromJson(j),
    [
      for (final h in j['history'] as List? ?? const [])
        OutletChange.fromJson(h as Map<String, dynamic>),
    ],
    [
      for (final v in j['visits'] as List? ?? const [])
        OutletVisitEntry.fromJson(v as Map<String, dynamic>),
    ],
  );
}

/// Fiche définie par la structure et types de commerce proposés.
class OutletForm {
  OutletForm({required this.fields, required this.categories});

  final List<MissionField> fields;
  final List<String> categories;

  factory OutletForm.fromJson(Map<String, dynamic> j) => OutletForm(
    fields: [
      for (final f in j['fields'] as List? ?? const [])
        MissionField.fromJson(f as Map<String, dynamic>),
    ],
    categories: (j['categories'] as List? ?? const []).cast<String>(),
  );
}

/// Point de vente semblable signalé avant un ajout.
class OutletCandidate {
  OutletCandidate({
    required this.id,
    required this.name,
    required this.status,
    required this.distance,
  });

  final String id;
  final String name;
  final OutletStatus status;
  final int distance;

  factory OutletCandidate.fromJson(Map<String, dynamic> j) => OutletCandidate(
    id: j['id'] as String,
    name: j['name'] as String,
    status: OutletStatus.from(j['status'] as String?),
    distance: (j['distance'] as num).round(),
  );
}
