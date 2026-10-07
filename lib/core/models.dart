/// Modèles des réponses de l'API (voir Swagger : /api/docs).
library;

import 'package:latlong2/latlong.dart';

import 'format.dart';

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();
double _num(Object? v) => v == null ? 0 : (v as num).toDouble();

enum DayStatus { active, paused, ended }

enum RequestStatus { pending, approved, rejected, expired, cancelled, released }

enum MissionStatus { todo, inProgress, achieved, failed }

T _enum<T extends Enum>(List<T> values, String raw, Map<String, T> aliases) =>
    aliases[raw] ?? values.firstWhere((v) => v.name == raw);

class Me {
  Me({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.tenantName,
    required this.trackDuringPause,
    required this.allowZoneChangeBeforeStart,
    required this.zoneRequired,
    this.zoneExitToleranceMeters = 30,
    this.zoneExitAlertMinutes = 5,
    this.submissionRequiresDay = true,
    this.workdayMinutes = 480,
    this.phone,
    this.avatarVersion,
    this.subscriptionStatus = 'active',
    this.features = const {
      'groups',
      'manual_approval',
      'missions',
      'branding',
      'exports',
      'stats',
      'team_leads',
      'audit',
    },
  });

  /// État de l'abonnement de la structure (trialing, active, past_due, suspended…).
  final String subscriptionStatus;

  /// Fonctionnalités ouvertes par la formule de la structure.
  final Set<String> features;

  bool get suspended => subscriptionStatus == 'suspended';
  bool get hasMissions => features.contains('missions');

  /// Rémunération calculée par la plateforme (formule Entreprise).
  bool get hasPayroll => features.contains('payroll');

  final String id;

  /// Numéro de connexion (format international).
  final String? phone;

  /// Version de la photo de profil, null sans photo.
  final int? avatarVersion;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String tenantName;
  final bool trackDuringPause;
  final bool allowZoneChangeBeforeStart;
  final bool zoneRequired;

  /// Formulaires envoyés seulement pendant une journée dans une zone de la mission.
  final bool submissionRequiresDay;

  /// Agent : durée de travail attendue par jour (la sienne, celle de son groupe ou de la structure).
  final int workdayMinutes;

  /// Marge autour de la zone avant de compter une sortie, en mètres.
  final int zoneExitToleranceMeters;

  /// Durée hors zone avant de prévenir le responsable, en minutes.
  final int zoneExitAlertMinutes;

  bool get isAgent => role == 'agent';
  bool get isTeamLead => role == 'team_lead';
  String get fullName => '$firstName $lastName';
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
          .toUpperCase();

  factory Me.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    final settings = json['settings'] as Map<String, dynamic>;
    return Me(
      id: user['id'] as String,
      firstName: user['firstName'] as String,
      lastName: user['lastName'] as String,
      email: user['email'] as String,
      role: user['role'] as String,
      tenantName: (json['tenant'] as Map<String, dynamic>)['name'] as String,
      trackDuringPause: settings['trackDuringPause'] as bool,
      allowZoneChangeBeforeStart:
          settings['allowZoneChangeBeforeStart'] as bool,
      zoneRequired: settings['zoneRequired'] as bool,
      submissionRequiresDay: settings['submissionRequiresDay'] as bool? ?? true,
      workdayMinutes:
          ((json['workday'] as Map<String, dynamic>?)?['minutes'] as num?)
              ?.toInt() ??
          480,
      zoneExitToleranceMeters:
          settings['zoneExitToleranceMeters'] as int? ?? 30,
      zoneExitAlertMinutes: settings['zoneExitAlertMinutes'] as int? ?? 5,
      phone: user['phone'] as String?,
      avatarVersion: user['avatarVersion'] as int?,
      subscriptionStatus:
          (json['subscription'] as Map<String, dynamic>?)?['status']
              as String? ??
          'active',
      features: json['subscription'] == null
          ? const {
              'groups',
              'manual_approval',
              'missions',
              'branding',
              'exports',
              'stats',
              'team_leads',
              'audit',
            }
          : {
              for (final f
                  in (json['subscription'] as Map<String, dynamic>)['features']
                      as List)
                f as String,
            },
    );
  }
}

class Zone {
  Zone({
    required this.id,
    required this.name,
    required this.capacity,
    required this.placesLeft,
    required this.isFull,
    required this.sensitive,
    this.mine,
    this.area = const [],
    this.missions = const [],
    this.groupIds = const [],
  });

  /// Groupes actifs de la zone ; vide : zone libre, ouverte à tous.
  final List<String> groupIds;

  /// Agent : missions en cours de cette zone qui le concernent (choix de la zone).
  final List<ZoneMission> missions;

  final String id;
  final String name;

  /// Contours de la zone (anneaux extérieurs), vides si l'API ne les envoie pas.
  final List<List<LatLng>> area;
  final int? capacity;
  final int? placesLeft;
  final bool isFull;
  final bool sensitive;

  /// Statut de la demande de l'agent sur cette zone, s'il y en a une.
  final RequestStatus? mine;

