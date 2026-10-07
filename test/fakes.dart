import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:suivi_agent/app.dart';
import 'package:suivi_agent/core/api_client.dart';
import 'package:suivi_agent/core/branding.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/models.dart';
import 'package:suivi_agent/core/providers.dart';
import 'package:suivi_agent/core/repository.dart';
import 'package:suivi_agent/core/session.dart';
import 'package:suivi_agent/core/sync.dart';
import 'package:suivi_agent/core/tracking.dart';
import 'package:suivi_agent/core/zone_guard.dart';
import 'package:suivi_agent/features/team/team_map_screen.dart';
import 'package:suivi_agent/features/onboarding/onboarding_data.dart';
import 'package:geolocator/geolocator.dart';

Me fakeMe({
  String role = 'agent',
  String first = 'Koffi',
  String subscriptionStatus = 'active',
  Set<String>? features,
  int workdayMinutes = 480,
  bool submissionRequiresDay = true,
}) => Me(
  workdayMinutes: workdayMinutes,
  submissionRequiresDay: submissionRequiresDay,
  subscriptionStatus: subscriptionStatus,
  features:
      features ??
      const {
        'groups',
        'manual_approval',
        'missions',
        'branding',
        'exports',
        'stats',
        'team_leads',
        'audit',
      },
  id: 'u1',
  firstName: first,
  lastName: 'Brou',
  email: 'agent@demo.ci',
  role: role,
  tenantName: 'Démo Abidjan',
  trackDuringPause: false,
  allowZoneChangeBeforeStart: true,
  zoneRequired: true,
);

const fakeBranding = Branding(
  displayName: 'Démo Abidjan',
  primary: Color(0xFF0F766E),
  onPrimary: Colors.white,
  welcomeMessage: 'Bonne journée sur le terrain !',
);

/// API simulée : aucune requête réseau dans les tests.
class FakeRepository extends Repository {
  FakeRepository() : super(ApiClient(SessionStore()));

  Object? loginError;
  DayState day = DayState();
  final positions = <List<Map<String, dynamic>>>[];
  ApiException? positionsError;

  @override
  Future<Map<String, dynamic>> login(String phone, String password) async {
    if (loginError != null) throw loginError!;
    return {'accessToken': 'a', 'refreshToken': 'r'};
  }

  @override
  Future<DayState> currentDay() async => day;

  /// Profil renvoyé par /auth/me (formule changée par l'éditeur, par exemple).
  Map<String, dynamic>? meResponse;

  @override
  Future<Map<String, dynamic>> meJson() async =>
      meResponse ?? (throw ApiException('Pas de connexion.'));

  /// Bilan du jour ; messages à l'équipe enregistrés pour vérification.
  final teamMessages = <(String, List<String>?)>[];
  final reportDays = <DateTime?>[];

  @override
  Future<DailyReport> dailyReport({DateTime? date}) async {
    reportDays.add(date);
    final today = DateTime.now();
    DateTime at(int h, int m) =>
        DateTime(today.year, today.month, today.day, h, m);
    Map<String, dynamic> row(
      String id,
      String first,
      String last,
      String status, {
      DateTime? start,
      DateTime? end,
      int worked = 0,
      int forms = 0,
      int exits = 0,
      List<String> alerts = const [],
      bool late = false,
    }) => {
      'id': id,
      'firstName': first,
      'lastName': last,
      'phone': '+2250702020201',
      'group': 'Équipe Nord',
      'status': status,
      'zone': status == 'not_started' ? null : 'Plateau',
      'startedAt': start?.toUtc().toIso8601String(),
      'endedAt': end?.toUtc().toIso8601String(),
      'workedMinutes': worked,
      'pausesMinutes': 30,
      'formsAccepted': forms,
      'formsRejected': 0,
      'zoneExits': exits,
      'outsideMinutes': exits * 12,
      'alerts': alerts,
      'late': late,
    };
    return DailyReport.fromJson({
      'date':
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      'summary': {
        'agents': 3,
        'worked': 2,
        'notStarted': 1,
        'late': 1,
        'workedMinutes': 790,
        'formsAccepted': 21,
        'formsRejected': 1,
        'zoneExits': 1,
        'alerts': 2,
        'autoClosed': 0,
      },
      'agents': [
        row('a3', 'Serge', 'Gbagbo', 'not_started'),
        row(
          'a4',
          'Koffi',
          'Brou',
          'ended',
          start: at(8, 2),
          end: at(17, 31),
          worked: 509,
          forms: 14,
        ),
        row(
          'a2',
          'Aminata',
          'Diallo',
          'working',
          start: at(8, 47),
          worked: 281,
          forms: 7,
          exits: 1,
          alerts: ['out_of_zone', 'low_battery'],
          late: true,
        ),
      ],
    });
  }

