import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/database.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';
import '../orders/orders.dart';
import '../outlets/outlets_controller.dart';

/// Moyens de paiement d'une vente ou d'un paiement.
enum PaymentMethod {
  cash('cash', 'Espèces'),
  mobileMoney('mobile_money', 'Mobile money'),
  bank('bank', 'Virement');

  const PaymentMethod(this.code, this.label);

  final String code;
  final String label;
}

/// Camion confié à l'agent.
class Van {
  Van({required this.id, required this.name, this.plate});

  final String id;
  final String name;
  final String? plate;

  String get label => plate == null ? name : '$name · $plate';
}

/// Ligne de stock ou de mouvement : un produit et sa quantité (unités de base).
class StockLine {
  StockLine(this.product, this.quantity, {this.received});

  final CatalogProduct product;
  final num quantity;

  /// Quantité reçue à la confirmation (chargement).
  final num? received;

  factory StockLine.fromJson(Map<String, dynamic> j) => StockLine(
    CatalogProduct.fromJson({
      'id': j['productId'],
      'name': j['name'],
      'format': j['format'],
      'unit': j['unit'],
      'packagings': j['packagings'] ?? const [],
    }),
    j['quantity'] as num,
    received: j['received'] as num?,
  );
}

/// Chargement (dépôt → camion) ou retour (camion → dépôt) en attente.
class PendingMovement {
  PendingMovement({
    required this.id,
    required this.kind,
    required this.label,
    required this.fromName,
    required this.toName,
    required this.at,
    required this.lines,
    this.byName,
    this.note,
  });

  final String id;
  final String kind;
  final String label;
  final String? fromName;
  final String? toName;
  final DateTime at;
  final String? byName;
  final String? note;
  final List<StockLine> lines;

  bool get isLoad => kind == 'load';

  factory PendingMovement.fromJson(Map<String, dynamic> j) => PendingMovement(
    id: j['id'] as String,
    kind: j['kind'] as String,
    label: j['label'] as String? ?? '',
    fromName: j['fromName'] as String?,
    toName: j['toName'] as String?,
    at: DateTime.parse(j['occurredAt'] as String).toLocal(),
    byName: j['createdByName'] as String?,
    note: j['note'] as String?,
    lines: [
      for (final l in j['lines'] as List? ?? const [])
        StockLine.fromJson(l as Map<String, dynamic>),
    ],
  );
}

/// Journée de l'agent : ventes, encaissements, argent liquide à remettre.
class VanDay {
  const VanDay({
    this.salesCount = 0,
    this.salesAmount = 0,
    this.cash = 0,
    this.mobileMoney = 0,
    this.bank = 0,
    this.dueOnSales = 0,
    this.cashBalance = 0,
  });

  final int salesCount;
  final num salesAmount;
  final num cash;
  final num mobileMoney;
  final num bank;

  /// Reste dû sur les ventes du jour (crédit accordé).
  final num dueOnSales;

  /// Argent liquide encore entre les mains de l'agent (à remettre).
  final num cashBalance;

  factory VanDay.fromJson(Map<String, dynamic>? j) => j == null
      ? const VanDay()
      : VanDay(
          salesCount: (j['salesCount'] as num? ?? 0).toInt(),
          salesAmount: j['salesAmount'] as num? ?? 0,
          cash: j['cash'] as num? ?? 0,
          mobileMoney: j['mobileMoney'] as num? ?? 0,
          bank: j['bank'] as num? ?? 0,
          dueOnSales: j['dueOnSales'] as num? ?? 0,
          cashBalance: j['cashBalance'] as num? ?? 0,
        );
}

/// « Mon camion » tel que le voit le téléphone : la réponse du serveur, corrigée par ce qui
/// attend encore dans la file d'envoi (ventes et casses retirées, chargements reçus ajoutés).
class MyVan {
  MyVan({
    required this.van,
    required this.depots,
    required this.stock,
    required this.pending,
    required this.today,
    this.queued = 0,
  });

  /// null : aucun camion affecté à l'agent.
  final Van? van;
  final List<({String id, String name})> depots;
  final List<StockLine> stock;