  factory Zone.fromJson(Map<String, dynamic> json) => Zone(
    id: json['id'] as String,
    name: json['name'] as String,
    capacity: json['capacity'] as int?,
    placesLeft: json['placesLeft'] as int?,
    isFull: json['isFull'] as bool,
    sensitive: json['sensitive'] as bool? ?? false,
    mine: json['mine'] == null
        ? null
        : RequestStatus.values.byName(json['mine'] as String),
    area: _rings(json['area']),
    groupIds: (json['groupIds'] as List? ?? const []).cast<String>(),
    missions: (json['missions'] as List? ?? [])
        .map((m) => ZoneMission.fromJson(m as Map<String, dynamic>))
        .toList(),
  );

  /// Milieu du bord nord : l'étiquette se place au-dessus de la zone, pas sur les agents.
  LatLng? get top {
    final points = area.expand((r) => r).toList();
    if (points.isEmpty) return null;
    final lngs = points.map((p) => p.longitude);
    return LatLng(
      points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
      (lngs.reduce((a, b) => a < b ? a : b) +
              lngs.reduce((a, b) => a > b ? a : b)) /
          2,
    );
  }

  /// Centre approximatif (moyenne des sommets).
  LatLng? get center {
    final points = area.expand((r) => r).toList();
    if (points.isEmpty) return null;
    return LatLng(
      points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
      points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
    );
  }
}

/// Anneaux extérieurs d'un Polygon ou d'un MultiPolygon GeoJSON.
List<List<LatLng>> _rings(Object? geo) {
  if (geo is! Map<String, dynamic>) return const [];
  List<LatLng> ring(Object? coords) => [
    for (final c in coords as List) LatLng(_num((c as List)[1]), _num(c[0])),
  ];
  final coords = geo['coordinates'] as List?;
  if (coords == null || coords.isEmpty) return const [];
  return switch (geo['type']) {
    'Polygon' => [ring(coords.first)],
    'MultiPolygon' => [for (final poly in coords) ring((poly as List).first)],
    _ => const [],
  };
}

/// Point de l'itinéraire d'une journée.
class TrackPoint {
  TrackPoint({
    required this.position,
    required this.recordedAt,
    required this.outsideZone,
  });

  final LatLng position;
  final DateTime recordedAt;
  final bool outsideZone;

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
    position: LatLng(_num(json['lat']), _num(json['lng'])),
    recordedAt: _date(json['recordedAt'])!,
    outsideZone: json['outsideZone'] as bool? ?? false,
  );
}

class ZoneRequest {
  ZoneRequest({
    required this.id,
    required this.zoneId,
    required this.status,
    required this.expiresAt,
    required this.isChange,
  });

  final String id;
  final String zoneId;
  final RequestStatus status;
  final DateTime? expiresAt;
  final bool isChange;

  factory ZoneRequest.fromJson(Map<String, dynamic> json) => ZoneRequest(
    id: json['id'] as String,
    zoneId: json['zoneId'] as String,
    status: RequestStatus.values.byName(json['status'] as String),
    expiresAt: _date(json['expiresAt']),
    isChange: json['isChange'] as bool? ?? false,
  );
}

class AvailableZones {
  AvailableZones({required this.zones, required this.groupMissing});

  final List<Zone> zones;
  final bool groupMissing;

  factory AvailableZones.fromJson(Map<String, dynamic> json) => AvailableZones(
    zones: (json['zones'] as List)
        .map((z) => Zone.fromJson(z as Map<String, dynamic>))
        .toList(),
    groupMissing: json['groupMissing'] as bool? ?? false,
  );
}

class WorkDay {
  WorkDay({
    required this.id,
    required this.status,
    required this.zoneId,
    required this.startedAt,
    required this.endedAt,
    required this.pausedSeconds,
    required this.currentPauseStartedAt,
  });

  final String id;
  final DayStatus status;
  final String? zoneId;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Durée des pauses terminées, en secondes (la pause en cours est calculée à part).
  final int pausedSeconds;
  final DateTime? currentPauseStartedAt;

  /// Temps travaillé à l'instant [now], pauses déduites.
  Duration worked(DateTime now) {
    final end = endedAt ?? now;
    final ongoingPause = currentPauseStartedAt == null
        ? Duration.zero
        : now.difference(currentPauseStartedAt!);
    return end.difference(startedAt) -
        Duration(seconds: pausedSeconds) -
        ongoingPause;
  }

  factory WorkDay.fromJson(Map<String, dynamic> json) {
    final pauses = (json['pauses'] as List? ?? []).cast<Map<String, dynamic>>();
    final open = pauses.where((p) => p['endedAt'] == null).toList();
    var closedSeconds = 0;
    for (final p in pauses.where((p) => p['endedAt'] != null)) {
      closedSeconds += _date(
        p['endedAt'],
      )!.difference(_date(p['startedAt'])!).inSeconds;
    }
    return WorkDay(
      id: json['id'] as String,
      status: DayStatus.values.byName(json['status'] as String),
      zoneId: json['zoneId'] as String?,
      startedAt: _date(json['startedAt'])!,
      endedAt: _date(json['endedAt']),
      pausedSeconds: closedSeconds,
      currentPauseStartedAt: open.isEmpty
          ? null
          : _date(open.first['startedAt']),
    );
  }
}

/// État de l'agent : journée ouverte, zone approuvée, demande en attente.
class DayState {
  DayState({this.day, this.approved, this.pending});

  final WorkDay? day;
  final ZoneRequest? approved;
  final ZoneRequest? pending;

