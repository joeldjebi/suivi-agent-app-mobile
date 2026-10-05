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

  @override
  Set<Column> get primaryKey => {clientId};
}

@DriftDatabase(tables: [PendingPositions, PendingSubmissions])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'suivi_agent'));

  @override
  int get schemaVersion => 1;

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
  }
}
