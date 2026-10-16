import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';
import '../../widgets/common.dart';
import '../outlets/outlets_controller.dart';

/// Statut d'une commande : prise → livrée → payée, ou annulée.
enum OrderStatus {
  taken('taken', 'Prise', Icons.receipt_long_rounded, Tone.info),
  delivered('delivered', 'Livrée', Icons.local_shipping_rounded, Tone.warning),
  paid('paid', 'Payée', Icons.payments_rounded, Tone.success),
  cancelled('cancelled', 'Annulée', Icons.block_rounded, Tone.neutral);

  const OrderStatus(this.code, this.label, this.icon, this.tone);

  final String code;
  final String label;
  final IconData icon;
  final Tone tone;

  static OrderStatus from(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => taken);

  /// Suites possibles pour l'agent qui a pris la commande (une commande livrée ne s'annule
  /// que par un responsable).
  List<OrderStatus> get agentNext => switch (this) {
    taken => [delivered, paid, cancelled],
    delivered => [paid],
    _ => const [],
  };

  /// Suites possibles pour un responsable (chef de l'équipe, administrateur) : il peut aussi
  /// annuler une commande déjà livrée.
  List<OrderStatus> get managerNext => switch (this) {
    taken => [delivered, paid, cancelled],
    delivered => [paid, cancelled],
    _ => const [],
  };
}

/// Produit du catalogue d'un point de vente, avec son prix pour ce type de client.
class PricedProduct {
  PricedProduct(this.product, this.price, this.category);

  final CatalogProduct product;

  /// Prix d'une unité de base.
  final num price;
  final String? category;
}

class OrderCatalog {
  OrderCatalog({
    required this.priceList,
    required this.currency,
    required this.products,
  });

  /// Type de client appliqué (null : aucun défini par la structure).
  final String? priceList;
  final String currency;
  final List<PricedProduct> products;

  factory OrderCatalog.fromJson(Map<String, dynamic> j) => OrderCatalog(
    priceList: (j['priceList'] as Map?)?['name'] as String?,
    currency: j['currency'] as String? ?? 'XOF',
    products: [
      for (final p in j['products'] as List? ?? const [])
        PricedProduct(
          CatalogProduct.fromJson({
            ...(p as Map<String, dynamic>),
            'own': true,
          }),
          p['price'] as num,
          p['category'] as String?,
        ),
    ],
  );
}

/// Commande (liste) ; le détail ajoute ses lignes et son historique.
class OrderItem {
  OrderItem({
    required this.id,
    required this.reference,
    required this.outletId,
    required this.outletName,
    required this.agentId,
    required this.agentName,
    required this.status,
    required this.total,
    required this.currency,
    required this.takenAt,
    this.priceListName,
    this.note,
    this.cancelReason,
    this.lineCount = 0,
  });

  final String id;
  final String reference;
  final String outletId;
  final String outletName;
  final String agentId;
  final String agentName;
  final OrderStatus status;
  final num total;
  final String currency;
  final DateTime takenAt;
  final String? priceListName;
  final String? note;
  final String? cancelReason;
  final int lineCount;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    id: j['id'] as String,
    reference: j['reference'] as String,
    outletId: j['outletId'] as String,
    outletName: j['outletName'] as String? ?? '',
    agentId: j['agentId'] as String,
    agentName: j['agentName'] as String? ?? '',
    status: OrderStatus.from(j['status'] as String),
    total: j['total'] as num,
    currency: j['currency'] as String? ?? 'XOF',
    takenAt: DateTime.parse(j['takenAt'] as String).toLocal(),
    priceListName: j['priceListName'] as String?,
    note: j['note'] as String?,
    cancelReason: j['cancelReason'] as String?,
    lineCount: j['lines'] is num ? (j['lines'] as num).toInt() : 0,
  );
}

class OrderLine {
  OrderLine({
    required this.name,
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
  });

  final String name;