  bool get isWorking => day != null && day!.status != DayStatus.ended;

  factory DayState.fromJson(Map<String, dynamic> json) => DayState(
    day: json['day'] == null
        ? null
        : WorkDay.fromJson(json['day'] as Map<String, dynamic>),
    approved: json['approved'] == null
        ? null
        : ZoneRequest.fromJson(json['approved'] as Map<String, dynamic>),
    pending: json['pending'] == null
        ? null
        : ZoneRequest.fromJson(json['pending'] as Map<String, dynamic>),
  );
}

enum FieldType { text, number, boolean, date, select }

class MissionField {
  MissionField({
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    this.options = const [],
  });

  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final List<String> options;

  factory MissionField.fromJson(Map<String, dynamic> json) => MissionField(
    key: json['key'] as String,
    label: json['label'] as String,
    type: FieldType.values.byName(json['type'] as String),
    required: json['required'] as bool,
    options: (json['options'] as List?)?.cast<String>() ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'type': type.name,
    'required': required,
    'options': options,
  };
}

class Progress {
  const Progress({
    required this.current,
    required this.target,
    required this.percent,
  });

  final double current;
  final double target;
  final int percent;

  factory Progress.fromJson(Map<String, dynamic> json) => Progress(
    current: _num(json['current']),
    target: _num(json['target']),
    percent: (json['percent'] as num).round(),
  );
}

class Mission {
  Mission({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.progressMethod,
    required this.dueDate,
    required this.progress,
    required this.forGroup,
    this.typeName,
    this.fields = const [],
    this.sumFieldKey,
    this.contributions = const [],
    this.myContribution,
    this.typeId,
    this.isActive = true,
    this.targetValue,
    this.assigneeAgentId,
    this.assigneeGroupId,
    this.hasOwnPay = false,
    this.earnings,
    this.myForms,
    this.zones = const [],
  });

  /// Zones où la mission se fait.
  final List<({String id, String name})> zones;

  final String? typeId;

  /// Agent : formulaires qu'il a envoyés sur cette mission (liste des missions).
  final int? myForms;

  /// Rémunération propre à la mission (fixée par l'administrateur).
  final bool hasOwnPay;

  /// Agent : ce que rapporte la mission (formule Entreprise), sinon null.
  final MissionEarnings? earnings;

  /// Désactivée : plus proposée aux agents (le chef peut la réactiver).
  final bool isActive;
  final double? targetValue;
  final String? assigneeAgentId;
  final String? assigneeGroupId;

  final String id;
  final String title;
  final String? description;
  final MissionStatus status;
  final String progressMethod;
  final DateTime? dueDate;
  final Progress progress;
  final bool forGroup;
  final String? typeName;
  final List<MissionField> fields;
  final String? sumFieldKey;

  /// Chef : contribution de chaque agent du groupe.
  final List<Contribution> contributions;

  /// Agent, mission de groupe : sa propre contribution (jamais celle des collègues).
  final double? myContribution;

  bool get isOpen =>
      status != MissionStatus.failed &&
      (dueDate == null || dueDate!.isAfter(DateTime.now()));

  factory Mission.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as Map<String, dynamic>?;
    return Mission(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: _enum(MissionStatus.values, json['status'] as String, {
        'in_progress': MissionStatus.inProgress,
      }),
      progressMethod: json['progressMethod'] as String,
      dueDate: _date(json['dueDate']),
      progress: Progress.fromJson(json['progress'] as Map<String, dynamic>),
      forGroup: json['assigneeGroupId'] != null,
      typeName: type?['name'] as String?,
      fields: (type?['fields'] as List? ?? [])
          .map((f) => MissionField.fromJson(f as Map<String, dynamic>))
          .toList(),
      sumFieldKey: json['sumFieldKey'] as String?,
      contributions: (json['contributions'] as List? ?? [])
          .map((c) => Contribution.fromJson(c as Map<String, dynamic>))
          .toList(),
      myContribution: (json['myContribution'] as num?)?.toDouble(),
      typeId: json['typeId'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      targetValue: (json['targetValue'] as num?)?.toDouble(),
      assigneeAgentId: json['assigneeAgentId'] as String?,
      assigneeGroupId: json['assigneeGroupId'] as String?,
      hasOwnPay: json['hasOwnPay'] as bool? ?? false,
      myForms: (json['myForms'] as num?)?.toInt(),
      zones: [
        for (final z in json['zones'] as List? ?? const [])
          (id: (z as Map)['id'] as String, name: z['name'] as String),
      ],
      earnings: json['myEarnings'] == null
          ? null
          : MissionEarnings.fromJson(
              json['myEarnings'] as Map<String, dynamic>,
            ),
    );
  }
}

/// Ce que rapporte une mission à l'agent : ses conditions propres, ou la grille de l'agent.
class MissionEarnings {
  const MissionEarnings({
    required this.source,
    required this.perForm,
    required this.commissionPercent,
    required this.tiers,
  });

  /// D'où viennent les conditions : mission, type ou grid (grille de l'agent).
  final String source;
  final int? perForm;
  final double? commissionPercent;

  /// Paliers de prime d'objectif, du plus haut au plus bas.
  final List<({int threshold, int amount})> tiers;

  bool get isEmpty =>
      (perForm ?? 0) == 0 && (commissionPercent ?? 0) == 0 && tiers.isEmpty;

