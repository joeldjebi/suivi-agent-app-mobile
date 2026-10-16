import 'package:suivi_agent/core/api_client.dart';

import 'fakes.dart';

/// Formule avec les points de vente.
const outletFeatures = {'missions', 'points_of_sale', 'groups', 'team_leads'};

Map<String, dynamic> outletJson(
  String id,
  String name, {
  String status = 'new',
  String? category = 'Boutique',
  double? lat = 5.3201,
  double? lng = -4.02,
  int? distance,
  String? photoId,
  Map<String, dynamic> data = const {},
  bool overdue = false,
  int? daysSinceVisit,
}) => {
  'id': id,
  'name': name,
  'category': category,
  'managerName': 'Awa Koné',
  'phone': '+2250707070707',
  'landmark': 'En face du marché',
  'lat': lat,
  'lng': lng,
  'status': status,
  'statusChangedAt': '2026-10-10T09:00:00.000Z',
  'photoId': photoId,
  'data': data,
  'zone': {'id': 'z1', 'name': 'Plateau'},
  'createdBy': {'id': 'u1', 'name': 'Koffi Brou'},
  'distance': ?distance,
  'overdue': overdue,
  'frequencyDays': 30,
  'visitFrequencyDays': null,
  'daysSinceVisit': daysSinceVisit,
  'lastVisitAt': daysSinceVisit == null
      ? null
      : DateTime.now()
            .subtract(Duration(days: daysSinceVisit))
            .toUtc()
            .toIso8601String(),
  'dueAt': DateTime.now()
      .add(Duration(days: overdue ? -5 : 10))
      .toUtc()
      .toIso8601String(),
};

/// API des points de vente simulée.
class OutletsRepo extends FakeRepository {
  final outletList = <Map<String, dynamic>>[
    outletJson('o1', 'Boutique Awa', status: 'prospect', distance: 12),
    outletJson('o2', 'Pharmacie du Port', category: 'Pharmacie', distance: 340),
  ];
  final unlocatedList = <Map<String, dynamic>>[
    outletJson(
      'o3',
      'Cave Koffi',
      category: 'Maquis / Bar',
      lat: null,
      lng: null,
    ),
  ];
  final created = <Map<String, dynamic>>[];
  final statusChanges = <(String, String, String?)>[];

  /// Erreurs simulées pour les prochains ajouts (dans l'ordre).
  final createErrors = <ApiException>[];

  @override
  Future<Map<String, dynamic>> outletForm() async => {
    'fields': [
      {
        'key': 'frigo',
        'label': 'Possède un frigo',
        'type': 'boolean',
        'required': false,
      },
    ],
    'categories': ['Boutique', 'Kiosque', 'Pharmacie'],
  };

  @override
  Future<Map<String, dynamic>> outlets({
    String? q,
    String? status,
    double? lat,
    double? lng,
    double? radius,
    bool unlocated = false,
    bool overdue = false,
    int limit = 100,
  }) async {
    final source = unlocated ? unlocatedList : outletList;
    final items = source
        .where((o) => !overdue || o['overdue'] == true)
        .where((o) => status == null || o['status'] == status)
        .where(
          (o) =>
              q == null ||
              (o['name'] as String).toLowerCase().contains(q.toLowerCase()),
        )
        .toList();
    return {
      'items': items,
      'total': items.length,
      'counts': {'new': 1, 'prospect': 1, 'active': 0},
      'overdue': source.where((o) => o['overdue'] == true).length,
    };
  }

  @override
  Future<Map<String, dynamic>> outlet(String id) async {
    final o = [
      ...outletList,
      ...unlocatedList,
    ].firstWhere((o) => o['id'] == id);
    return {
      ...o,
      'history': [
        {
          'id': 'h1',
          'fromStatus': null,
          'toStatus': o['status'],
          'comment': null,
          'createdAt': '2026-10-10T09:00:00.000Z',
          'user': {'id': 'u1', 'name': 'Koffi Brou'},
        },
      ],
      'visits': visitsJson,
    };
  }

  /// Dernières visites renvoyées avec la fiche.
  List<Map<String, dynamic>> visitsJson = const [];

  @override
  Future<Map<String, dynamic>> createOutlet(Map<String, dynamic> body) async {
    if (createErrors.isNotEmpty) throw createErrors.removeAt(0);
    created.add(body);
    final o = outletJson('o9', body['name'] as String, status: body['status']);
    outletList.add(o);
    return o;
  }