  @override
  Future<int> sendTeamMessage(String body, {List<String>? agentIds}) async {
    teamMessages.add((body, agentIds));
    return agentIds?.length ?? 3;
  }

  /// Centre d'alertes du chef ; prises en charge enregistrées pour vérification.
  final acknowledged = <(String, String?)>[];

  Map<String, dynamic> _alert(
    String id,
    String type,
    String agentId,
    String first,
    String last,
    Duration since,
    Map<String, dynamic> data, {
    Duration? resolvedAfter,
    bool acked = false,
  }) {
    final start = DateTime.now().subtract(since);
    return {
      'id': id,
      'type': type,
      'agent': {'id': agentId, 'firstName': first, 'lastName': last},
      'dayId': type == 'late_start' ? null : 'd-$agentId',
      'startedAt': start.toUtc().toIso8601String(),
      'resolvedAt': resolvedAfter == null
          ? null
          : start.add(resolvedAfter).toUtc().toIso8601String(),
      'data': data,
      'acknowledgedAt': acked
          ? DateTime.now()
                .subtract(const Duration(minutes: 3))
                .toUtc()
                .toIso8601String()
          : null,
      'acknowledgedBy': acked
          ? {'firstName': 'Yao', 'lastName': 'Kouassi'}
          : null,
      'note': acked ? 'Appelé : client en réunion' : null,
    };
  }

  @override
  Future<List<AgentAlert>> alerts({String status = 'open'}) async {
    final open = [
      _alert(
        'al1',
        'out_of_zone',
        'a2',
        'Aminata',
        'Diallo',
        const Duration(minutes: 12),
        {'zoneName': 'Plateau', 'maxDistanceM': 420},
      ),
      _alert(
        'al2',
        'immobile',
        'a4',
        'Koffi',
        'Brou',
        const Duration(minutes: 52),
        {
          'radiusM': 100,
          'since': DateTime.now()
              .subtract(const Duration(minutes: 52))
              .toUtc()
              .toIso8601String(),
        },
        acked: true,
      ),
      _alert(
        'al5',
        'low_battery',
        'a2',
        'Aminata',
        'Diallo',
        const Duration(minutes: 4),
        {'percent': 12},
      ),
      _alert(
        'al3',
        'late_start',
        'a3',
        'Serge',
        'Gbagbo',
        const Duration(minutes: 20),
        {'expectedAt': '08:00'},
      ),
    ];
    final resolved = [
      _alert(
        'al4',
        'low_battery',
        'a5',
        'Jean-Marc',
        'Aka',
        const Duration(hours: 5),
        {'percent': 12},
        resolvedAfter: const Duration(minutes: 40),
      ),
    ];
    return (status == 'open' ? open : resolved)
        .map(AgentAlert.fromJson)
        .where(
          (a) =>
              !acknowledged.any((x) => x.$1 == a.id) ||
              a.acknowledgedAt != null,
        )
        .toList();
  }

  @override
  Future<void> acknowledgeAlert(String id, {String? note}) async =>
      acknowledged.add((id, note));