  /// Résumé d'une ligne : « 500 FCFA par formulaire · prime jusqu'à 10 000 FCFA ».
  String? get summary {
    if (isEmpty) return null;
    final parts = [
      if ((perForm ?? 0) > 0) '${formatMoney(perForm!)} par formulaire',
      if ((commissionPercent ?? 0) > 0)
        '${formatNumber(commissionPercent!)} % de commission',
      if (tiers.isNotEmpty) 'prime jusqu’à ${formatMoney(tiers.first.amount)}',
    ];
    final text = parts.join(' · ');
    return text[0].toUpperCase() + text.substring(1);
  }

  factory MissionEarnings.fromJson(Map<String, dynamic> json) =>
      MissionEarnings(
        source: json['source'] as String? ?? 'grid',
        perForm: (json['perForm'] as num?)?.round(),
        commissionPercent: (json['commissionPercent'] as num?)?.toDouble(),
        tiers: [
          for (final t in json['objectiveBonus'] as List? ?? const [])
            (
              threshold: ((t as Map)['thresholdPercent'] as num).round(),
              amount: (t['amount'] as num).round(),
            ),
        ]..sort((a, b) => b.threshold.compareTo(a.threshold)),
      );
}

/// Type de mission : son formulaire (champs) sert aux agents sur le terrain.
class MissionType {
  MissionType({required this.id, required this.name, required this.fields});

  final String id;
  final String name;
  final List<MissionField> fields;

  /// Champs numériques : une mission peut en additionner un (méthode « somme »).
  List<MissionField> get numberFields =>
      fields.where((f) => f.type == FieldType.number).toList();

  factory MissionType.fromJson(Map<String, dynamic> json) => MissionType(
    id: json['id'] as String,
    name: json['name'] as String,
    fields: (json['fields'] as List? ?? [])
        .map((f) => MissionField.fromJson(f as Map<String, dynamic>))
        .toList(),
  );
}

/// Groupe dirigé par le chef d'équipe.
class TeamGroup {
  TeamGroup({required this.id, required this.name});

  final String id;
  final String name;

  factory TeamGroup.fromJson(Map<String, dynamic> json) =>
      TeamGroup(id: json['id'] as String, name: json['name'] as String);
}

class Submission {
  Submission({
    required this.id,
    required this.submittedAt,
    required this.rejected,
    required this.rejectedReason,
    required this.data,
    this.agentName,
    this.agentId,
  });

  final String id;
  final String? agentId;
  final DateTime submittedAt;
  final bool rejected;
  final String? rejectedReason;
  final Map<String, dynamic> data;

  /// Auteur (renseigné pour le chef d'équipe, qui voit les formulaires de ses agents).
  final String? agentName;

  factory Submission.fromJson(Map<String, dynamic> json) {
    final agent = json['agent'] as Map<String, dynamic>?;
    return Submission(
      id: json['id'] as String,
      submittedAt: _date(json['submittedAt'])!,
      rejected: json['status'] == 'rejected',
      rejectedReason: json['rejectedReason'] as String?,
      data: (json['data'] as Map).cast<String, dynamic>(),
      agentName: agent == null
          ? null
          : '${agent['firstName']} ${agent['lastName']}',
      agentId: agent?['id'] as String? ?? json['agentId'] as String?,
    );
  }
}

/// Contribution d'un agent à une mission de groupe (RG-38).
class Contribution {
  Contribution({required this.name, required this.value, this.agentId});

  final String? agentId;
  final String name;
  final double value;

  factory Contribution.fromJson(Map<String, dynamic> json) => Contribution(
    agentId: json['agentId'] as String?,
    name: '${json['firstName']} ${json['lastName']}',
    value: _num(json['value']),
  );
}

enum SubmissionPeriod {
  all('Toute la période'),
  today('Aujourd’hui'),
  week('7 derniers jours'),
  month('30 derniers jours');

  const SubmissionPeriod(this.label);
  final String label;

  /// Début de la période (minuit, heure du téléphone), ou null pour tout.
  DateTime? start(DateTime now) {
    final midnight = DateTime(now.year, now.month, now.day);
    return switch (this) {
      SubmissionPeriod.all => null,
      SubmissionPeriod.today => midnight,
      SubmissionPeriod.week => midnight.subtract(const Duration(days: 6)),
      SubmissionPeriod.month => midnight.subtract(const Duration(days: 29)),
    };
  }
}

/// Filtres des formulaires reçus par le chef d'équipe.
class SubmissionFilter {
  const SubmissionFilter({
    this.agentId,
    this.agentName,
    this.rejected,
    this.period = SubmissionPeriod.all,
  });

  final String? agentId;
  final String? agentName;

  /// null : tous ; true : rejetés ; false : valides.
  final bool? rejected;
  final SubmissionPeriod period;

  bool get isActive =>
      agentId != null || rejected != null || period != SubmissionPeriod.all;

  SubmissionFilter withAgent(String? id, String? name) => SubmissionFilter(
    agentId: id,
    agentName: name,
    rejected: rejected,
    period: period,
  );

  SubmissionFilter withStatus(bool? value) => SubmissionFilter(
    agentId: agentId,
    agentName: agentName,
    rejected: value,
    period: period,
  );