  @override
  Future<Map<String, dynamic>> changeOutletStatus(
    String id,
    String status,
    String? comment,
  ) async {
    statusChanges.add((id, status, comment));
    final o = outletList.firstWhere((o) => o['id'] == id);
    o['status'] = status;
    return o;
  }
}

/// Mission de visites (liste précise) et ses points de vente.
class VisitsRepo extends OutletsRepo {
  VisitsRepo() {
    outletList.add(
      outletJson('o7', 'Kiosque du Lycée', category: 'Kiosque', lat: 5.33),
    );
  }

  Map<String, dynamic> get _mission => {
    'id': 'v1',
    'title': 'Tournée du Plateau',
    'status': 'in_progress',
    'progressMethod': 'outlets',
    'visitMode': 'list',
    'dueDate': DateTime.now()
        .add(const Duration(days: 2))
        .toUtc()
        .toIso8601String(),
    'progress': {'current': 1, 'target': 3, 'percent': 33},
    'zones': [
      {'id': 'z1', 'name': 'Plateau'},
    ],
    'type': {
      'name': 'Contrôle',
      'fields': [
        {'key': 'stock', 'label': 'Stock', 'type': 'number', 'required': false},
      ],
    },
  };

  @override
  Future<List<Map<String, dynamic>>> missionsJson() async => [_mission];

  @override
  Future<Map<String, dynamic>> missionJson(String id) async => _mission;

  @override
  Future<List<dynamic>> missionOutlets(
    String id, {
    double? lat,
    double? lng,
  }) async => [
    {
      'id': 'o1',
      'name': 'Boutique Awa',
      'category': 'Boutique',
      'status': 'prospect',
      'lat': 5.3201,
      'lng': -4.02,
      'visits': 0,
      'visited': false,
      'distance': 11,
    },
    {
      'id': 'o7',
      'name': 'Kiosque du Lycée',
      'category': 'Kiosque',
      'status': 'new',
      'lat': 5.33,
      'lng': -4.02,
      'visits': 0,
      'visited': false,
      'distance': 1113,
    },
    {
      'id': 'o2',
      'name': 'Pharmacie du Port',
      'category': 'Pharmacie',
      'status': 'new',
      'lat': 5.3201,
      'lng': -4.02,
      'visits': 2,
      'visited': true,
      'lastVisitAt': '2026-10-12T10:00:00.000Z',
      'lastVisitBy': 'Koffi Brou',
      'distance': 11,
    },
  ];
}

/// Mission avec un relevé par produit (boissons : nos produits et un concurrent).
class ReadingsRepo extends OutletsRepo {
  Map<String, dynamic> get _mission => {
    'id': 'r1',
    'title': 'Relevé des boissons',
    'status': 'in_progress',
    'progressMethod': 'count',
    'dueDate': DateTime.now()
        .add(const Duration(days: 2))
        .toUtc()
        .toIso8601String(),
    'progress': {'current': 3, 'target': 20, 'percent': 15},
    'type': {
      'name': 'Relevé',
      'fields': [
        {
          'key': 'releve',
          'label': 'Relevé des boissons',
          'type': 'products',
          'required': true,
          'products': {
            'scope': 'all',
            'measures': ['presence', 'stock', 'price'],
          },
        },
      ],
    },
    'products': {
      'releve': [
        {
          'id': 'p-coca',
          'name': 'Coca-Cola',
          'format': '33 cl',
          'own': true,
          'unit': 'Bouteille',
          'packagings': [
            {'name': 'Pack', 'units': 6},
            {'name': 'Casier', 'units': 12},
          ],
        },
        {
          'id': 'p-pepsi',
          'name': 'Pepsi',
          'format': '33 cl',
          'own': false,
          'unit': 'Bouteille',
          'packagings': [
            {'name': 'Casier', 'units': 12},
          ],
        },
      ],
    },
  };

  @override
  Future<List<Map<String, dynamic>>> missionsJson() async => [_mission];

  @override
  Future<Map<String, dynamic>> missionJson(String id) async => _mission;
}

/// Tableau de bord des relevés (chef).
class InsightsRepo extends OutletsRepo {
  final periods = <(String, String)>[];

