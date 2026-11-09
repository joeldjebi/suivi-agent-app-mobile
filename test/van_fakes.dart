import 'dart:typed_data';

import 'package:suivi_agent/core/api_client.dart';
import 'package:suivi_agent/features/van_sales/van_sales.dart';

import 'outlet_fakes.dart';

/// Formule avec la vente en camionnette.
const vanFeatures = {...orderFeatures, 'product_audits', 'van_sales'};

/// API de la vente en camionnette simulée : un camion avec 24 Coca et 6 Fanta, un
/// chargement à confirmer, une cliente (Boutique Awa) avec ou sans crédit.
class VanRepo extends OrdersRepo {
  Map<String, num> stock = {'p-coca': 24, 'p-fanta': 6};

  /// Sorti du camion aujourd'hui, par produit.
  Map<String, num> outToday = {};

  /// Journée (ventes, encaissements) à la place de celle par défaut.
  Map<String, dynamic>? todayJson;
  bool loadPending = true;
  num? creditLimit;
  num outstanding = 0;

  final saleBodies = <Map<String, dynamic>>[];
  final confirmBodies = <(String, Map<String, dynamic>)>[];
  final paymentBodies = <Map<String, dynamic>>[];
  final lossBodies = <Map<String, dynamic>>[];
  ApiException? saleError;

  Map<String, dynamic> _line(String id, num quantity) => {
    'productId': id,
    'name': const {'p-coca': 'Coca-Cola', 'p-sprite': 'Sprite'}[id] ?? 'Fanta',
    'format': '33 cl',
    'unit': 'Bouteille',
    'packagings': [
      {'name': 'Casier', 'units': 12},
    ],
    'quantity': quantity,
    'outToday': outToday[id] ?? 0,
  };

  @override
  Future<Map<String, dynamic>> myVan() async => {
    'van': {'id': 'v1', 'name': 'Camion 1', 'plate': 'AB 1234 CI'},
    'depots': [
      {'id': 'd1', 'name': 'Dépôt Yopougon'},
    ],
    'stock': [for (final e in stock.entries) _line(e.key, e.value)],
    'pending': [
      if (loadPending)
        {
          'id': 'm-load',
          'kind': 'load',
          'label': 'Chargement',
          'fromName': 'Dépôt Yopougon',
          'toName': 'Camion 1',
          'occurredAt': '2026-11-05T07:30:00.000Z',
          'createdByName': 'Awa Koné',
          'lines': [_line('p-coca', 24)],
        },
    ],
    'today':
        todayJson ??
        {
          'salesCount': saleBodies.length,
          'salesAmount': 0,
          'cash': 0,
          'mobileMoney': 0,
          'bank': 0,
          'dueOnSales': 0,
          'cashBalance': 2500,
        },
  };

  @override
  Future<Map<String, dynamic>> confirmMovement(
    String id,
    Map<String, dynamic> body,
  ) async {
    confirmBodies.add((id, body));
    loadPending = false;
    for (final l in body['lines'] as List) {
      final id = (l as Map)['productId'] as String;
      stock[id] = (stock[id] ?? 0) + (l['received'] as num);
    }
    return {'id': id, 'status': 'done'};
  }

  @override
  Future<Map<String, dynamic>> outletBalance(String outletId) async => {
    'outletId': outletId,
    'creditLimit': creditLimit,
    'outstanding': outstanding,
    'advance': 0,
    'available': creditLimit == null ? 0 : creditLimit! - outstanding,
    'dues': const [],
  };

  @override
  Future<Map<String, dynamic>> createSale(Map<String, dynamic> body) async {
    if (saleError != null) throw saleError!;
    saleBodies.add(body);
    final order = await super.createOrder(body);
    final total = order['total'] as num;
    final paid = body['paidAmount'] as num;
    for (final l in body['lines'] as List) {
      final id = (l as Map)['productId'] as String;
      stock[id] = (stock[id] ?? 0) - (l['quantity'] as num);
    }
    order
      ..['kind'] = 'sale'
      ..['status'] = paid >= total ? 'paid' : 'delivered'
      ..['paidAmount'] = paid
      ..['due'] = total - paid
      ..['locationName'] = 'Camion 1';
    return order;
  }

  @override
  Future<Map<String, dynamic>> createPayment(Map<String, dynamic> body) async {
    paymentBodies.add(body);
    outstanding -= body['amount'] as num;
    return {'id': 'pay-1'};
  }

  @override
  Future<Map<String, dynamic>> createLoss(Map<String, dynamic> body) async {
    lossBodies.add(body);
    return {'id': 'm-loss'};
  }

  @override
  Future<List<int>> receiptPdf(String orderId) async => [37, 80, 68, 70];