  // Chef d'équipe : missions et propositions de paie, enregistrées pour vérification.
  final createdMissions = <Map<String, dynamic>>[];
  final missionUpdates = <(String, Map<String, dynamic>)>[];
  final proposals = <(String, int, String)>[];

  @override
  Future<List<MissionType>> missionTypes() async => [
    MissionType.fromJson({
      'id': 't1',
      'name': 'Visite commerciale',
      'fields': [
        {
          'key': 'commerce',
          'label': 'Commerce',
          'type': 'text',
          'required': true,
        },
        {
          'key': 'montant',
          'label': 'Montant',
          'type': 'number',
          'required': false,
        },
      ],
    }),
  ];

  @override
  Future<List<TeamGroup>> leaderGroups() async => [
    TeamGroup(id: 'g1', name: 'Équipe Nord'),
  ];

  @override
  Future<Map<String, dynamic>> createMission(Map<String, dynamic> body) async {
    createdMissions.add(body);
    return {'id': 'm1'};
  }

  @override
  Future<Map<String, dynamic>> updateMission(
    String id,
    Map<String, dynamic> body,
  ) async {
    missionUpdates.add((id, body));
    return {'id': id};
  }

  @override
  Future<void> setMissionResult(String id, {required bool achieved}) async {}

  @override
  Future<void> deleteMission(String id) async {}

  @override
  Future<List<PayRunSummary>> payRuns() async => [
    const PayRunSummary(id: 'r9', label: 'septembre 2026', status: 'draft'),
  ];

  @override
  Future<PayRunDetail> payRun(String id) async => PayRunDetail.fromJson({
    'id': id,
    'label': 'septembre 2026',
    'status': 'draft',
    'currency': 'XOF',
    'lines': [
      {
        'userId': 'a1',
        'firstName': 'Aminata',
        'lastName': 'Diallo',
        'total': 72700,
      },
      {
        'userId': 'a2',
        'firstName': 'Koffi',
        'lastName': 'Brou',
        'total': 67750,
      },
    ],
    'adjustments': [],
  });

  @override
  Future<void> proposeAdjustment(
    String runId, {
    required String userId,
    required int amount,
    required String reason,
  }) async => proposals.add((userId, amount, reason));

  @override
  Future<MyPay> myPay() async => MyPay.fromJson(payJson);

  @override
  Future<CurrentPay> teamPay() async => CurrentPay.fromJson(teamPayJson());

  @override
  Future<AvailableZones> availableZones() async => AvailableZones(
    zones: [
      Zone(
        id: 'z1',
        name: 'Plateau',
        capacity: 3,
        placesLeft: 1,
        isFull: false,
        sensitive: false,
        area: plateauArea,
        missions: const [
          ZoneMission(
            id: 'm1',
            title: '120 visites cette semaine',
            description: 'Présentez la nouvelle offre aux commerces.',
            typeName: 'Visite commerciale',
            fields: ['Nom du commerce', 'Montant'],
            progressMethod: 'count',
            targetValue: 120,
            assignment: 'group',
            progress: Progress(current: 77, target: 120, percent: 64),
            myForms: 3,
            earnings: MissionEarnings(
              source: 'mission',
              perForm: 500,
              commissionPercent: null,
              tiers: [(threshold: 100, amount: 10000)],
            ),
          ),
        ],
      ),
      Zone(
        id: 'z2',
        name: 'Cocody',
        capacity: 4,
        placesLeft: 0,
        isFull: true,
        sensitive: true,
      ),
      Zone(
        id: 'z3',
        name: 'Adjamé',
        capacity: null,
        placesLeft: null,
        isFull: false,
        sensitive: false,
      ),
    ],
    groupMissing: false,
  );

  /// Liste vue par un agent : formulaires envoyés sur chaque mission.
  bool withMyForms = false;

  /// Formulaires envoyés au serveur ; `submitError` simule un refus ou une coupure.
  final submittedForms = <Map<String, dynamic>>[];
  ApiException? submitError;