  /// Chargements à confirmer, retours en attente d'un responsable.
  final List<PendingMovement> pending;
  final VanDay today;

  /// Ventes, casses, retours et réceptions pas encore envoyés.
  final int queued;

  num quantityOf(String productId) =>
      stock.where((s) => s.product.id == productId).firstOrNull?.quantity ?? 0;

  factory MyVan.fromJson(Map<String, dynamic> j) {
    final van = j['van'] as Map<String, dynamic>?;
    return MyVan(
      van: van == null
          ? null
          : Van(
              id: van['id'] as String,
              name: van['name'] as String,
              plate: van['plate'] as String?,
            ),
      depots: [
        for (final d in j['depots'] as List? ?? const [])
          (id: (d as Map)['id'] as String, name: d['name'] as String),
      ],
      stock: [
        for (final s in j['stock'] as List? ?? const [])
          StockLine.fromJson(s as Map<String, dynamic>),
      ],
      pending: [
        for (final m in j['pending'] as List? ?? const [])
          PendingMovement.fromJson(m as Map<String, dynamic>),
      ],
      today: VanDay.fromJson(j['today'] as Map<String, dynamic>?),
    );
  }

  /// Le même camion, une fois appliqué ce qui n'est pas encore envoyé.
  MyVan withQueue(List<PendingOutlet> queue) {
    final delta = <String, num>{};
    final confirmed = <String>{};
    var count = 0;
    for (final row in queue) {
      if (!const {
        'sale',
        'loss',
        'unload',
        'load_confirm',
      }.contains(row.kind)) {
        continue;
      }
      count++;
      final body = jsonDecode(row.bodyJson) as Map<String, dynamic>;
      // Un retour ne retire le stock qu'à la confirmation du responsable.
      if (row.kind == 'unload') continue;
      final sign = row.kind == 'load_confirm' ? 1 : -1;
      if (row.kind == 'load_confirm') {
        confirmed.add(body['movementId'] as String);
      }
      for (final l in body['lines'] as List? ?? const []) {
        final line = l as Map<String, dynamic>;
        final id = line['productId'] as String;
        final q = (line['received'] ?? line['quantity']) as num;
        delta[id] = (delta[id] ?? 0) + sign * q;
      }
    }
    if (count == 0) return this;
    // Produits arrivés par un chargement reçu sans réseau, absents du stock connu.
    final known = {for (final s in stock) s.product.id};
    final loaded = [
      for (final m in pending)
        if (confirmed.contains(m.id))
          for (final l in m.lines)
            if (!known.contains(l.product.id)) l.product,
    ];
    return MyVan(
      van: van,
      depots: depots,
      stock: [
        for (final s in stock)
          StockLine(s.product, s.quantity + (delta[s.product.id] ?? 0)),
        for (final p in {for (final p in loaded) p.id: p}.values)
          StockLine(p, delta[p.id] ?? 0),
      ],
      pending: [
        for (final m in pending)
          if (!confirmed.contains(m.id)) m,
      ],
      today: today,
      queued: count,
    );
  }
}

/// Réponse du serveur (gardée pour le hors ligne par le cache des réponses).
final _myVanServerProvider = FutureProvider.autoDispose<MyVan>(
  (ref) async => MyVan.fromJson(await ref.read(repositoryProvider).myVan()),
);

/// « Mon camion », file d'envoi comprise.
final myVanProvider = Provider.autoDispose<AsyncValue<MyVan>>((ref) {
  final server = ref.watch(_myVanServerProvider);
  final queue = ref.watch(pendingOutletsProvider).value ?? const [];
  return server.whenData((v) => v.withQueue(queue));
});

/// Recharge « Mon camion » depuis le serveur.
void refreshVan(WidgetRef ref) => ref.invalidate(_myVanServerProvider);

/// Ce que doit un point de vente et le crédit encore possible.
class OutletBalance {
  OutletBalance({
    required this.creditLimit,
    required this.outstanding,
    required this.advance,
    required this.available,
  });