  @override
  Future<Map<String, dynamic>> productInsights(
    String part, {
    required String from,
    required String to,
  }) async {
    if (part == 'overview') periods.add((from, to));
    return switch (part) {
      'overview' => {
        'visits': 26,
        'outlets': 11,
        'products': 3,
        'ownStockouts': 4,
        'ownChecked': 19,
        'stockoutRate': 21,
        'ownSold': 478,
        'competitorSold': 288,
        'ownLosses': 34,
      },
      'stockouts' => {
        'byProduct': [
          {
            'productId': 'p-fanta',
            'name': 'Fanta',
            'format': '33 cl',
            'own': true,
            'checked': 10,
            'stockouts': 4,
            'rate': 40,
          },
          {
            'productId': 'p-coca',
            'name': 'Coca-Cola',
            'format': '33 cl',
            'own': true,
            'checked': 9,
            'stockouts': 0,
            'rate': 0,
          },
        ],
        'outlets': [
          {
            'productId': 'p-fanta',
            'productName': 'Fanta',
            'format': '33 cl',
            'own': true,
            'outletId': 'o1',
            'outletName': 'Boutique Awa',
            'zone': 'Plateau',
            'since': '2026-10-10T11:44:00.000Z',
            'lat': 5.32,
            'lng': -4.02,
            'agent': 'Koffi Brou',
          },
        ],
      },
      'sales' => {
        'products': [
          {
            'productId': 'p-fanta',
            'name': 'Fanta',
            'format': '33 cl',
            'own': true,
            'unit': 'Bouteille',
            'packagings': [
              {'name': 'Casier', 'units': 12},
            ],
            'sold': 190,
            'losses': 26,
            'ordered': 0,
            'outlets': 8,
          },
          {
            'productId': 'p-pepsi',
            'name': 'Pepsi',
            'format': '33 cl',
            'own': false,
            'unit': 'Bouteille',
            'packagings': [
              {'name': 'Casier', 'units': 12},
            ],
            'sold': 180,
            'losses': 27,
            'ordered': 0,
            'outlets': 9,
          },
        ],
        'lossOutlets': [],
      },
      _ => {
        'products': [],
        'categories': [
          {
            'category': 'Boissons',
            'own': 305,
            'competitor': 260,
            'gapPercent': 17,
          },
        ],
      },
    };
  }
}

/// Points de vente en retard et tournée.
class RouteRepo extends OutletsRepo {
  RouteRepo() {
    outletList
      ..[1] = outletJson(
        'o2',
        'Pharmacie du Port',
        category: 'Pharmacie',
        distance: 340,
        overdue: true,
        daysSinceVisit: 42,
      )
      ..add(
        outletJson(
          'o5',
          'Kiosque Orange',
          category: 'Kiosque',
          distance: 900,
          overdue: true,
          lat: 5.328,
        ),
      );
  }

  final routes = <(double, double, String?)>[];

  @override
  Future<Map<String, dynamic>> outletRoute({
    required double lat,
    required double lng,
    String? missionId,
  }) async {
    routes.add((lat, lng, missionId));
    return {
      'source': missionId == null ? 'overdue' : 'mission',
      'candidates': 2,
      'stops': [
        {
          ...outletList[1],
          'order': 1,
          'legMeters': 340,
          'cumulativeMeters': 340,
        },
        {
          ...outletList[2],
          'order': 2,
          'legMeters': 860,
          'cumulativeMeters': 1200,
        },
      ],
      'totalMeters': 1200,
      'travelMinutes': 21,
      'visitMinutes': 20,
    };
  }
}

/// Module Points de vente seul : visites libres avec les formulaires de visite.
class FreeVisitRepo extends OutletsRepo {
  FreeVisitRepo({int forms = 2}) {
    visitFormsJson = [
      {
        'id': 'f1',
        'name': 'Audit point de vente',
        'description': null,
        'fields': [
          {
            'key': 'remarque',
            'label': 'Remarque',
            'type': 'text',
            'required': true,
          },
        ],
        'products': <String, dynamic>{},
      },
      {
        'id': 'f2',
        'name': 'Prospection',
        'description': null,
        'fields': <dynamic>[],
        'products': <String, dynamic>{},
      },
    ].take(forms).toList();
  }
}

/// Formule avec le seul module Points de vente (sans missions).
const outletOnlyFeatures = {'points_of_sale', 'groups', 'team_leads'};