  @override
  Future<void> submit(String missionId, Map<String, dynamic> body) async {
    if (submitError != null) throw submitError!;
    submittedForms.add({...body, 'missionId': missionId});
  }

  /// Équipe de l'agent (/me/team).
  AgentTeam agentTeam = const AgentTeam(
    usesGroups: true,
    groupMissing: false,
    groupId: 'g1',
    groupName: 'Équipe Nord',
    members: 4,
    leads: [
      TeamLeadContact(
        id: 'l1',
        firstName: 'Yao',
        lastName: 'Kouassi',
        phone: '07 01 01 01 01',
      ),
    ],
    zones: [(id: 'z1', name: 'Plateau', capacity: 5)],
  );

  @override
  Future<AgentTeam> myTeam() async => agentTeam;

  @override
  Future<List<Map<String, dynamic>>> missionsJson() async => [
    for (final m in await _missions())
      {
        ...m,
        if (withMyForms) 'myForms': const {'m1': 3, 'm3': 1}[m['id']] ?? 0,
      },
  ];

  Future<List<Map<String, dynamic>>> _missions() async => [
    {
      'id': 'm1',
      'title': '120 visites cette semaine',
      'status': 'in_progress',
      'progressMethod': 'count',
      'dueDate': DateTime.now()
          .add(const Duration(days: 2))
          .toUtc()
          .toIso8601String(),
      'assigneeGroupId': 'g1',
      'progress': {'current': 77, 'target': 120, 'percent': 64},
    },
    {
      'id': 'm2',
      'title': 'Relance clients Cocody',
      'status': 'todo',
      'progressMethod': 'count',
      'dueDate': DateTime.now()
          .add(const Duration(days: 3))
          .toUtc()
          .toIso8601String(),
      'progress': {'current': 0, 'target': 25, 'percent': 0},
    },
    {
      'id': 'm3',
      'title': 'Lancement Mobile Money',
      'status': 'achieved',
      'progressMethod': 'count',
      'dueDate': null,
      'assigneeGroupId': 'g1',
      'progress': {'current': 64, 'target': 60, 'percent': 100},
    },
  ];

  // Profil : l'API renvoie le profil complet à jour après chaque modification.
  Map<String, dynamic> profile = {
    'id': 'u1',
    'firstName': 'Koffi',
    'lastName': 'Brou',
    'email': 'agent@demo.ci',
    'role': 'agent',
    'phone': '+2250102030405',
    'avatarVersion': null,
  };
  final passwordChanges = <(String, String)>[];

  Map<String, dynamic> get _meJson => {
    'user': profile,
    'tenant': {'name': 'Démo Abidjan'},
    'settings': {
      'trackDuringPause': false,
      'allowZoneChangeBeforeStart': true,
      'zoneRequired': true,
    },
  };

  @override
  Future<Map<String, dynamic>> updateProfile({
    String? firstName,
    String? lastName,
    String? email,
  }) async {
    profile = {
      ...profile,
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (email != null) 'email': email,
    };
    return _meJson;
  }

  @override
  Future<Map<String, dynamic>> changePassword(
    String current,
    String next,
  ) async {
    if (current != 'Password123!') {
      throw ApiException('Identifiants incorrects', status: 401);
    }
    passwordChanges.add((current, next));
    return {
      'accessToken': 'nouveau',
      'refreshToken': 'nouveau',
      'expiresIn': 900,
    };
  }

  @override
  Future<List<int>?> avatarBytes(String userId) async => null;

  @override
  Future<List<AppNotification>> notifications() async => [];

  int markAllReadCalls = 0;

  @override
  Future<void> markAllRead() async => markAllReadCalls++;

