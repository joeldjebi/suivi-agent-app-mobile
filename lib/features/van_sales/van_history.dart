import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../orders/orders.dart';
import 'transfers.dart';

/// Onglets de l'historique du camion.
enum VanHistoryTab {
  sales('sales', 'Ventes'),
  loads('loads', 'Approvisionnements'),
  transfers('transfers', 'Dépannages'),
  losses('losses', 'Casse ou perte'),
  unloads('unloads', 'Retours au dépôt');

  const VanHistoryTab(this.code, this.label);

  final String code;
  final String label;

  static VanHistoryTab from(String? code) =>
      values.firstWhere((t) => t.code == code, orElse: () => sales);

  /// Opérations de la file d'envoi qui appartiennent à cet onglet.
  String? get queueKind => switch (this) {
    sales => 'sale',
    losses => 'loss',
    unloads => 'unload',
    _ => null,
  };
}

/// Période de l'historique, commune à tous les onglets (dates du téléphone, incluses).
class HistoryPeriod {
  const HistoryPeriod._(this.kind, this.from, this.to);

  /// today, week, month, custom
  final String kind;
  final DateTime from;
  final DateTime to;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  factory HistoryPeriod.today([DateTime? now]) {
    final d = _day(now ?? DateTime.now());
    return HistoryPeriod._('today', d, d);
  }

  /// Les 7 derniers jours, aujourd'hui compris (par défaut).
  factory HistoryPeriod.week([DateTime? now]) {
    final d = _day(now ?? DateTime.now());
    return HistoryPeriod._('week', d.subtract(const Duration(days: 6)), d);
  }

  factory HistoryPeriod.month([DateTime? now]) {
    final d = _day(now ?? DateTime.now());
    return HistoryPeriod._('month', d.subtract(const Duration(days: 29)), d);
  }

  factory HistoryPeriod.custom(DateTime from, DateTime to) =>
      HistoryPeriod._('custom', _day(from), _day(to));

  String get label => switch (kind) {
    'today' => 'Aujourd’hui',
    'week' => '7 derniers jours',
    'month' => '30 derniers jours',
    _ =>
      from == to
          ? DateFormat('d MMM y', 'fr_FR').format(from)
          : '${DateFormat('d MMM', 'fr_FR').format(from)} → ${DateFormat('d MMM', 'fr_FR').format(to)}',
  };

  static final _iso = DateFormat('yyyy-MM-dd');
  String get fromIso => _iso.format(from);
  String get toIso => _iso.format(to);

  @override
  bool operator ==(Object other) =>
      other is HistoryPeriod &&
      other.kind == kind &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(kind, from, to);
}

/// Filtres d'un onglet. [status] : pending/done/cancelled (approvisionnements, retours),
/// open/finished (dépannages) ; [payment] : paid/credit/cancelled (ventes) ;
/// [direction] : received/given (dépannages).
class HistoryFilters {
  const HistoryFilters({
    this.productId,
    this.productName,
    this.outletId,
    this.outletName,
    this.payment,
    this.status,
    this.direction,
  });

  final String? productId;
  final String? productName;
  final String? outletId;
  final String? outletName;
  final String? payment;
  final String? status;
  final String? direction;

  bool get isActive =>
      productId != null ||
      outletId != null ||
      payment != null ||
      status != null ||
      direction != null;

  HistoryFilters copyWith({
    (String?, String?)? product,
    (String?, String?)? outlet,
    (String?,)? payment,
    (String?,)? status,
    (String?,)? direction,
  }) => HistoryFilters(
    productId: product == null ? productId : product.$1,
    productName: product == null ? productName : product.$2,
    outletId: outlet == null ? outletId : outlet.$1,
    outletName: outlet == null ? outletName : outlet.$2,
    payment: payment == null ? this.payment : payment.$1,
    status: status == null ? this.status : status.$1,
    direction: direction == null ? this.direction : direction.$1,
  );

  @override
  bool operator ==(Object other) =>
      other is HistoryFilters &&
      other.productId == productId &&
      other.outletId == outletId &&
      other.payment == payment &&
      other.status == status &&
      other.direction == direction;

  @override
  int get hashCode =>
      Object.hash(productId, outletId, payment, status, direction);
}

/// Une page demandée : onglet, période, filtres, nombre de lignes chargées.
class HistoryQuery {
  const HistoryQuery({
    required this.tab,
    required this.period,
    this.filters = const HistoryFilters(),
    this.limit = pageSize,
  });

  static const pageSize = 30;

  final VanHistoryTab tab;
  final HistoryPeriod period;
  final HistoryFilters filters;
  final int limit;

  Map<String, dynamic> toQuery() => {
    'type': tab.code,
    'from': period.fromIso,
    'to': period.toIso,
    'limit': limit,
    'productId': ?filters.productId,
    if (tab == VanHistoryTab.sales) ...{
      'outletId': ?filters.outletId,
      'payment': ?filters.payment,
    },
    if (tab != VanHistoryTab.sales && tab != VanHistoryTab.losses)
      'status': ?filters.status,
    if (tab == VanHistoryTab.transfers) 'direction': ?filters.direction,
  };

  @override
  bool operator ==(Object other) =>
      other is HistoryQuery &&
      other.tab == tab &&
      other.period == period &&
      other.filters == filters &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(tab, period, filters, limit);
}

/// Produit d'un total de la période (quantités en unités de base).
class HistoryProduct {
  const HistoryProduct(
    this.product, {
    this.quantity = 0,
    this.received = 0,
    this.given = 0,
  });

  final CatalogProduct product;
  final num quantity;

  /// Dépannages : reçu sur mes demandes, donné aux collègues.
  final num received;
  final num given;