/// Fiche complète : relevés produits (dont un concurrent) et visites, dont une rejetée.
class ActivityRepo extends FreeVisitRepo {
  ActivityRepo() : super(forms: 1) {
    visitsJson = [
      {
        'id': 's1',
        'missionId': null,
        'missionTitle': 'Audit point de vente',
        'formName': 'Audit point de vente',
        'agent': 'Koffi Brou',
        'submittedAt': '2026-10-12T10:00:00.000Z',
        'status': 'accepted',
      },
      {
        'id': 's2',
        'missionId': 'v1',
        'missionTitle': 'Tournée du Plateau',
        'formName': 'Audit',
        'agent': 'Awa Koné',
        'submittedAt': '2026-10-05T10:00:00.000Z',
        'status': 'rejected',
      },
    ];
    outletReadingsJson = [
      {
        'productId': 'p-coca',
        'name': 'Coca-Cola',
        'format': '33 cl',
        'own': true,
        'unit': 'Bouteille',
        'packagings': [
          {'name': 'Casier', 'units': 12},
        ],
        'last': {
          'at': '2026-10-12T10:00:00.000Z',
          'presence': true,
          'stock': 44,
          'price': 300,
        },
        'stockHistory': [
          {'at': '2026-10-05T10:00:00.000Z', 'stock': 30},
          {'at': '2026-10-12T10:00:00.000Z', 'stock': 44},
        ],
      },
      {
        'productId': 'p-pepsi',
        'name': 'Pepsi',
        'format': '33 cl',
        'own': false,
        'unit': 'Bouteille',
        'packagings': <dynamic>[],
        'last': {
          'at': '2026-10-12T10:00:00.000Z',
          'presence': false,
          'stock': null,
          'price': null,
        },
        'stockHistory': <dynamic>[],
      },
    ];
  }
}

/// Historique d'un point de vente : une visite de l'agent (avec relevé), une d'un collègue.
class HistoryRepo extends ActivityRepo {
  HistoryRepo() {
    Map<String, dynamic> visit(
      String id,
      String agentId,
      String agent,
      String at,
    ) => {
      'id': id,
      'missionId': null,
      'title': 'Audit point de vente',
      'formName': 'Audit point de vente',
      'agentId': agentId,
      'agent': agent,
      'submittedAt': at,
      'status': 'accepted',
      'rejectedReason': null,
      'distance': 12,
      'readings': id == 's1' ? 2 : 0,
    };
    outletVisitsJson = [
      visit('s1', 'u1', 'Koffi Brou', '2026-10-12T10:00:00.000Z'),
      visit('s3', 'u7', 'Awa Koné', '2026-10-08T10:00:00.000Z'),
    ];
    visitDetailsJson = {
      's1': {
        ...outletVisitsJson.first,
        'outletId': 'o1',
        'outletName': 'Boutique Awa',
        'fields': [
          {
            'key': 'remarque',
            'label': 'Remarque',
            'type': 'text',
            'required': false,
          },
          {
            'key': 'releve',
            'label': 'Relevé',
            'type': 'products',
            'required': false,
          },
          {
            'key': 'rayon',
            'label': 'Photo du rayon',
            'type': 'photo',
            'required': false,
          },
        ],
        'data': {
          'remarque': 'Rayon bien rempli',
          'releve': {
            'p-coca': {'presence': true, 'stock': 44, 'price': 300, 'sold': 24},
            'p-pepsi': {'presence': false},
          },
          'rayon': 'ph-1',
        },
        'photos': <String, dynamic>{},
        'readings': [
          {
            'productId': 'p-coca',
            'name': 'Coca-Cola',
            'format': '33 cl',
            'own': true,
            'unit': 'Bouteille',
            'packagings': [
              {'name': 'Casier', 'units': 12},
            ],
            'presence': true,
            'stock': 44,
            'price': 300,
            'sold': 24,
            'losses': 0,
          },
          {
            'productId': 'p-pepsi',
            'name': 'Pepsi',
            'format': '33 cl',
            'own': false,
            'unit': 'Bouteille',
            'packagings': <dynamic>[],
            'presence': false,
            'stock': null,
            'price': null,
            'sold': null,
            'losses': null,
          },
        ],
      },
    };
  }
}

/// Formule avec les points de vente et les relevés produits.
const auditFeatures = {
  'missions',
  'points_of_sale',
  'product_audits',
  'groups',
  'team_leads',
};

/// Prise de commande : catalogue au tarif « Détaillant » (Coca en casiers de 12, Fanta).
class OrdersRepo extends OutletsRepo {
  OrdersRepo() {
    orderCatalogJson = {
      'priceList': {'id': 'pl1', 'name': 'Détaillant'},
      'currency': 'XOF',
      'products': [
        {
          'id': 'p-coca',
          'name': 'Coca-Cola',
          'format': '33 cl',
          'category': 'Boissons',
          'unit': 'Bouteille',
          'packagings': [
            {'name': 'Casier', 'units': 12},
          ],
          'price': 300,
        },
        {
          'id': 'p-fanta',
          'name': 'Fanta',
          'format': '33 cl',
          'category': 'Boissons',
          'unit': 'Bouteille',
          'packagings': [
            {'name': 'Casier', 'units': 12},
          ],
          'price': 350,
        },
      ],
    };
  }
}

