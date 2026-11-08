import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../orders/orders.dart';
import 'van_sales.dart';

/// Préfixe du contenu du code QR d'une demande de dépannage.
const transferQrPrefix = 'performx:depannage:';

/// Dépannage partagé entre camions : la demande, ses quantités, les parts des collègues.
class Transfer {
  const Transfer({
    required this.id,
    required this.status,
    required this.statusLabel,
    required this.requesterId,
    required this.requesterName,
    required this.createdAt,
    required this.lines,
    required this.legs,
    this.note,
    this.token,
    this.needsApproval = false,
    this.myStock = const {},
    this.distanceM,
  });

  final String id;

  /// open, covered, done, closed, expired
  final String status;
  final String statusLabel;
  final String requesterId;
  final String requesterName;
  final DateTime createdAt;
  final String? note;
  final List<TransferLine> lines;
  final List<TransferLeg> legs;

  /// Code à montrer aux collègues (QR) : seulement au demandeur.
  final String? token;

  /// Demande d'une autre équipe : ma part attendra l'accord de mon chef.
  final bool needsApproval;

  /// Mon stock des produits encore à trouver (liste « autour de moi »).
  final Map<String, num> myStock;
  final int? distanceM;

  bool get isOpen => status == 'open' || status == 'covered';

  List<TransferLine> get missing =>
      lines.where((l) => l.remaining > 0).toList();

  factory Transfer.fromJson(Map<String, dynamic> j) => Transfer(
    id: j['id'] as String,
    status: j['status'] as String,
    statusLabel: j['statusLabel'] as String? ?? '',
    requesterId: j['requesterId'] as String,
    requesterName: j['requesterName'] as String? ?? '',
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    note: j['note'] as String?,
    token: j['token'] as String?,
    needsApproval: j['needsApproval'] as bool? ?? false,
    distanceM: (j['distanceM'] as num?)?.round(),
    myStock: {
      for (final e in ((j['myStock'] as Map?) ?? const {}).entries)
        e.key as String: e.value as num,
    },
    lines: [
      for (final l in j['lines'] as List? ?? const [])
        TransferLine.fromJson(l as Map<String, dynamic>),
    ],
    legs: [
      for (final l in j['legs'] as List? ?? const [])
        TransferLeg.fromJson(l as Map<String, dynamic>),
    ],
  );
}

class TransferLine {
  const TransferLine({
    required this.productId,
    required this.name,
    required this.requested,
    required this.reserved,
    required this.given,
    required this.remaining,
  });

  final String productId;
  final String name;
  final num requested;
  final num reserved;
  final num given;
  final num remaining;

  factory TransferLine.fromJson(Map<String, dynamic> j) => TransferLine(
    productId: j['productId'] as String,
    name: j['name'] as String? ?? 'Produit',
    requested: j['requested'] as num? ?? 0,
    reserved: j['reserved'] as num? ?? 0,
    given: j['given'] as num? ?? 0,
    remaining: j['remaining'] as num? ?? 0,
  );
}

class TransferLeg {
  const TransferLeg({
    required this.id,
    required this.giverId,
    required this.giverName,
    required this.status,
    required this.statusLabel,
    required this.lines,
    this.crossTeam = false,
    this.expiresAt,
  });

  final String id;
  final String giverId;
  final String giverName;

  /// approval, accepted, done, released, rejected
  final String status;
  final String statusLabel;
  final bool crossTeam;
  final List<({String productId, String name, num quantity})> lines;
  final DateTime? expiresAt;

  bool get isActive => status == 'approval' || status == 'accepted';

  String get summary =>
      lines.map((l) => '${formatQty(l.quantity)} × ${l.name}').join(', ');

  factory TransferLeg.fromJson(Map<String, dynamic> j) => TransferLeg(
    id: j['id'] as String,
    giverId: j['giverId'] as String,
    giverName: j['giverName'] as String? ?? '',
    status: j['status'] as String,
    statusLabel: j['statusLabel'] as String? ?? '',
    crossTeam: j['crossTeam'] as bool? ?? false,
    expiresAt: j['expiresAt'] == null
        ? null
        : DateTime.parse(j['expiresAt'] as String).toLocal(),
    lines: [
      for (final l in j['lines'] as List? ?? const [])
        (
          productId: (l as Map)['productId'] as String,
          name: l['name'] as String? ?? 'Produit',
          quantity: l['quantity'] as num,
        ),
    ],
  );
}

/// « 24 », « 1,5 ».
String formatQty(num n) => n == n.roundToDouble()
    ? n.round().toString()
    : n.toString().replaceAll('.', ',');

/// Mes demandes et mes parts en cours.
final myTransfersProvider = FutureProvider.autoDispose<List<Transfer>>(
  (ref) async => [
    for (final t in await ref.read(repositoryProvider).transfers())
      Transfer.fromJson(t as Map<String, dynamic>),
  ],
);

/// Demandes de collègues que je peux aider.
final nearbyTransfersProvider = FutureProvider.autoDispose<List<Transfer>>(
  (ref) async => [
    for (final t in await ref.read(repositoryProvider).nearbyTransfers())
      Transfer.fromJson(t as Map<String, dynamic>),
  ],
);

/// Produits de la structure (ce qu'on peut demander).
final ownProductsProvider = FutureProvider.autoDispose<List<CatalogProduct>>(
  (ref) async => [
    for (final p in await ref.read(repositoryProvider).products(side: 'own'))
      CatalogProduct.fromJson(p as Map<String, dynamic>),
  ],
);

/// Recharge les dépannages et le camion.
void refreshTransfers(WidgetRef ref) {
  ref.invalidate(myTransfersProvider);
  ref.invalidate(nearbyTransfersProvider);
  refreshVan(ref);
}

/// Client hors zone choisi : nom, prix et crédit.
class OutOfZoneContext {
  const OutOfZoneContext({
    required this.name,
    required this.catalog,
    required this.balance,
    this.zoneName,
  });

  final String name;
  final String? zoneName;
  final OrderCatalog catalog;
  final OutletBalance balance;
}

final outOfZoneContextProvider = FutureProvider.autoDispose
    .family<OutOfZoneContext, String>((ref, outletId) async {
      final j = await ref.read(repositoryProvider).outOfZoneContext(outletId);
      final outlet = j['outlet'] as Map<String, dynamic>;
      return OutOfZoneContext(
        name: outlet['name'] as String,
        zoneName: outlet['zoneName'] as String?,
        catalog: OrderCatalog.fromJson(j['catalog'] as Map<String, dynamic>),
        balance: OutletBalance.fromJson(j['balance'] as Map<String, dynamic>),
      );
    });

/// Lecture d'un code QR (remplacée dans les tests).
abstract interface class CodeScanner {
  /// Contenu lu, ou null si l'agent annule.
  Future<String?> scan(BuildContext context);
}

/// Appareil photo du téléphone (ou de l'ordinateur sur la version web).
class CameraCodeScanner implements CodeScanner {
  @override
  Future<String?> scan(BuildContext context) => Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
}

final codeScannerProvider = Provider<CodeScanner>((_) => CameraCodeScanner());

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scanner le code du collègue')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final value = capture.barcodes
                .map((b) => b.rawValue)
                .whereType<String>()
                .firstOrNull;
            if (value == null || _done) return;
            _done = true;
            Navigator.of(context).pop(value);
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Appareil photo indisponible : autorisez-le dans les réglages du téléphone.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Visez le code affiché sur le téléphone du collègue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}