  @override
  Future<Map<String, dynamic>> missionJson(String id) async => {
    'id': id,
    'title': '120 visites cette semaine',
    'description':
        'Présentez la nouvelle offre aux commerces de vos zones. Une visite = un formulaire.',
    'status': 'in_progress',
    'progressMethod': 'count',
    'dueDate': DateTime.now()
        .add(const Duration(days: 2))
        .toUtc()
        .toIso8601String(),
    'assigneeGroupId': 'g1',
    'progress': {'current': 77, 'target': 120, 'percent': 64},
    'type': {
      'name': 'Prospection',
      'fields': [
        {
          'key': 'commerce',
          'label': 'Nom du commerce',
          'type': 'text',
          'required': true,
        },
        {
          'key': 'interesse',
          'label': 'Client intéressé',
          'type': 'boolean',
          'required': true,
        },
      ],
    },
    'contributions': [
      {'agentId': 'a4', 'firstName': 'Koffi', 'lastName': 'Brou', 'value': 45},
      {
        'agentId': 'a2',
        'firstName': 'Aminata',
        'lastName': 'Diallo',
        'value': 32,
      },
    ],
    // Vue agent (l'API n'envoie aux agents que leur propre contribution).
    'myContribution': 45,
    // Rémunération propre à la mission (formule Entreprise).
    'hasOwnPay': true,
    'myEarnings': {
      'source': 'mission',
      'perForm': 1000,
      'commissionPercent': null,
      'objectiveBonus': [
        {'thresholdPercent': 80, 'amount': 10000},
        {'thresholdPercent': 100, 'amount': 25000},
      ],
    },
  };

  /// Formulaires reçus sur plusieurs jours, filtrés comme le ferait l'API.
  List<Submission> get allSubmissions {
    // Midi : « il y a une heure » reste aujourd'hui, quelle que soit l'heure du test.
    final today = DateTime.now();
    final now = DateTime(today.year, today.month, today.day, 12);
    Submission make(
      String id,
      String agentId,
      String agentName,
      Duration ago,
      String commerce, {
      String? rejectedReason,
    }) => Submission(
      id: id,
      submittedAt: now.subtract(ago),
      rejected: rejectedReason != null,
      rejectedReason: rejectedReason,
      data: {'commerce': commerce, 'interesse': rejectedReason == null},
      agentId: agentId,
      agentName: agentName,
    );
    return [
      make(
        's1',
        'a4',
        'Koffi Brou',
        const Duration(minutes: 20),
        'Boutique Awa',
      ),
      make(
        's2',
        'a2',
        'Aminata Diallo',
        const Duration(hours: 1),
        'Cave du Port',
      ),
      make(
        's3',
        'a4',
        'Koffi Brou',
        const Duration(days: 1, hours: 1),
        'Pharmacie du Marché',
        rejectedReason: 'Visite en double',
      ),
      make('s4', 'a2', 'Aminata Diallo', const Duration(days: 3), 'Garage Yao'),
      make(
        's5',
        'a4',
        'Koffi Brou',
        const Duration(days: 12),
        'Maquis Chez Tanti',
      ),
    ];
  }

  final submissionQueries = <SubmissionFilter>[];

  @override
  Future<List<Submission>> submissions(
    String missionId, {
    SubmissionFilter filter = const SubmissionFilter(),
  }) async {
    submissionQueries.add(filter);
    final from = filter.period.start(DateTime.now());
    return allSubmissions
        .where((s) => filter.agentId == null || s.agentId == filter.agentId)
        .where((s) => filter.rejected == null || s.rejected == filter.rejected)
        .where((s) => from == null || !s.submittedAt.isBefore(from))
        .toList();
  }