  SubmissionFilter withPeriod(SubmissionPeriod value) => SubmissionFilter(
    agentId: agentId,
    agentName: agentName,
    rejected: rejected,
    period: value,
  );

  Map<String, dynamic> query(DateTime now) => {
    if (agentId != null) 'agentId': agentId,
    if (rejected != null) 'status': rejected! ? 'rejected' : 'accepted',
    if (period.start(now) case final from?)
      'from': from.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is SubmissionFilter &&
      other.agentId == agentId &&
      other.rejected == rejected &&
      other.period == period;

  @override
  int get hashCode => Object.hash(agentId, rejected, period);
}

// ---------------------------------------------------------------------------
// Chef d'équipe

/// Agent du périmètre du chef d'équipe.
class TeamMember {
  TeamMember({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.isActive,
    this.groupId,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? phone;
  final bool isActive;
  final String? groupId;

  String get fullName => '$firstName $lastName';
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
          .toUpperCase();

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
    id: json['id'] as String,
    firstName: json['firstName'] as String,
    lastName: json['lastName'] as String,
    phone: json['phone'] as String?,
    isActive: json['isActive'] as bool? ?? true,
    groupId: json['groupId'] as String?,
  );
}

/// Agent en journée, avec sa dernière position (carte en temps réel).
class LiveAgent {
  LiveAgent({
    required this.dayId,
    required this.position,
    required this.agentId,
    required this.name,
    required this.status,
    required this.zoneId,
    required this.startedAt,
    required this.lastPositionAt,
    required this.batteryLevel,
    required this.outsideZone,
    required this.isMocked,
    required this.signalLost,
    this.outsideSince,
    this.outsideMaxMeters,
    this.alerts = const [],
  });

  final String dayId;

  /// Alertes en cours sur l'agent (immobile, low_battery…), du centre d'alertes.
  final List<String> alerts;

  /// Dernière position connue (absente si l'agent n'a encore rien envoyé).
  final LatLng? position;
  final String agentId;
  final String name;
  final DayStatus status;
  final String? zoneId;
  final DateTime startedAt;
  final DateTime? lastPositionAt;
  final double? batteryLevel;
  final bool outsideZone;
  final bool isMocked;
  final bool signalLost;

  /// Sortie de zone en cours : depuis quand, et distance maximale (marge de la structure comprise).
  final DateTime? outsideSince;
  final int? outsideMaxMeters;

  bool get hasAlert =>
      signalLost || outsideZone || isMocked || alerts.isNotEmpty;

  factory LiveAgent.fromJson(Map<String, dynamic> json) {
    final agent = json['agent'] as Map<String, dynamic>;
    final position = json['position'] as Map<String, dynamic>?;
    final exit = json['zoneExit'] as Map<String, dynamic>?;
    return LiveAgent(
      dayId: json['dayId'] as String,
      position: position?['lat'] == null
          ? null
          : LatLng(_num(position!['lat']), _num(position['lng'])),
      agentId: agent['id'] as String,
      name: '${agent['firstName']} ${agent['lastName']}',
      status: DayStatus.values.byName(json['status'] as String),
      zoneId: json['zoneId'] as String?,
      startedAt: _date(json['startedAt'])!,
      lastPositionAt: _date(position?['recordedAt']),
      batteryLevel: (position?['batteryLevel'] as num?)?.toDouble(),
      // « Hors zone » : la sortie suivie par le serveur, avec la marge de la structure.
      outsideZone: json.containsKey('zoneExit')
          ? exit != null
          : position?['outsideZone'] as bool? ?? false,
      isMocked: position?['isMocked'] as bool? ?? false,
      signalLost: json['signalLost'] as bool? ?? false,
      outsideSince: _date(exit?['exitedAt']),
      outsideMaxMeters: (exit?['maxDistanceM'] as num?)?.round(),
      alerts: [
        for (final t in json['alerts'] as List? ?? const []) t as String,
      ],
    );
  }
}

/// Bilan d'une journée de l'équipe : résumé et une ligne par agent.
class DailyReport {
  const DailyReport({
    required this.date,
    required this.agents,
    required this.worked,
    required this.notStarted,
    required this.late,
    required this.workedMinutes,
    required this.formsAccepted,
    required this.formsRejected,
    required this.zoneExits,
    required this.alerts,
    required this.autoClosed,
    required this.rows,
  });

  final DateTime date;
  final int agents;
  final int worked;
  final int notStarted;
  final int late;
  final int workedMinutes;
  final int formsAccepted;
  final int formsRejected;
  final int zoneExits;
  final int alerts;
  final int autoClosed;
  final List<DailyReportRow> rows;

  factory DailyReport.fromJson(Map<String, dynamic> json) {
    final s = json['summary'] as Map<String, dynamic>;
    int n(String k) => (s[k] as num?)?.toInt() ?? 0;
    return DailyReport(
      date: DateTime.parse(json['date'] as String),
      agents: n('agents'),
      worked: n('worked'),
      notStarted: n('notStarted'),
      late: n('late'),
      workedMinutes: n('workedMinutes'),
      formsAccepted: n('formsAccepted'),
      formsRejected: n('formsRejected'),
      zoneExits: n('zoneExits'),
      alerts: n('alerts'),
      autoClosed: n('autoClosed'),
      rows: [
        for (final r in json['agents'] as List)
          DailyReportRow.fromJson(r as Map<String, dynamic>),
      ],
    );
  }
}

class DailyReportRow {
  const DailyReportRow({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.zone,
    required this.startedAt,
    required this.endedAt,
    required this.workedMinutes,
    required this.formsAccepted,
    required this.formsRejected,
    required this.zoneExits,
    required this.alerts,
    required this.late,
    this.targetMinutes,
  });