  /// null : pas de vente à crédit pour ce client.
  final num? creditLimit;
  final num outstanding;
  final num advance;
  final num available;

  bool get creditAllowed => creditLimit != null;

  factory OutletBalance.fromJson(Map<String, dynamic> j) => OutletBalance(
    creditLimit: j['creditLimit'] as num?,
    outstanding: j['outstanding'] as num? ?? 0,
    advance: j['advance'] as num? ?? 0,
    available: j['available'] as num? ?? 0,
  );

  /// Corrigé par les ventes à crédit et les paiements pas encore envoyés.
  OutletBalance withQueue(String outletId, List<PendingOutlet> queue) {
    num credit = 0;
    num paid = 0;
    for (final row in queue) {
      if (row.outletId != outletId) continue;
      final body = jsonDecode(row.bodyJson) as Map<String, dynamic>;
      if (row.kind == 'sale') {
        credit +=
            (body['total'] as num? ?? 0) - (body['paidAmount'] as num? ?? 0);
      } else if (row.kind == 'payment') {
        paid += body['amount'] as num? ?? 0;
      }
    }
    if (credit == 0 && paid == 0) return this;
    final owed = outstanding + credit - paid;
    return OutletBalance(
      creditLimit: creditLimit,
      outstanding: owed < 0 ? 0 : owed,
      advance: advance,
      available: creditLimit == null
          ? 0
          : (creditLimit! - owed + advance).clamp(0, double.infinity),
    );
  }
}

final _balanceServerProvider = FutureProvider.autoDispose
    .family<OutletBalance, String>(
      (ref, outletId) async => OutletBalance.fromJson(
        await ref.read(repositoryProvider).outletBalance(outletId),
      ),
    );

final outletBalanceProvider = Provider.autoDispose
    .family<AsyncValue<OutletBalance>, String>((ref, outletId) {
      final server = ref.watch(_balanceServerProvider(outletId));
      final queue = ref.watch(pendingOutletsProvider).value ?? const [];
      return server.whenData((b) => b.withQueue(outletId, queue));
    });

/// Enregistre l'action sur le téléphone puis l'envoie aussitôt : envoyée (réponse du
/// serveur) ou en attente du réseau. Un refus remonte en ApiException.
Future<(SubmitOutcome, Map<String, dynamic>?)> _queue(
  WidgetRef ref, {
  required String kind,
  required String name,
  required Map<String, dynamic> body,
  String? outletId,
}) async {
  final db = ref.read(databaseProvider);
  final clientId = const Uuid().v4();
  await db
      .into(db.pendingOutlets)
      .insert(
        PendingOutletsCompanion.insert(
          clientId: clientId,
          kind: kind,
          outletId: Value(outletId),
          name: name,
          bodyJson: jsonEncode(body),
          createdAt: DateTime.now().toUtc(),
        ),
      );
  final result = await ref.read(syncProvider).sendOutletNow(clientId);
  ref.invalidate(_myVanServerProvider);
  if (outletId != null) {
    ref.invalidate(_balanceServerProvider(outletId));
    ref.invalidate(outletOrdersProvider(outletId));
  }
  return result;
}

/// Vente directe : la quantité vendue sort du camion ; payée en tout ou partie, le reste à
/// crédit. `total` sert seulement au calcul du crédit hors ligne (le serveur recalcule).
Future<(SubmitOutcome, OrderItem?)> sendSale(
  WidgetRef ref, {
  required String outletId,
  required String outletName,
  required Map<String, num> quantities,
  required num total,
  required num paidAmount,
  PaymentMethod? method,

  /// Vente d'urgence chez un client hors de la zone de l'agent : motif obligatoire.
  String? outOfZoneReason,
}) async {
  // Hors zone : le serveur vérifie que l'agent est sur place, il faut une position fraîche.
  final tracker = ref.read(trackerProvider);
  final position = outOfZoneReason != null
      ? await tracker.freshPosition()
      : await tracker.lastKnown();
  final (outcome, json) = await _queue(
    ref,
    kind: 'sale',
    outletId: outletId,
    name: 'Vente · $outletName',
    body: {
      'outletId': outletId,
      'lines': [
        for (final e in quantities.entries)
          {'productId': e.key, 'quantity': e.value},
      ],
      'paidAmount': paidAmount,
      if (paidAmount > 0 && method != null) 'paymentMethod': method.code,
      'total': total,
      'lat': ?position?.latitude,
      'lng': ?position?.longitude,
      if (outOfZoneReason != null) ...{
        'outOfZoneReason': outOfZoneReason,
        'accuracy': ?position?.accuracy,
      },
      'soldAt': DateTime.now().toUtc().toIso8601String(),
    },
  );
  return (outcome, json == null ? null : OrderItem.fromJson(json));
}

