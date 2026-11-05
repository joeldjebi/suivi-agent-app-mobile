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
    'name': id == 'p-coca' ? 'Coca-Cola' : 'Fanta',
    'format': '33 cl',
    'unit': 'Bouteille',
    'packagings': [
      {'name': 'Casier', 'units': 12},
    ],
    'quantity': quantity,
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
    'today': {
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
}

class FakeSharer implements FileSharer {
  final shared = <(String, int)>[];

  @override
  Future<void> sharePdf(Uint8List bytes, String filename, String text) async =>
      shared.add((filename, bytes.length));
}