  /// Durée de travail attendue de l'agent, en minutes.
  final int? targetMinutes;

  final String id;
  final String name;
  final String? phone;

  /// not_started, working, ended, auto
  final String status;
  final String? zone;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int workedMinutes;
  final int formsAccepted;
  final int formsRejected;
  final int zoneExits;
  final List<String> alerts;
  final bool late;

  bool get started => status != 'not_started';

  factory DailyReportRow.fromJson(Map<String, dynamic> json) => DailyReportRow(
    id: json['id'] as String,
    name: '${json['firstName']} ${json['lastName']}',
    phone: json['phone'] as String?,
    status: json['status'] as String,
    zone: json['zone'] as String?,
    startedAt: _date(json['startedAt']),
    endedAt: _date(json['endedAt']),
    workedMinutes: (json['workedMinutes'] as num?)?.toInt() ?? 0,
    targetMinutes: (json['targetMinutes'] as num?)?.toInt(),
    formsAccepted: (json['formsAccepted'] as num?)?.toInt() ?? 0,
    formsRejected: (json['formsRejected'] as num?)?.toInt() ?? 0,
    zoneExits: (json['zoneExits'] as num?)?.toInt() ?? 0,
    alerts: [for (final a in json['alerts'] as List? ?? const []) a as String],
    late: json['late'] as bool? ?? false,
  );
}

/// Alerte du centre d'alertes du chef : se referme d'elle-même quand la situation se règle.
class AgentAlert {
  const AgentAlert({
    required this.id,
    required this.type,
    required this.agentId,
    required this.agentName,
    required this.dayId,
    required this.startedAt,
    required this.resolvedAt,
    required this.data,
    required this.acknowledgedAt,
    required this.acknowledgedBy,
    required this.note,
  });

  final String id;

  /// signal_lost, immobile, low_battery, mocked, out_of_zone, late_start
  final String type;
  final String agentId;
  final String agentName;
  final String? dayId;
  final DateTime startedAt;
  final DateTime? resolvedAt;
  final Map<String, dynamic> data;
  final DateTime? acknowledgedAt;

  /// Responsable qui s'en occupe (prénom et nom).
  final String? acknowledgedBy;
  final String? note;

  bool get isOpen => resolvedAt == null;

  factory AgentAlert.fromJson(Map<String, dynamic> json) {
    final agent = json['agent'] as Map<String, dynamic>;
    final ack = json['acknowledgedBy'] as Map<String, dynamic>?;
    return AgentAlert(
      id: json['id'] as String,
      type: json['type'] as String,
      agentId: agent['id'] as String,
      agentName: '${agent['firstName']} ${agent['lastName']}',
      dayId: json['dayId'] as String?,
      startedAt: _date(json['startedAt'])!,
      resolvedAt: _date(json['resolvedAt']),
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      acknowledgedAt: _date(json['acknowledgedAt']),
      acknowledgedBy: ack == null
          ? null
          : '${ack['firstName']} ${ack['lastName']}',
      note: json['note'] as String?,
    );
  }
}

/// Demande de zone à valider par le chef d'équipe.
class PendingRequest {
  PendingRequest({
    required this.id,
    required this.agentName,
    required this.agentPhone,
    required this.zoneName,
    required this.isChange,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String agentName;
  final String? agentPhone;
  final String zoneName;
  final bool isChange;
  final DateTime createdAt;
  final DateTime? expiresAt;

  factory PendingRequest.fromJson(Map<String, dynamic> json) {
    final agent = json['agent'] as Map<String, dynamic>;
    return PendingRequest(
      id: json['id'] as String,
      agentName: '${agent['firstName']} ${agent['lastName']}',
      agentPhone: agent['phone'] as String?,
      zoneName: (json['zone'] as Map<String, dynamic>)['name'] as String,
      isChange: json['isChange'] as bool? ?? false,
      createdAt: _date(json['createdAt'])!,
      expiresAt: _date(json['expiresAt']),
    );
  }
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String title;
  final String? body;
  final DateTime createdAt;
  final bool read;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String?,
        createdAt: _date(json['createdAt'])!,
        read: json['readAt'] != null,
      );
}

// ---------------------------------------------------------------------------
// Rémunération : calculée par la plateforme, payée par la structure hors de l'app.

int _int(Object? v) => (v as num?)?.round() ?? 0;

/// Élément de gains : fixe, journées, formulaires, primes, retenues…
class PayItem {
  const PayItem({
    required this.label,
    required this.amount,
    this.quantity,
    this.unitAmount,
  });

  final String label;
  final int amount;
  final num? quantity;
  final int? unitAmount;

  bool get isDeduction => amount < 0;