  @override
  Future<List<LiveAgent>> live() async => [
    LiveAgent(
      dayId: 'd2',
      position: const LatLng(5.3290, -4.0100),
      agentId: 'a2',
      name: 'Aminata Diallo',
      status: DayStatus.active,
      zoneId: 'z1',
      startedAt: DateTime.now().subtract(const Duration(hours: 1)),
      lastPositionAt: DateTime.now(),
      batteryLevel: 0.5,
      outsideZone: true,
      isMocked: false,
      signalLost: false,
      outsideSince: DateTime.now().subtract(const Duration(minutes: 12)),
      outsideMaxMeters: 420,
    ),
    LiveAgent(
      dayId: 'd4',
      position: const LatLng(5.3215, -4.0205),
      agentId: 'a4',
      name: 'Koffi Brou',
      status: DayStatus.active,
      zoneId: 'z1',
      startedAt: DateTime.now().subtract(const Duration(hours: 3)),
      lastPositionAt: DateTime.now().subtract(const Duration(minutes: 1)),
      batteryLevel: 0.8,
      outsideZone: false,
      isMocked: false,
      signalLost: false,
    ),
    LiveAgent(
      dayId: 'd5',
      position: const LatLng(5.3555, -3.9850),
      agentId: 'a5',
      name: 'Jean-Marc Aka',
      status: DayStatus.paused,
      zoneId: 'z2',
      startedAt: DateTime.now().subtract(const Duration(hours: 2)),
      lastPositionAt: DateTime.now().subtract(const Duration(minutes: 4)),
      batteryLevel: 0.4,
      outsideZone: false,
      isMocked: false,
      signalLost: false,
    ),
  ];

  @override
  Future<List<TrackPoint>> track(String dayId) async {
    final start = DateTime.now().subtract(const Duration(hours: 3));
    const path = [
      LatLng(5.3170, -4.0270),
      LatLng(5.3185, -4.0240),
      LatLng(5.3200, -4.0250),
      LatLng(5.3220, -4.0225),
      LatLng(5.3205, -4.0200),
      LatLng(5.3215, -4.0205),
    ];
    return [
      for (var i = 0; i < path.length; i++)
        TrackPoint(
          position: path[i],
          recordedAt: start.add(Duration(minutes: 30 * i)),
          outsideZone: false,
        ),
    ];
  }

  @override
  Future<List<TeamMember>> team() async => [
    TeamMember(
      id: 'a2',
      firstName: 'Aminata',
      lastName: 'Diallo',
      phone: '+2250702020202',
      isActive: true,
    ),
    TeamMember(
      id: 'a3',
      firstName: 'Serge',
      lastName: 'Gbagbo',
      phone: null,
      isActive: true,
    ),
  ];

  @override
  Future<List<Zone>> leaderZones() async => [
    Zone(
      id: 'z1',
      name: 'Plateau',
      capacity: 3,
      placesLeft: 2,
      isFull: false,
      sensitive: false,
      area: const [
        [
          LatLng(5.3150, -4.0300),
          LatLng(5.3150, -4.0150),
          LatLng(5.3260, -4.0150),
          LatLng(5.3260, -4.0300),
        ],
      ],
    ),
    Zone(
      id: 'z2',
      name: 'Cocody',
      capacity: 4,
      placesLeft: 1,
      isFull: false,
      sensitive: true,
      area: const [
        [
          LatLng(5.3450, -3.9950),
          LatLng(5.3450, -3.9750),
          LatLng(5.3620, -3.9750),
          LatLng(5.3620, -3.9950),
        ],
      ],
    ),
  ];

  @override
  Future<List<PendingRequest>> pendingRequests() async => [
    PendingRequest(
      id: 'r1',
      agentName: 'Serge Gbagbo',
      agentPhone: null,
      zoneName: 'Cocody',
      isChange: false,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 20)),
    ),
  ];

  @override
  Future<Map<String, dynamic>> sendPositions(
    String dayId,
    List<Map<String, dynamic>> points,
  ) async {
    if (positionsError != null) throw positionsError!;
    positions.add(points);
    return {'accepted': points.length, 'duplicates': 0, 'rejected': 0};
  }
}

/// Période de paie du mois en cours, au format de l'API.
Map<String, dynamic> _month() {
  final now = DateTime.now();
  String d(DateTime x) =>
      '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  return {
    'period': 'monthly',
    'start': d(DateTime(now.year, now.month)),
    'end': d(DateTime(now.year, now.month + 1, 0)),
    'label': 'octobre 2026',
    'currency': 'XOF',
  };
}