  factory HistoryProduct.fromJson(Map<String, dynamic> j) => HistoryProduct(
    CatalogProduct.fromJson({
      'id': j['productId'],
      'name': j['name'] ?? 'Produit',
      'unit': j['unit'],
      'packagings': j['packagings'],
    }),
    quantity: j['quantity'] as num? ?? 0,
    received: j['received'] as num? ?? 0,
    given: j['given'] as num? ?? 0,
  );
}

/// Mouvement du camion : chargement, casse ou perte, retour au dépôt.
class HistoryMovement {
  const HistoryMovement({
    required this.id,
    required this.kind,
    required this.status,
    required this.at,
    required this.lines,
    this.fromName,
    this.toName,
    this.note,
    this.createdByName,
    this.confirmedByName,
    this.confirmedAt,
  });

  final String id;

  /// load, loss, unload
  final String kind;

  /// pending, done, cancelled
  final String status;
  final DateTime at;
  final String? fromName;
  final String? toName;
  final String? note;
  final String? createdByName;
  final String? confirmedByName;
  final DateTime? confirmedAt;
  final List<({CatalogProduct product, num quantity, num? received})> lines;

  /// Quantité qui compte : la reçue une fois confirmée.
  static num counted(
    ({CatalogProduct product, num quantity, num? received}) l,
  ) => l.received ?? l.quantity;

  String get summary => lines
      .map((l) => '${formatQty(counted(l))} × ${l.product.label}')
      .join(', ');

  factory HistoryMovement.fromJson(Map<String, dynamic> j) => HistoryMovement(
    id: j['id'] as String,
    kind: j['kind'] as String,
    status: j['status'] as String,
    at: DateTime.parse(j['occurredAt'] as String).toLocal(),
    fromName: j['fromName'] as String?,
    toName: j['toName'] as String?,
    note: j['note'] as String?,
    createdByName: j['createdByName'] as String?,
    confirmedByName: j['confirmedByName'] as String?,
    confirmedAt: j['confirmedAt'] == null
        ? null
        : DateTime.parse(j['confirmedAt'] as String).toLocal(),
    lines: [
      for (final l in j['lines'] as List? ?? const [])
        (
          product: CatalogProduct.fromJson({
            'id': (l as Map)['productId'],
            'name': l['name'] ?? 'Produit',
            'unit': l['unit'],
            'packagings': l['packagings'],
          }),
          quantity: l['quantity'] as num,
          received: l['received'] as num?,
        ),
    ],
  );
}

/// Totaux de la période. Ventes : [count], [amount], [paid], [credit], [cancelled] ;
/// mouvements : [count] et [products] ; dépannages : [requested], [helped], [products].
class HistorySummary {
  const HistorySummary({
    this.count = 0,
    this.amount = 0,
    this.paid = 0,
    this.credit = 0,
    this.cancelled = 0,
    this.currency = 'XOF',
    this.requested = 0,
    this.helped = 0,
    this.products = const [],
  });

  final int count;
  final num amount;
  final num paid;
  final num credit;
  final int cancelled;
  final String currency;
  final int requested;
  final int helped;
  final List<HistoryProduct> products;

  factory HistorySummary.fromJson(Map<String, dynamic>? j) => j == null
      ? const HistorySummary()
      : HistorySummary(
          count: (j['count'] as num? ?? 0).toInt(),
          amount: j['amount'] as num? ?? 0,
          paid: j['paid'] as num? ?? 0,
          credit: j['credit'] as num? ?? 0,
          cancelled: (j['cancelled'] as num? ?? 0).toInt(),
          currency: j['currency'] as String? ?? 'XOF',
          requested: (j['requested'] as num? ?? 0).toInt(),
          helped: (j['helped'] as num? ?? 0).toInt(),
          products: [
            for (final p in j['products'] as List? ?? const [])
              HistoryProduct.fromJson(p as Map<String, dynamic>),
          ],
        );
}

/// Une page de l'historique : selon l'onglet, des ventes, des mouvements ou des dépannages.
class HistoryPage {
  const HistoryPage({
    required this.total,
    required this.summary,
    this.sales = const [],
    this.movements = const [],
    this.transfers = const [],
  });

  final int total;
  final HistorySummary summary;
  final List<OrderItem> sales;
  final List<HistoryMovement> movements;

  /// Dépannage et sens : « received » (ma demande) ou « given » (ma part).
  final List<({Transfer transfer, bool given})> transfers;

  int get loaded => sales.length + movements.length + transfers.length;

  factory HistoryPage.fromJson(VanHistoryTab tab, Map<String, dynamic> j) {
    final items = (j['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return HistoryPage(
      total: (j['total'] as num? ?? 0).toInt(),
      summary: HistorySummary.fromJson(j['summary'] as Map<String, dynamic>?),
      sales: tab == VanHistoryTab.sales
          ? [for (final i in items) OrderItem.fromJson(i)]
          : const [],
      transfers: tab == VanHistoryTab.transfers
          ? [
              for (final i in items)
                (
                  transfer: Transfer.fromJson(i),
                  given: i['direction'] == 'given',
                ),
            ]
          : const [],
      movements: tab == VanHistoryTab.sales || tab == VanHistoryTab.transfers
          ? const []
          : [for (final i in items) HistoryMovement.fromJson(i)],
    );
  }
}

/// Une page de l'historique (gardée hors ligne par le cache des réponses).
final vanHistoryProvider = FutureProvider.autoDispose
    .family<HistoryPage, HistoryQuery>(
      (ref, q) async => HistoryPage.fromJson(
        q.tab,
        await ref.read(repositoryProvider).vanHistory(q.toQuery()),
      ),
    );