/// Paiement reçu d'un client : il règle ses ventes dues, les plus anciennes d'abord.
Future<SubmitOutcome> sendPayment(
  WidgetRef ref, {
  required String outletId,
  required String outletName,
  required num amount,
  required PaymentMethod method,
}) async => (await _queue(
  ref,
  kind: 'payment',
  outletId: outletId,
  name: 'Paiement · $outletName',
  body: {
    'outletId': outletId,
    'amount': amount,
    'method': method.code,
    'receivedAt': DateTime.now().toUtc().toIso8601String(),
  },
)).$1;

/// Casse, perte, vol : sort du camion aussitôt (motif obligatoire).
Future<SubmitOutcome> sendLoss(
  WidgetRef ref, {
  required Map<String, num> quantities,
  required String reason,
}) async => (await _queue(
  ref,
  kind: 'loss',
  name: 'Casse ou perte',
  body: {
    'lines': [
      for (final e in quantities.entries)
        {'productId': e.key, 'quantity': e.value},
    ],
    'note': reason,
    'occurredAt': DateTime.now().toUtc().toIso8601String(),
  },
)).$1;

/// Retour au dépôt : un responsable le confirme à l'arrivée.
Future<SubmitOutcome> sendUnload(
  WidgetRef ref, {
  required String depotId,
  required Map<String, num> quantities,
  String? note,
}) async => (await _queue(
  ref,
  kind: 'unload',
  name: 'Retour au dépôt',
  body: {
    'depotId': depotId,
    'lines': [
      for (final e in quantities.entries)
        {'productId': e.key, 'quantity': e.value},
    ],
    if (note != null && note.isNotEmpty) 'note': note,
  },
)).$1;

/// Réception d'un chargement, avec les quantités réellement reçues.
Future<SubmitOutcome> confirmLoad(
  WidgetRef ref, {
  required PendingMovement movement,
  required Map<String, num> received,
  String? note,
}) async => (await _queue(
  ref,
  kind: 'load_confirm',
  name: 'Réception du chargement',
  body: {
    'movementId': movement.id,
    'lines': [
      for (final l in movement.lines)
        {
          'productId': l.product.id,
          'received': received[l.product.id] ?? l.quantity,
        },
    ],
    if (note != null && note.isNotEmpty) 'note': note,
  },
)).$1;

/// Partage d'un fichier (WhatsApp, SMS…) ; remplacé dans les tests.
abstract class FileSharer {
  Future<void> sharePdf(Uint8List bytes, String filename, String text);
}

class _SystemSharer implements FileSharer {
  @override
  Future<void> sharePdf(Uint8List bytes, String filename, String text) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: 'application/pdf', name: filename),
        ],
        fileNameOverrides: [filename],
        text: text,
      ),
    );
  }
}

final fileSharerProvider = Provider<FileSharer>((_) => _SystemSharer());

/// Télécharge le reçu PDF puis ouvre le partage du téléphone.
Future<void> shareReceipt(
  WidgetRef ref, {
  required String orderId,
  required String reference,
  required String outletName,
}) async {
  final bytes = await ref.read(repositoryProvider).receiptPdf(orderId);
  await ref
      .read(fileSharerProvider)
      .sharePdf(
        Uint8List.fromList(bytes),
        'recu-$reference.pdf',
        'Reçu $reference · $outletName',
      );
}