Map<String, dynamic> _payLine(
  String id,
  String first,
  String last,
  List<List<Object?>> items, {
  String? grid = 'Agents terrain',
  String role = 'agent',
}) {
  final list = [
    for (final i in items)
      {'label': i[0], 'quantity': i[1], 'unitAmount': i[2], 'amount': i[3]},
  ];
  return {
    'user': {'id': id, 'firstName': first, 'lastName': last, 'role': role},
    'gridName': grid,
    'items': grid == null ? [] : list,
    'gross': grid == null
        ? 0
        : list.fold<int>(0, (s, i) => s + (i['amount'] as int)),
  };
}

/// Gains de démonstration : estimation du mois et deux paies validées.
final payJson = {
  'current': {
    ..._month(),
    'line': _payLine('u1', 'Koffi', 'Brou', [
      ['Fixe', null, null, 40000],
      ['Journées validées', 3, 2500, 7500],
      ['Formulaires « Prospection »', 12, 150, 1800],
      ['Objectif « 120 visites cette semaine » (100 %)', null, null, 10000],
      ['Journées non clôturées', 1, -1000, -1000],
    ]),
  },
  'history': [
    {
      'runId': 'r2',
      'period': 'monthly',
      'periodStart': '2026-09-01',
      'periodEnd': '2026-09-30',
      'label': 'septembre 2026',
      'items': [
        {'label': 'Fixe', 'amount': 40000},
        {
          'label': 'Journées validées',
          'quantity': 9,
          'unitAmount': 2500,
          'amount': 22500,
        },
        {
          'label': 'Formulaires « Prospection »',
          'quantity': 35,
          'unitAmount': 150,
          'amount': 5250,
        },
      ],
      'gross': 67750,
      'adjustments': 5000,
      'total': 72750,
      'status': 'validated',
      'paidAt': null,
      'paymentReference': null,
      'adjustmentsDetail': [
        {'amount': 5000, 'reason': 'Prime de fin de campagne'},
      ],
    },
    {
      'runId': 'r1',
      'period': 'monthly',
      'periodStart': '2026-08-01',
      'periodEnd': '2026-08-31',
      'label': 'août 2026',
      'items': [
        {'label': 'Fixe', 'amount': 40000},
        {
          'label': 'Journées validées',
          'quantity': 11,
          'unitAmount': 2500,
          'amount': 27500,
        },
      ],
      'gross': 67500,
      'adjustments': 0,
      'total': 67500,
      'status': 'paid',
      'paidAt': '2026-09-05T10:00:00Z',
      'paymentReference': 'OM-58213',
      'adjustmentsDetail': [],
    },
  ],
};

/// Estimation de l'équipe d'un chef (le chef compris, comme l'API).
Map<String, dynamic> teamPayJson() {
  final lines = [
    _payLine(
      'u1',
      'Yao',
      'Brou',
      [
        ['Fixe', null, null, 60000],
      ],
      grid: 'Chefs d’équipe',
      role: 'team_lead',
    ),
    _payLine('a1', 'Aminata', 'Diallo', [
      ['Fixe', null, null, 40000],
      ['Journées validées', 2, 2500, 5000],
      ['Formulaires « Audit point de vente »', 4, 150, 600],
      [
        'Objectif « Audit des pharmacies du Plateau » (100 %)',
        null,
        null,
        10000,
      ],
    ]),
    _payLine('a2', 'Koffi', 'Brou', [
      ['Fixe', null, null, 40000],
      ['Journées validées', 1, 2500, 2500],
      ['Journées avec position simulée', 2, -2500, -5000],
    ]),
    _payLine('a3', 'Serge', 'Gbagbo', [], grid: null),
  ];
  return {
    ..._month(),
    'lines': lines,
    'total': lines.fold<int>(0, (s, l) => s + (l['gross'] as int)),
  };
}