  // Historique du camion : deux ventes (une à crédit), un chargement reçu avec un écart et
  // un à confirmer, ma demande de dépannage et ma part chez un collègue, une casse, un
  // retour en attente. Les filtres « à crédit » et « reçus » sont appliqués.
  final historyQueries = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> vanHistory(Map<String, dynamic> query) async {
    historyQueries.add(query);
    Map<String, dynamic> product(String id, num quantity) => {
      ..._line(id, quantity),
      'name': id == 'p-coca' ? 'Coca-Cola 33 cl' : 'Fanta 33 cl',
    };
    switch (query['type']) {
      case 'sales':
        final credit = query['payment'] == 'credit';
        final sales = [
          if (!credit)
            _sale('s1', 'Boutique Awa', 3600, 3600, '2026-11-09T09:15:00Z'),
          _sale('s2', 'Chez Koffi', 1500, 500, '2026-11-08T16:40:00Z'),
        ];
        return {
          'items': sales,
          'total': sales.length,
          'summary': {
            'count': sales.length,
            'amount': credit ? 1500 : 5100,
            'paid': credit ? 500 : 4100,
            'credit': 1000,
            'cancelled': 0,
            'currency': 'XOF',
          },
        };
      case 'loads':
        return {
          'items': [
            _movement('m-l2', 'load', 'pending', [
              {...product('p-fanta', 12), 'received': null},
            ], at: '2026-11-09T07:00:00Z'),
            _movement('m-l1', 'load', 'done', [
              {...product('p-coca', 48), 'received': 46},
              {...product('p-fanta', 24), 'received': 24},
            ], at: '2026-11-08T07:30:00Z'),
          ],
          'total': 2,
          'summary': {
            'count': 2,
            'products': [product('p-coca', 46), product('p-fanta', 36)],
          },
        };
      case 'transfers':
        final mine = transferJson(
          id: 't-mine',
          requesterId: 'u1',
          requesterName: 'Koffi Brou',
          lines: [
            {
              'productId': 'p-coca',
              'name': 'Coca-Cola 33 cl',
              'requested': 6,
              'reserved': 0,
              'given': 4,
              'remaining': 2,
            },
          ],
          legs: [
            {
              'id': 'leg-1',
              'giverId': 'u2',
              'giverName': 'Awa Koné',
              'status': 'done',
              'statusLabel': 'Remise',
              'lines': [
                {
                  'productId': 'p-coca',
                  'name': 'Coca-Cola 33 cl',
                  'quantity': 4,
                },
              ],
            },
          ],
        )..['direction'] = 'received';
        final theirs = transferJson(
          id: 't-theirs',
          requesterId: 'u3',
          requesterName: 'Yao Kouassi',
          lines: [
            {
              'productId': 'p-fanta',
              'name': 'Fanta 33 cl',
              'requested': 3,
              'reserved': 0,
              'given': 3,
              'remaining': 0,
            },
          ],
          legs: [
            {
              'id': 'leg-2',
              'giverId': 'u1',
              'giverName': 'Koffi Brou',
              'status': 'done',
              'statusLabel': 'Remise',
              'lines': [
                {'productId': 'p-fanta', 'name': 'Fanta 33 cl', 'quantity': 3},
              ],
            },
          ],
        );
        theirs
          ..['status'] = 'done'
          ..['statusLabel'] = 'Terminé'
          ..['direction'] = 'given';
        final received = query['direction'] == 'received';
        return {
          'items': [if (!received) theirs, mine],
          'total': received ? 1 : 2,
          'summary': {
            'requested': 1,
            'helped': received ? 0 : 1,
            'products': [
              {...product('p-coca', 0), 'received': 4, 'given': 0},
              if (!received)
                {...product('p-fanta', 0), 'received': 0, 'given': 3},
            ],
          },
        };
      case 'losses':
        return {
          'items': [
            _movement('m-loss', 'loss', 'done', [
              product('p-fanta', 2),
            ], note: 'Casier tombé'),
          ],
          'total': 1,
          'summary': {
            'count': 1,
            'products': [product('p-fanta', 2)],
          },
        };
      default:
        return {
          'items': [
            _movement('m-unload', 'unload', 'pending', [product('p-coca', 10)]),
          ],
          'total': 1,
          'summary': {
            'count': 1,
            'products': [product('p-coca', 10)],
          },
        };
    }
  }

  Map<String, dynamic> _sale(
    String id,
    String outlet,
    num total,
    num paid,
    String at,
  ) => {
    'id': id,
    'reference': 'CMD-00${id.substring(1)}',
    'kind': 'sale',
    'outletId': 'o-$id',
    'outletName': outlet,
    'agentId': 'u1',
    'agentName': 'Koffi Brou',
    'status': paid < total ? 'delivered' : 'paid',
    'total': total,
    'paidAmount': paid,
    'due': total - paid,
    'currency': 'XOF',
    'takenAt': at,
    'lines': 1,
  };

