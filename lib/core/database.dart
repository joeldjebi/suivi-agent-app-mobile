import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Positions mesurées, en attente d'envoi (conservées sans réseau).
class PendingPositions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dayId => text()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  RealColumn get accuracy => real()();
  RealColumn get speed => real().nullable()();
  BoolColumn get isMocked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get recordedAt => dateTime()();

  /// Batterie du téléphone, de 0 à 1 (alerte « batterie faible » du chef).
  RealColumn get battery => real().nullable()();
}

/// Formulaires de mission saisis, en attente d'envoi.
class PendingSubmissions extends Table {
  /// Identifiant généré sur le téléphone : un renvoi ne crée pas de doublon côté serveur.
  TextColumn get clientId => text()();
  TextColumn get missionId => text()();
  TextColumn get missionTitle => text()();
  TextColumn get dataJson => text()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  DateTimeColumn get submittedAt => dateTime()();

  /// Refus définitif du serveur (formulaire invalide, mission close) : n'est plus renvoyé.
  TextColumn get error => text().nullable()();

  /// Code du refus (DAY_REQUIRED, WRONG_ZONE, INVALID_FORM, MISSION_CLOSED…) : décide si
  /// l'agent peut corriger et renvoyer.
  TextColumn get errorCode => text().nullable()();

  /// Champs envoyés en plus des réponses (point de vente visité, précision du GPS…).
  TextColumn get extraJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {clientId};
}

/// Dernière réponse de chaque écran lu avec du réseau : affichée hors ligne.
class HttpCache extends Table {
  /// Adresse et paramètres de la requête.
  TextColumn get key => text()();
  TextColumn get body => text()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Points de vente ajoutés ou mis à jour sans réseau, en attente d'envoi (dans l'ordre).
class PendingOutlets extends Table {
  /// Identifiant généré sur le téléphone (création : évite un doublon au renvoi).
  TextColumn get clientId => text()();

  /// create, update, status, order (commande prise sans réseau), suggestion (produit
  /// concurrent signalé)
  TextColumn get kind => text()();

  /// Point de vente concerné (mise à jour, statut) ; null pour une création.
  TextColumn get outletId => text().nullable()();

  /// Nom affiché dans la liste d'attente.
  TextColumn get name => text()();

  /// Corps de la requête ; les photos y sont encore des fichiers du téléphone.
  TextColumn get bodyJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// Refus définitif (doublon, hors zone…) : conservé pour que l'agent décide.
  TextColumn get error => text().nullable()();
  TextColumn get errorCode => text().nullable()();

  @override
  Set<Column> get primaryKey => {clientId};
}

@DriftDatabase(
  tables: [PendingPositions, PendingSubmissions, HttpCache, PendingOutlets],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'suivi_agent',
              // Version web : SQLite compilé en WebAssembly, stocké dans le navigateur.
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // v2 : code du refus des formulaires.
      if (from < 2) {
        await m.addColumn(pendingSubmissions, pendingSubmissions.errorCode);
      }
      // v3 : batterie relevée avec chaque position.
      if (from < 3) {
        await m.addColumn(pendingPositions, pendingPositions.battery);
      }
      // v4 : mémoire des écrans pour le mode hors ligne.
      if (from < 4) await m.createTable(httpCache);
      // v5 : points de vente saisis sans réseau.
      if (from < 5) await m.createTable(pendingOutlets);
      // v6 : visites de points de vente (point de vente et statut avec le formulaire).
      if (from < 6) {
        await m.addColumn(pendingSubmissions, pendingSubmissions.extraJson);
      }
    },
  );

  /// Formulaires refusés par le serveur, à corriger ou supprimer par l'agent.
  Stream<List<PendingSubmission>> watchRejected() =>
      (select(pendingSubmissions)
            ..where((s) => s.error.isNotNull())
            ..orderBy([(s) => OrderingTerm.desc(s.submittedAt)]))
          .watch();

  Future<int> countPendingPositions() async {
    final count = pendingPositions.id.count();
    final row = await (selectOnly(
      pendingPositions,
    )..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Stream<int> watchPendingCount() {
    final positions = pendingPositions.id.count();
    final forms = pendingSubmissions.clientId.count();
    final p = (selectOnly(pendingPositions)..addColumns([positions]))
        .watchSingle()
        .map((r) => r.read(positions) ?? 0);
    final f =
        (selectOnly(pendingSubmissions)
              ..addColumns([forms])
              ..where(pendingSubmissions.error.isNull()))
            .watchSingle()
            .map((r) => r.read(forms) ?? 0);
    return p.asyncExpand((pc) => f.map((fc) => pc + fc));
  }

  /// Supprime tout (déconnexion) : rien ne doit rester sur le téléphone d'un autre agent.
  Future<void> wipe() async {
    await delete(pendingPositions).go();
    await delete(pendingSubmissions).go();
    await delete(httpCache).go();
    await delete(pendingOutlets).go();
  }

  /// Points de vente en attente d'envoi ou refusés, du plus ancien au plus récent.
  Stream<List<PendingOutlet>> watchPendingOutlets() => (select(
    pendingOutlets,
  )..orderBy([(o) => OrderingTerm.asc(o.createdAt)])).watch();

  // Mémoire des écrans (mode hors ligne).

  Future<void> cachePut(String key, String body) =>
      into(httpCache).insertOnConflictUpdate(
        HttpCacheCompanion.insert(
          key: key,
          body: body,
          savedAt: DateTime.now(),
        ),
      );

  Future<HttpCacheData?> cacheGet(String key) =>
      (select(httpCache)..where((c) => c.key.equals(key))).getSingleOrNull();

  /// Oublie ce qui n'a pas été relu depuis [age].
  Future<void> cachePrune(Duration age) =>
      (delete(httpCache)..where(
            (c) => c.savedAt.isSmallerThanValue(DateTime.now().subtract(age)),
          ))
          .go();
}
