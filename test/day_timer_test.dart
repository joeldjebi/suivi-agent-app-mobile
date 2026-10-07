import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivi_agent/core/database.dart';
import 'package:suivi_agent/core/day_timer.dart';
import 'package:suivi_agent/core/models.dart';
import 'package:suivi_agent/core/providers.dart';
import 'package:suivi_agent/core/sync.dart';
import 'package:suivi_agent/features/day/day_controller.dart';

import 'fakes.dart';

/// Chrono simulé : garde ce qui serait affiché sur l'écran verrouillé.
class FakeDayTimer implements DayTimer {
  final shown = <DayTimerInfo>[];
  int cleared = 0;

  @override
  Future<void> show(DayTimerInfo info) async => shown.add(info);

  @override
  Future<void> clear() async => cleared++;
}

WorkDay _day(DayStatus status, {DateTime? pausedAt, int pausedSeconds = 0}) =>
    WorkDay(
      id: 'd1',
      status: status,
      zoneId: 'z1',
      startedAt: DateTime.now().subtract(const Duration(hours: 3)),
      endedAt: status == DayStatus.ended ? DateTime.now() : null,
      pausedSeconds: pausedSeconds,
      currentPauseStartedAt: pausedAt,
    );

void main() {
  test('chrono : affiché en journée et en pause, retiré à la fin', () async {
    final repo = FakeRepository()..day = DayState(day: _day(DayStatus.active));
    final timer = FakeDayTimer();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => SignedInAuth(fakeMe(workdayMinutes: 420)),
        ),
        repositoryProvider.overrideWithValue(repo),
        databaseProvider.overrideWithValue(db),
        trackerProvider.overrideWith((ref) => FakeTracker(db)),
        alertSinkProvider.overrideWithValue(FakeAlerts()),
        dayTimerProvider.overrideWithValue(timer),
        syncProvider.overrideWith(
          (ref) => SyncService(
            db,
            repo,
            connectivity: const Stream<List<ConnectivityResult>>.empty(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Journée en cours : 3 h travaillées, objectif de l'agent (7 h), nom de la zone.
    await container.read(dayProvider.future);
    await Future<void>.delayed(Duration.zero);
    final active = timer.shown.single;
    expect(active.paused, isFalse);
    expect(active.worked.inMinutes, closeTo(180, 1));
    expect(active.objective, const Duration(hours: 7));
    expect(active.zone, 'Plateau');

    // Pause depuis 20 min : chrono figé, heure de début de la pause.
    final pausedAt = DateTime.now().subtract(const Duration(minutes: 20));
    repo.day = DayState(day: _day(DayStatus.paused, pausedAt: pausedAt));
    await container.read(dayProvider.notifier).refresh();
    await Future<void>.delayed(Duration.zero);
    expect(timer.shown.last.paused, isTrue);
    expect(timer.shown.last.pausedAt, pausedAt);
    expect(timer.shown.last.worked.inMinutes, closeTo(160, 1));

    // Fin de journée : retiré de l'écran verrouillé.
    repo.day = DayState(day: _day(DayStatus.ended));
    await container.read(dayProvider.notifier).refresh();
    await Future<void>.delayed(Duration.zero);
    expect(timer.cleared, 1);
  });

  test('chrono : une mise à jour seulement si quelque chose change', () {
    const base = DayTimerInfo(
      paused: false,
      worked: Duration(minutes: 90),
      objective: Duration(hours: 8),
      structure: 'Démo',
      zone: 'Plateau',
    );
    // Le chrono avance seul : quelques secondes d'écart ne comptent pas.
    expect(
      base ==
          const DayTimerInfo(
            paused: false,
            worked: Duration(minutes: 90, seconds: 2),
            objective: Duration(hours: 8),
            structure: 'Démo',
            zone: 'Plateau',
          ),
      isTrue,
    );
    expect(
      base ==
          const DayTimerInfo(
            paused: true,
            worked: Duration(minutes: 90),
            objective: Duration(hours: 8),
            structure: 'Démo',
            zone: 'Plateau',
          ),
      isFalse,
    );
  });
}