/// Formule avec les points de vente et la prise de commande.
const orderFeatures = {
  'missions',
  'points_of_sale',
  'orders',
  'groups',
  'team_leads',
};

/// Statistiques d'un formulaire de prospection : nombre, Oui/Non, liste de choix, photo.
class FormStatsRepo extends OutletsRepo {
  FormStatsRepo() {
    formStatsJson = {
      'forms': [
        {'id': 't1', 'name': 'Prospection', 'submissions': 3, 'outlets': 2},
        {'id': 't2', 'name': 'Audit', 'submissions': 1, 'outlets': 1},
      ],
    };
    Map<String, dynamic> field(
      String key,
      String label,
      String type,
      Map<String, dynamic> stats,
    ) => {'key': key, 'label': label, 'type': type, 'stats': stats};
    formFieldStatsJson = {
      't1': {
        'submissions': 3,
        'outlets': 2,
        'fields': [
          field('montant', 'Montant encaissé', 'number', {
            'kind': 'number',
            'answered': 2,
            'sum': 40000,
            'avg': 20000,
            'min': 10000,
            'max': 30000,
          }),
          field('conforme', 'Présentation conforme', 'boolean', {
            'kind': 'boolean',
            'answered': 3,
            'yes': 2,
            'no': 1,
            'yesRate': 67,
          }),
          field('interet', 'Client intéressé', 'select', {
            'kind': 'select',
            'answered': 3,
            'options': [
              {'value': 'Oui', 'count': 2},
              {'value': 'À relancer', 'count': 1},
              {'value': 'Non', 'count': 0},
            ],
          }),
          field('vitrine', 'Vitrine', 'photo', {
            'kind': 'photo',
            'answered': 2,
          }),
          field('nom', 'Commerce', 'text', {'kind': 'text', 'answered': 3}),
        ],
      },
      't2': {
        'submissions': 1,
        'outlets': 1,
        'fields': [
          field('ok', 'Rayon rangé', 'boolean', {
            'kind': 'boolean',
            'answered': 1,
            'yes': 0,
            'no': 1,
            'yesRate': 0,
          }),
        ],
      },
    };
  }
}

/// Relevés produits dans la formule, mais aucune visite avec relevé sur la période.
class NoReadingsRepo extends FormStatsRepo {
  @override
  Future<Map<String, dynamic>> productInsights(
    String part, {
    required String from,
    required String to,
  }) async => switch (part) {
    'overview' => {
      'visits': 0,
      'outlets': 0,
      'products': 0,
      'ownStockouts': 0,
      'ownChecked': 0,
      'stockoutRate': null,
      'ownSold': 0,
      'competitorSold': 0,
      'ownLosses': 0,
    },
    'stockouts' => {'byProduct': <dynamic>[], 'outlets': <dynamic>[]},
    'sales' => {'products': <dynamic>[], 'lossOutlets': <dynamic>[]},
    _ => {'products': <dynamic>[], 'categories': <dynamic>[]},
  };
}

/// Fiche chargée : 8 produits relevés (3 en rupture, 2 concurrents) et 7 changements de statut.
class BusyOutletRepo extends ActivityRepo {
  BusyOutletRepo() {
    Map<String, dynamic> reading(
      String id,
      String name, {
      bool own = true,
      bool out = false,
    }) => {
      'productId': id,
      'name': name,
      'format': '33 cl',
      'own': own,
      'unit': 'Bouteille',
      'packagings': [
        {'name': 'Casier', 'units': 12},
      ],
      'last': {
        'at': '2026-10-12T10:00:00.000Z',
        'presence': !out,
        'stock': out ? null : 24,
        'price': out ? null : 300,
      },
      'stockHistory': <dynamic>[],
    };
    outletReadingsJson = [
      reading('a', 'Alpha'),
      reading('b', 'Bravo'),
      reading('c', 'Charlie', out: true),
      reading('d', 'Delta'),
      reading('e', 'Echo', out: true),
      reading('f', 'Foxtrot'),
      reading('x', 'Xray', own: false, out: true),
      reading('y', 'Yankee', own: false),
    ];
  }
}