  Map<String, dynamic> _movement(
    String id,
    String kind,
    String status,
    List<Map<String, dynamic>> lines, {
    String at = '2026-11-08T11:00:00Z',
    String? note,
  }) => {
    'id': id,
    'kind': kind,
    'status': status,
    'occurredAt': at,
    'fromName': kind == 'load' ? 'Dépôt Yopougon' : 'Camion 1',
    'toName': kind == 'load' ? 'Camion 1' : 'Dépôt Yopougon',
    'note': note,
    'lines': lines,
  };

  // Dépannage entre camions.
  List<Map<String, dynamic>> myTransfersJson = [];
  List<Map<String, dynamic>> nearbyJson = [];
  final transferBodies = <Map<String, dynamic>>[];
  final acceptBodies = <(String, List<Map<String, dynamic>>)>[];
  final handoverBodies = <Map<String, dynamic>>[];
  final closed = <String>[];

  @override
  Future<List<dynamic>> transfers({String state = 'open'}) async =>
      myTransfersJson;

  @override
  Future<List<dynamic>> nearbyTransfers() async => nearbyJson;

  @override
  Future<Map<String, dynamic>> createTransfer(Map<String, dynamic> body) async {
    transferBodies.add(body);
    final t = transferJson(
      id: 't-mine',
      requesterId: 'u1',
      requesterName: 'Koffi Brou',
      token: 'CODE-KOFFI',
      lines: [
        for (final l in body['lines'] as List)
          {
            'productId': (l as Map)['productId'],
            'name': l['productId'] == 'p-coca'
                ? 'Coca-Cola 33 cl'
                : 'Fanta 33 cl',
            'requested': l['quantity'],
            'reserved': 0,
            'given': 0,
            'remaining': l['quantity'],
          },
      ],
    );
    myTransfersJson = [t];
    return t;
  }

  @override
  Future<Map<String, dynamic>> acceptTransfer(
    String id,
    List<Map<String, dynamic>> lines,
  ) async {
    acceptBodies.add((id, lines));
    final t = nearbyJson.firstWhere((x) => x['id'] == id);
    nearbyJson = [];
    final accepted = {
      ...t,
      'legs': [
        {
          'id': 'leg-1',
          'giverId': 'u1',
          'giverName': 'Koffi Brou',
          'status': 'accepted',
          'statusLabel': 'Réservée',
          'crossTeam': false,
          'expiresAt': '2026-11-07T15:30:00.000Z',
          'lines': [
            for (final l in lines)
              {
                'productId': l['productId'],
                'name': 'Coca-Cola 33 cl',
                'quantity': l['quantity'],
              },
          ],
        },
      ],
    };
    myTransfersJson = [accepted];
    return accepted;
  }

  ApiException? handoverError;

  @override
  Future<Map<String, dynamic>> handoverTransfer(
    Map<String, dynamic> body,
  ) async {
    if (handoverError != null) throw handoverError!;
    handoverBodies.add(body);
    myTransfersJson = [];
    return {};
  }

  @override
  Future<Map<String, dynamic>> closeTransfer(String id) async {
    closed.add(id);
    myTransfersJson = [];
    return {};
  }

  // Vente hors zone.
  @override
  Future<List<dynamic>> searchOutlets({
    String? q,
    double? lat,
    double? lng,
  }) async => [
    {
      'id': 'o-maquis',
      'name': 'Maquis Cocody',
      'zoneName': 'Cocody',
      'distance': lat == null ? null : 850,
      'inScope': false,
    },
  ];

  @override
  Future<Map<String, dynamic>> outOfZoneContext(String outletId) async => {
    'outlet': {'id': outletId, 'name': 'Maquis Cocody', 'zoneName': 'Cocody'},
    'catalog': await orderCatalog(outletId),
    'balance': {
      'creditLimit': null,
      'outstanding': 0,
      'advance': 0,
      'available': 0,
    },
  };
}

/// Demande de dépannage telle que l'API la renvoie.
Map<String, dynamic> transferJson({
  required String id,
  required String requesterId,
  required String requesterName,
  required List<Map<String, dynamic>> lines,
  String? token,
  List<Map<String, dynamic>> legs = const [],
  Map<String, num> myStock = const {},
  int? distanceM,
}) => {
  'id': id,
  'status': 'open',
  'statusLabel': 'En recherche',
  'requesterId': requesterId,
  'requesterName': requesterName,
  'requesterVanId': 'v-x',
  'note': null,
  'createdAt': '2026-11-07T14:00:00.000Z',
  'lines': lines,
  'legs': legs,
  'token': token,
  'myStock': myStock,
  'distanceM': distanceM,
};

class FakeSharer implements FileSharer {
  final shared = <(String, int)>[];

  @override
  Future<void> sharePdf(Uint8List bytes, String filename, String text) async =>
      shared.add((filename, bytes.length));
}
