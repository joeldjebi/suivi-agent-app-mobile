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
    int limit = 100,
  }) async {
    final source = unlocated ? unlocatedList : outletList;
    final items = source
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
    };
  }

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
