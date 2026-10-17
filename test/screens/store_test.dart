@Tags(['store'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivi_agent/core/models.dart';
import 'package:suivi_agent/design/components.dart';
import 'package:suivi_agent/features/team/team_map_screen.dart'
    show mapTileSourceProvider;

import '../fakes.dart';
import '../outlet_fakes.dart';

/// Écrans pour les captures des stores : rendus en haute définition (× 3, 1170 × 2532) avec
/// des données de démonstration réalistes (marques inventées), dans build/store/.
/// Fond de carte : tuiles OpenStreetMap enregistrées dans build/store/tiles/{z}/{x}/{y}.png.
/// TZ=Etc/GMT±n (il est un peu plus de 7 h) flutter test test/screens/store_test.dart --tags store --run-skipped
Future<void> _loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans')
    ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
  await jakarta.load();
  final root = Platform.environment['FLUTTER_ROOT']!;
  final bytes = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytesSync();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await icons.load();
}

/// Tuiles enregistrées à l'avance (pas de réseau pendant les tests).
class _SavedTiles extends TileProvider {
  static final _blank = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  @override
  ImageProvider getImage(TileCoordinates c, TileLayer options) {
    final file = File('build/store/tiles/${c.z}/${c.x}/${c.y}.png');
    return MemoryImage(file.existsSync() ? file.readAsBytesSync() : _blank);
  }
}

Future<void> _pumps(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// STORE_DEVICE=ipad : écrans iPad 13 pouces (2064 × 2752), dans build/store/ipad/.
final _ipad = Platform.environment['STORE_DEVICE'] == 'ipad';
final _whole = GlobalKey();

Future<void> _shoot(
  WidgetTester tester,
  Widget app,
  String name,
  Future<void> Function() then,
) async {
  tester.view.physicalSize = _ipad
      ? const Size(2064, 2752)
      : const Size(1170, 2532);
  tester.view.devicePixelRatio = _ipad ? 2 : 3;
  addTearDown(tester.view.reset);
  // iPad : toute l'app (colonne centrée et côtés), pas seulement l'écran.
  await tester.pumpWidget(
    _ipad ? RepaintBoundary(key: _whole, child: app) : app,
  );
  await _pumps(tester);
  await then();
  await _pumps(tester);
  // Images (tuiles) : décodées hors du temps simulé.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await _pumps(tester);
  }
  var render = tester.renderObject(
    _ipad ? find.byKey(_whole) : find.byType(Scaffold).first,
  );
  while (render is! RenderRepaintBoundary) {
    render = render.parent!;
  }
  final boundary = render;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ipad ? 2 : 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/store/${_ipad ? 'ipad/' : ''}$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Produits de démonstration : marques inventées.
Map<String, dynamic> _product(
  String id,
  String name,
  String format, {
  bool own = true,
}) => {
  'id': id,
  'name': name,
  'format': format,
  'own': own,
  'unit': 'Bouteille',
  'packagings': [
    {'name': 'Casier', 'units': 12},
  ],
};

final _products = [
  _product('p1', 'Lagune Blonde', '65 cl'),
  _product('p2', 'Malta Soleil', '33 cl'),
  _product('p3', 'Eau Cascade', '1,5 L'),
  _product('c1', 'Brune du Port', '65 cl', own: false),
];

/// La journée de démonstration : des points de vente au Plateau, une tournée, un relevé
/// récent (nos produits et la concurrence), des visites.
class StoreRepo extends ActivityRepo {
  StoreRepo() {
    outletList
      ..clear()
      ..addAll([
        outletJson(
          'o1',
          'Boutique Awa',
          status: 'active',
          distance: 12,
          daysSinceVisit: 2,
          lat: 5.3232,
          lng: -4.0168,
        ),
        outletJson(
          'o2',
          'Maquis Chez Tantie Rose',
          category: 'Maquis / Bar',
          status: 'prospect',
          distance: 820,
          overdue: true,
          daysSinceVisit: 35,
          lat: 5.3268,
          lng: -4.0142,
        ),
        outletJson(
          'o4',
          'Supérette du Lycée',
          category: 'Supérette',
          status: 'active',
          distance: 1300,
          overdue: true,
          daysSinceVisit: 33,
          lat: 5.3305,
          lng: -4.0186,
        ),
        outletJson(
          'o5',
          'Cave Le Bon Goût',
          category: 'Cave',
          status: 'new',
          distance: 1700,
          lat: 5.3281,
          lng: -4.0236,
        ),
      ]);
    Map<String, dynamic> reading(
      Map<String, dynamic> p, {
      int? stock,
      int? price,
    }) => {
      'productId': p['id'],
      'name': p['name'],
      'format': p['format'],
      'own': p['own'],
      'unit': 'Bouteille',
      'packagings': p['packagings'],
      'last': {
        'at': '2026-10-14T09:30:00.000Z',
        'presence': stock != null,
        'stock': stock,
        'price': price,
      },
      'stockHistory': <dynamic>[],
    };
    outletReadingsJson = [
      reading(_products[0], stock: 30, price: 650),
      reading(_products[1], stock: 18, price: 400),
      reading(_products[2]),
      reading(_products[3], stock: 24, price: 700),
      reading(_product('c2', 'Tonic Royal', '33 cl', own: false)),
    ];
    visitsJson = [
      for (final v in visitsJson)
        {...v, 'status': 'accepted', 'agent': 'Koffi Brou'},
    ];
    // Journée en cours depuis 7 h 45, dans la zone du Plateau.
    day = DayState(
      day: WorkDay(
        id: 'd1',
        status: DayStatus.active,
        zoneId: 'z1',
        // Le rendu se lance avec un fuseau où il est un peu plus de 7 h (voir TZ).
        startedAt: DateTime.now().subtract(const Duration(minutes: 12)),
        endedAt: null,
        pausedSeconds: 0,
        currentPauseStartedAt: null,
      ),
      approved: ZoneRequest(
        id: 'r1',
        zoneId: 'z1',
        status: RequestStatus.approved,
        expiresAt: null,
        isChange: false,
      ),
    );
    formStatsJson = {
      'forms': [
        {
          'id': 't1',
          'name': 'Relevé produits',
          'submissions': 86,
          'outlets': 24,
        },
        {'id': 't2', 'name': 'Prospection', 'submissions': 12, 'outlets': 9},
      ],
    };
    orderCatalogJson = {
      'priceList': {'id': 'pl1', 'name': 'Détaillant'},
      'currency': 'XOF',
      'products': [
        for (final (p, price) in [
          (_products[0], 650),
          (_products[1], 400),
          (_products[2], 350),
          (_product('p4', 'Lagune Radler', '33 cl'), 500),
        ])
          {...p, 'category': 'Boissons', 'price': price},
      ],
    };
  }

  /// Relevés du mois : ruptures, ventes déclarées, concurrence.
  @override
  Future<Map<String, dynamic>> productInsights(
    String part, {
    required String from,
    required String to,
  }) async {
    Map<String, dynamic> sale(Map<String, dynamic> p, int sold, int outlets) =>
        {
          'productId': p['id'],
          'name': p['name'],
          'format': p['format'],
          'own': p['own'],
          'unit': 'Bouteille',
          'packagings': p['packagings'],
          'sold': sold,
          'losses': 0,
          'ordered': 0,
          'outlets': outlets,
        };
    return switch (part) {
      'overview' => {
        'visits': 86,
        'outlets': 24,
        'products': 6,
        'ownStockouts': 9,
        'ownChecked': 112,
        'stockoutRate': 8,
        'ownSold': 2280,
        'competitorSold': 1340,
        'ownLosses': 0,
      },
      'stockouts' => {
        'byProduct': [
          {
            'productId': 'p3',
            'name': 'Eau Cascade',
            'format': '1,5 L',
            'own': true,
            'checked': 24,
            'stockouts': 6,
            'rate': 25,
          },
          {
            'productId': 'p2',
            'name': 'Malta Soleil',
            'format': '33 cl',
            'own': true,
            'checked': 22,
            'stockouts': 3,
            'rate': 14,
          },
        ],
        'outlets': [
          for (final (p, outlet, zone) in [
            (_products[2], 'Boutique Awa', 'Plateau'),
            (_products[2], 'Supérette du Lycée', 'Plateau'),
            (_products[1], 'Maquis Chez Tantie Rose', 'Plateau'),
          ])
            {
              'productId': p['id'],
              'productName': p['name'],
              'format': p['format'],
              'own': true,
              'outletId': 'o1',
              'outletName': outlet,
              'zone': zone,
              'since': '2026-10-14T09:30:00.000Z',
              'lat': 5.3232,
              'lng': -4.0168,
              'agent': 'Koffi Brou',
            },
        ],
      },
      'sales' => {
        'products': [
          sale(_products[0], 1104, 21),
          sale(_products[3], 860, 18),
          sale(_products[1], 696, 17),
        ],
        'lossOutlets': <dynamic>[],
      },
      _ => {
        'products': <dynamic>[],
        'categories': [
          {
            'category': 'Boissons',
            'own': 2280,
            'competitor': 1340,
            'gapPercent': 70,
          },
        ],
      },
    };
  }

  /// Un mois de ventes de l'agent (commandes livrées ou payées).
  @override
  Future<Map<String, dynamic>> ordersSummary({
    required String from,
    required String to,
  }) async => {
    'currency': 'XOF',
    'count': 64,
    'amount': 1284500,
    'toCollect': 186000,
    'byStatus': {
      'taken': {'count': 3, 'amount': 52400},
      'delivered': {'count': 9, 'amount': 186000},
      'paid': {'count': 52, 'amount': 1046100},
      'cancelled': {'count': 2, 'amount': 31200},
    },
  };

  @override
  Future<Map<String, dynamic>> soldProducts({
    required String from,
    required String to,
  }) async => {
    'currency': 'XOF',
    'products': [
      for (final (p, quantity, price, outlets) in [
        (_products[0], 1104, 650, 21),
        (_products[1], 696, 400, 17),
        (_product('p4', 'Lagune Radler', '33 cl'), 312, 500, 9),
        (_products[2], 168, 350, 6),
      ])
        {
          'productId': p['id'],
          'name': p['name'],
          'format': p['format'],
          'unit': 'Bouteille',
          'packagings': p['packagings'],
          'quantity': quantity,
          'amount': quantity * price,
          'outlets': outlets,
        },
    ],
  };

  Map<String, dynamic> get _mission => {
    'id': 'm1',
    'title': 'Tournée relevé Plateau',
    'status': 'in_progress',
    'progressMethod': 'count',
    'dueDate': DateTime.now()
        .add(const Duration(days: 2))
        .toUtc()
        .toIso8601String(),
    'progress': {'current': 6, 'target': 20, 'percent': 30},
    'type': {
      'name': 'Relevé produits',
      'fields': [
        {
          'key': 'releve',
          'label': 'Relevé des produits',
          'type': 'products',
          'required': true,
          'products': {
            'scope': 'all',
            'measures': ['presence', 'stock', 'price'],
          },
        },
      ],
    },
    'products': {'releve': _products},
  };

  @override
  Future<List<Map<String, dynamic>>> missionsJson() async => [_mission];

  @override
  Future<Map<String, dynamic>> missionJson(String id) async => _mission;

  @override
  Future<Map<String, dynamic>> outletRoute({
    required double lat,
    required double lng,
    String? missionId,
  }) async {
    final legs = [480, 520, 610, 560];
    var total = 0;
    return {
      'source': 'overdue',
      'candidates': 4,
      'stops': [
        for (final (i, o) in outletList.indexed)
          {
            ...o,
            'order': i + 1,
            'legMeters': legs[i],
            'cumulativeMeters': total += legs[i],
          },
      ],
      'totalMeters': 2170,
      'travelMinutes': 29,
      'visitMinutes': 40,
    };
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await _loadFonts();
  });

  Finder tab(String label) =>
      find.descendant(of: find.byType(AppNavBar), matching: find.text(label));

  Widget app() => testApp(
    auth: () => SignedInAuth(
      fakeMe(
        features: {...auditFeatures, ...orderFeatures},
        submissionRequiresDay: false,
      ),
    ),
    repo: StoreRepo(),
    mapTiles: true,
    overrides: [mapTileSourceProvider.overrideWithValue(_SavedTiles())],
  );

  testWidgets('journée', (tester) async {
    await _shoot(tester, app(), '01-journee', () async {});
  }, skip: true);

  testWidgets('tournée', (tester) async {
    await _shoot(tester, app(), '02-tournee', () async {
      await tester.tap(tab('Points de vente'));
      await _pumps(tester);
      await tester.tap(find.text('Ma tournée'));
    });
  }, skip: true);

  testWidgets('fiche point de vente', (tester) async {
    await _shoot(tester, app(), '03-fiche-point-de-vente', () async {
      await tester.tap(tab('Points de vente'));
      await _pumps(tester);
      await tester.tap(find.text('Boutique Awa'));
    });
  }, skip: true);

  testWidgets('relevé des produits', (tester) async {
    await _shoot(tester, app(), '04-releve-produits', () async {
      await tester.tap(tab('Missions'));
      await _pumps(tester);
      await tester.tap(find.text('Tournée relevé Plateau'));
      await _pumps(tester);
      await tester.tap(find.text('Nouveau formulaire'));
      await _pumps(tester);
      // Lagune Blonde présente : 2 casiers + 6, 650 FCFA.
      await tester.tap(find.bySemanticsLabel('Présent').first);
      await _pumps(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'casiers').first,
        '2',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'bouteilles').first,
        '6',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Prix de vente').first,
        '650',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _pumps(tester);
    });
  }, skip: true);

  testWidgets('prise de commande', (tester) async {
    await _shoot(tester, app(), '05-commande', () async {
      await tester.tap(tab('Points de vente'));
      await _pumps(tester);
      await tester.tap(find.text('Boutique Awa'));
      await _pumps(tester);
      await tester.tap(find.text('Commander'));
      await _pumps(tester);
      final fields = find.widgetWithText(TextField, 'bouteilles');
      await tester.enterText(fields.at(0), '48');
      await tester.enterText(fields.at(1), '24');
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }, skip: true);

  testWidgets('le chef suit en direct', (tester) async {
    await _shoot(
      tester,
      testApp(
        auth: () => SignedInAuth(
          fakeMe(
            role: 'team_lead',
            first: 'Yao',
            features: {...auditFeatures, ...orderFeatures},
          ),
        ),
        mapTiles: true,
        overrides: [mapTileSourceProvider.overrideWithValue(_SavedTiles())],
      ),
      '06-chef-en-direct',
      () => tester.tap(tab('Carte')),
    );
  }, skip: true);

  testWidgets('ventes', (tester) async {
    await _shoot(tester, app(), '07-ventes', () async {
      await tester.tap(tab('Points de vente'));
      await _pumps(tester);
      await tester.tap(find.text('Mes statistiques'));
    });
  }, skip: true);
}