  factory PayItem.fromJson(Map<String, dynamic> json) => PayItem(
    label: json['label'] as String,
    amount: _int(json['amount']),
    quantity: json['quantity'] as num?,
    unitAmount: (json['unitAmount'] as num?)?.round(),
  );
}

List<PayItem> _items(Object? raw) => [
  for (final i in (raw as List?) ?? const [])
    PayItem.fromJson(i as Map<String, dynamic>),
];

/// Estimation d'une personne sur la période en cours.
class PayEstimate {
  const PayEstimate({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.gridName,
    required this.items,
    required this.gross,
  });

  final String userId;
  final String firstName;
  final String lastName;
  final String role;

  /// Null : aucune grille attribuée, donc aucun gain calculé.
  final String? gridName;
  final List<PayItem> items;
  final int gross;

  String get fullName => '$firstName $lastName';
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
          .toUpperCase();

  factory PayEstimate.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return PayEstimate(
      userId: user['id'] as String,
      firstName: user['firstName'] as String,
      lastName: user['lastName'] as String,
      role: user['role'] as String,
      gridName: json['gridName'] as String?,
      items: _items(json['items']),
      gross: _int(json['gross']),
    );
  }
}

/// Période de paie (dates au format AAAA-MM-JJ, dans le fuseau de la structure).
class PayPeriod {
  const PayPeriod({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;

  /// Avancement de la période, de 0 à 1.
  double progress(DateTime now) {
    final days = end.difference(start).inDays + 1;
    final elapsed =
        DateTime(now.year, now.month, now.day).difference(start).inDays + 1;
    return (elapsed / days).clamp(0.0, 1.0);
  }

  int get days => end.difference(start).inDays + 1;
}

/// Période en cours : estimation recalculée à chaque ouverture.
class CurrentPay {
  const CurrentPay({
    required this.period,
    required this.currency,
    required this.lines,
    required this.total,
  });

  final PayPeriod period;
  final String currency;
  final List<PayEstimate> lines;
  final int total;

  factory CurrentPay.fromJson(Map<String, dynamic> json) {
    final line = json['line'];
    return CurrentPay(
      period: PayPeriod(
        label: json['label'] as String,
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
      ),
      currency: json['currency'] as String? ?? 'XOF',
      lines: json['lines'] is List
          ? [
              for (final l in json['lines'] as List)
                PayEstimate.fromJson(l as Map<String, dynamic>),
            ]
          : [if (line is Map<String, dynamic>) PayEstimate.fromJson(line)],
      total: _int(json['total']),
    );
  }
}

/// Paie validée par la structure : reçu de la personne.
class PayReceipt {
  const PayReceipt({
    required this.runId,
    required this.period,
    required this.items,
    required this.gross,
    required this.adjustments,
    required this.total,
    required this.adjustmentDetails,
    this.paidAt,
    this.paymentReference,
  });

  final String runId;
  final PayPeriod period;
  final List<PayItem> items;
  final int gross;
  final int adjustments;
  final int total;
  final List<PayItem> adjustmentDetails;
  final DateTime? paidAt;
  final String? paymentReference;

  bool get isPaid => paidAt != null;

  factory PayReceipt.fromJson(Map<String, dynamic> json) => PayReceipt(
    runId: json['runId'] as String,
    period: PayPeriod(
      label: json['label'] as String,
      start: DateTime.parse(json['periodStart'] as String),
      end: DateTime.parse(json['periodEnd'] as String),
    ),
    items: _items(json['items']),
    gross: _int(json['gross']),
    adjustments: _int(json['adjustments']),
    total: _int(json['total']),
    adjustmentDetails: [
      for (final a in (json['adjustmentsDetail'] as List?) ?? const [])
        PayItem(
          label: (a as Map<String, dynamic>)['reason'] as String,
          amount: _int(a['amount']),
        ),
    ],
    paidAt: json['paidAt'] == null
        ? null
        : DateTime.parse(json['paidAt'] as String).toLocal(),
    paymentReference: json['paymentReference'] as String?,
  );
}

/// Mes gains : estimation en direct et paies validées.
class MyPay {
  const MyPay({required this.current, required this.history});

  final CurrentPay current;
  final List<PayReceipt> history;

  PayEstimate? get estimate => current.lines.firstOrNull;

  factory MyPay.fromJson(Map<String, dynamic> json) => MyPay(
    current: CurrentPay.fromJson(json['current'] as Map<String, dynamic>),
    history: [
      for (final h in (json['history'] as List?) ?? const [])
        PayReceipt.fromJson(h as Map<String, dynamic>),
    ],
  );
}

/// Paie d'une période terminée (brouillon : le chef peut proposer des ajustements).
class PayRunSummary {
  const PayRunSummary({
    required this.id,
    required this.label,
    required this.status,
  });

  final String id;
  final String label;
  final String status;

  bool get isDraft => status == 'draft';

  factory PayRunSummary.fromJson(Map<String, dynamic> json) => PayRunSummary(
    id: json['id'] as String,
    label: json['label'] as String,
    status: json['status'] as String,
  );
}

/// Ajustement d'une paie : proposé par le chef, décidé par l'administrateur.
class PayAdjustmentInfo {
  const PayAdjustmentInfo({
    required this.id,
    required this.userId,
    required this.amount,
    required this.reason,
    required this.status,
  });

  final String id;
  final String userId;
  final int amount;
  final String reason;

  /// proposed, approved, rejected
  final String status;

  factory PayAdjustmentInfo.fromJson(Map<String, dynamic> json) =>
      PayAdjustmentInfo(
        id: json['id'] as String,
        userId: json['userId'] as String,
        amount: _int(json['amount']),
        reason: json['reason'] as String,
        status: json['status'] as String,
      );
}

/// Paie d'une période, vue par le chef : lignes de son équipe et ajustements.
class PayRunDetail {
  const PayRunDetail({
    required this.id,
    required this.label,
    required this.status,
    required this.currency,
    required this.lines,
    required this.adjustments,
  });

  final String id;
  final String label;
  final String status;
  final String currency;
  final List<({String userId, String name, int total})> lines;
  final List<PayAdjustmentInfo> adjustments;

  bool get isDraft => status == 'draft';

  factory PayRunDetail.fromJson(Map<String, dynamic> json) => PayRunDetail(
    id: json['id'] as String,
    label: json['label'] as String,
    status: json['status'] as String,
    currency: json['currency'] as String? ?? 'XOF',
    lines: [
      for (final l
          in (json['lines'] as List? ?? []).cast<Map<String, dynamic>>())
        (
          userId: l['userId'] as String,
          name: '${l['firstName']} ${l['lastName']}',
          total: _int(l['total']),
        ),
    ],
    adjustments: [
      for (final a in (json['adjustments'] as List? ?? []))
        PayAdjustmentInfo.fromJson(a as Map<String, dynamic>),
    ],
  );
}

/// Chef d'équipe à contacter depuis l'app de l'agent.
class TeamLeadContact {
  const TeamLeadContact({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.phone,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? phone;

  String get fullName => '$firstName $lastName'.trim();
  String get initials =>
      '${firstName.isEmpty ? '' : firstName[0]}${lastName.isEmpty ? '' : lastName[0]}'
          .toUpperCase();

  factory TeamLeadContact.fromJson(Map<String, dynamic> j) => TeamLeadContact(
    id: j['id'] as String,
    firstName: j['firstName'] as String? ?? '',
    lastName: j['lastName'] as String? ?? '',
    phone: j['phone'] as String?,
  );
}

/// Équipe de l'agent : groupe, chef(s) et zones qu'il peut choisir.
class AgentTeam {
  const AgentTeam({
    required this.usesGroups,
    required this.groupMissing,
    required this.leads,
    required this.zones,
    this.groupId,
    this.groupName,
    this.members = 0,
  });

  final bool usesGroups;

  /// Groupes utilisés mais agent rattaché à aucun : aucune zone possible.
  final bool groupMissing;
  final String? groupId;
  final String? groupName;
  final int members;
  final List<TeamLeadContact> leads;
  final List<({String id, String name, int? capacity})> zones;

  factory AgentTeam.fromJson(Map<String, dynamic> j) {
    final group = j['group'] as Map<String, dynamic>?;
    return AgentTeam(
      usesGroups: j['usesGroups'] as bool? ?? false,
      groupMissing: j['groupMissing'] as bool? ?? false,
      groupId: group?['id'] as String?,
      groupName: group?['name'] as String?,
      members: (group?['members'] as num?)?.toInt() ?? 0,
      leads: (j['leads'] as List? ?? [])
          .map((l) => TeamLeadContact.fromJson(l as Map<String, dynamic>))
          .toList(),
      zones: (j['zones'] as List? ?? []).map((z) {
        final m = z as Map<String, dynamic>;
        return (
          id: m['id'] as String,
          name: m['name'] as String,
          capacity: (m['capacity'] as num?)?.toInt(),
        );
      }).toList(),
    );
  }
}

/// Mission présentée au choix de la zone : de quoi décider avant de démarrer la journée.
class ZoneMission {
  const ZoneMission({
    required this.id,
    required this.title,
    required this.typeName,
    required this.fields,
    required this.progressMethod,
    required this.targetValue,
    required this.assignment,
    required this.progress,
    this.description,
    this.dueDate,
    this.myForms = 0,
    this.earnings,
  });

  final String id;
  final String title;
  final String? description;
  final String typeName;

  /// Champs du formulaire à remplir (libellés).
  final List<String> fields;
  final String progressMethod;
  final double targetValue;
  final DateTime? dueDate;

  /// Pour lui (agent), pour son groupe (group) ou ouverte à tous (open).
  final String assignment;
  final Progress progress;
  final int myForms;
  final MissionEarnings? earnings;

  String get assignmentLabel => switch (assignment) {
    'agent' => 'Pour vous',
    'group' => 'Votre groupe',
    _ => 'Ouverte à tous',
  };

  factory ZoneMission.fromJson(Map<String, dynamic> j) => ZoneMission(
    id: j['id'] as String,
    title: j['title'] as String,
    description: j['description'] as String?,
    typeName: j['typeName'] as String? ?? '',
    fields: (j['fields'] as List? ?? const []).cast<String>(),
    progressMethod: j['progressMethod'] as String,
    targetValue: (j['targetValue'] as num).toDouble(),
    dueDate: _date(j['dueDate']),
    assignment: j['assignment'] as String? ?? 'open',
    progress: Progress.fromJson(j['progress'] as Map<String, dynamic>),
    myForms: (j['myForms'] as num?)?.toInt() ?? 0,
    earnings: j['myEarnings'] == null
        ? null
        : MissionEarnings.fromJson(j['myEarnings'] as Map<String, dynamic>),
  );
}