/// Session déjà ouverte avec le rôle voulu.
class SignedInAuth extends AuthController {
  SignedInAuth(this.me);

  final Me me;

  @override
  AuthState build() => SignedIn(me, fakeBranding);

  @override
  Future<void> logout({String? message}) async => state = const SignedOut();
}

class SignedOutAuth extends AuthController {
  @override
  AuthState build() => const SignedOut();
}

/// Suivi de position simulé : pas de GPS dans les tests.
class FakeTracker extends LocationTracker {
  FakeTracker(super.db);

  bool _tracking = false;

  @override
  bool get isTracking => _tracking;

  /// Dernière position connue (formulaires) : position fixe au Plateau.
  @override
  Future<Position?> lastKnown() async => Position(
    latitude: 5.32,
    longitude: -4.02,
    timestamp: DateTime.now(),
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<void> start(String dayId, {required String structure}) async {
    _tracking = true;
    lastFixAt = DateTime.now().subtract(const Duration(seconds: 12));
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _tracking = false;
    notifyListeners();
  }

  /// Relevé GPS simulé.
  void emit(LatLng position, {double accuracy = 10, DateTime? at}) {
    lastPosition = position;
    lastFixAt = at ?? DateTime.now();
    onFix?.call(position, accuracy, lastFixAt!);
    notifyListeners();
  }
}

/// Contours du Plateau (comme la démo) : bord est à la longitude -4,01.
const plateauArea = [
  [
    LatLng(5.31, -4.03),
    LatLng(5.31, -4.01),
    LatLng(5.33, -4.01),
    LatLng(5.33, -4.03),
  ],
];

/// Point à [meters] à l'est du Plateau.
LatLng eastOfPlateau(double meters) => LatLng(5.32, -4.01 + meters / 110840);

/// Alertes du téléphone, enregistrées pour vérification.
class FakeAlerts implements AlertSink {
  final shown = <(String, String)>[];
  var cancelled = 0;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> show(int id, String title, String body) async =>
      shown.add((title, body));

  @override
  Future<void> cancel(int id) async => cancelled++;
}

/// Onboarding déjà vu : les tests ouvrent directement la connexion ou l'accueil.
class SeenOnboarding extends OnboardingController {
  @override
  OnboardingState build() => const OnboardingDone();
}

Widget testApp({
  required AuthController Function() auth,
  FakeRepository? repo,
  FakeAlerts? alerts,
}) {
  final db = AppDatabase(NativeDatabase.memory());
  final repository = repo ?? FakeRepository();
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(auth),
      onboardingProvider.overrideWith(SeenOnboarding.new),
      repositoryProvider.overrideWithValue(repository),
      databaseProvider.overrideWithValue(db),
      // Pas de fonds de carte téléchargés pendant les tests.
      mapTilesProvider.overrideWithValue(false),
      trackerProvider.overrideWith((ref) => FakeTracker(db)),
      alertSinkProvider.overrideWithValue(alerts ?? FakeAlerts()),
      syncProvider.overrideWith(
        (ref) => SyncService(
          db,
          repository,
          connectivity: const Stream<List<ConnectivityResult>>.empty(),
        ),
      ),
    ],
    child: const SuiviAgentApp(),
  );
}

/// Profil /auth/me au format de l'API, avec les fonctionnalités de la formule.
Map<String, dynamic> meJsonWith({
  String role = 'agent',
  required List<String> features,
  String status = 'active',
}) => {
  'user': {
    'id': 'u1',
    'firstName': 'Koffi',
    'lastName': 'Brou',
    'email': 'agent@demo.ci',
    'role': role,
  },
  'tenant': {'name': 'Démo Abidjan'},
  'settings': {
    'trackDuringPause': false,
    'allowZoneChangeBeforeStart': true,
    'zoneRequired': true,
  },
  'subscription': {'status': status, 'features': features},
};