  /// Unité et conditionnements, pour afficher « 36 bouteilles (3 casiers) ».
  final CatalogProduct product;
  final num quantity;
  final num unitPrice;
  final num amount;
}

class OrderEvent {
  OrderEvent(this.status, this.at, this.user, this.comment);

  final OrderStatus status;
  final DateTime at;
  final String? user;
  final String? comment;
}

class OrderDetail {
  OrderDetail(this.order, this.lines, this.events);

  final OrderItem order;
  final List<OrderLine> lines;
  final List<OrderEvent> events;

  factory OrderDetail.fromJson(Map<String, dynamic> j) => OrderDetail(
    OrderItem.fromJson({...j, 'lines': (j['lines'] as List).length}),
    [
      for (final l in j['lines'] as List)
        OrderLine(
          name: (l as Map)['name'] as String,
          product: CatalogProduct.fromJson({
            'id': l['productId'],
            'name': l['name'],
            'unit': l['unit'],
            'packagings': l['packagings'] ?? const [],
          }),
          quantity: l['quantity'] as num,
          unitPrice: l['unitPrice'] as num,
          amount: l['amount'] as num,
        ),
    ],
    [
      for (final e in j['events'] as List? ?? const [])
        OrderEvent(
          OrderStatus.from((e as Map)['status'] as String),
          DateTime.parse(e['at'] as String).toLocal(),
          e['user'] as String?,
          e['comment'] as String?,
        ),
    ],
  );
}

/// Catalogue du point de vente (gardé pour le hors ligne par le cache des réponses).
final orderCatalogProvider = FutureProvider.autoDispose
    .family<OrderCatalog, String>(
      (ref, outletId) async => OrderCatalog.fromJson(
        await ref.read(repositoryProvider).orderCatalog(outletId),
      ),
    );

/// Dernières commandes d'un point de vente.
final outletOrdersProvider = FutureProvider.autoDispose
    .family<({List<OrderItem> items, int total}), String>((
      ref,
      outletId,
    ) async {
      final json = await ref
          .read(repositoryProvider)
          .orders(outletId: outletId, limit: 5);
      return (
        items: [
          for (final o in json['items'] as List)
            OrderItem.fromJson(o as Map<String, dynamic>),
        ],
        total: (json['total'] as num).toInt(),
      );
    });

final orderProvider = FutureProvider.autoDispose.family<OrderDetail, String>(
  (ref, id) async =>
      OrderDetail.fromJson(await ref.read(repositoryProvider).order(id)),
);

/// Enregistre la commande sur le téléphone puis l'envoie aussitôt : envoyée (avec la commande
/// créée par le serveur) ou en attente du réseau. Un refus remonte en ApiException.
Future<(SubmitOutcome, OrderItem?)> sendOrder(
  WidgetRef ref, {
  required String outletId,
  required String outletName,
  required Map<String, num> quantities,
  String? note,
}) async {
  final db = ref.read(databaseProvider);
  final sync = ref.read(syncProvider);
  final position = await ref.read(trackerProvider).lastKnown();
  final clientId = const Uuid().v4();
  await db
      .into(db.pendingOutlets)
      .insert(
        PendingOutletsCompanion.insert(
          clientId: clientId,
          kind: 'order',
          outletId: Value(outletId),
          name: 'Commande · $outletName',
          bodyJson: jsonEncode({
            'outletId': outletId,
            'lines': [
              for (final e in quantities.entries)
                {'productId': e.key, 'quantity': e.value},
            ],
            if (note != null && note.isNotEmpty) 'note': note,
            'lat': ?position?.latitude,
            'lng': ?position?.longitude,
            'takenAt': DateTime.now().toUtc().toIso8601String(),
          }),
          createdAt: DateTime.now().toUtc(),
        ),
      );
  final (outcome, json) = await sync.sendOutletNow(clientId);
  ref.invalidate(outletOrdersProvider(outletId));
  ref.invalidate(outletProvider(outletId));
  return (outcome, json == null ? null : OrderItem.fromJson(json));
}
