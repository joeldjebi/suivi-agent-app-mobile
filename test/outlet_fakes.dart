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
