import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivi_agent/app.dart';
import 'package:suivi_agent/core/local_notifications.dart';
import 'package:suivi_agent/core/push.dart';
import 'package:suivi_agent/features/team/alerts_screen.dart';

import 'fakes.dart';

void main() {
  test('chaque notification ouvre son écran', () {
    String agent(Map<String, String> d) => pushRouteFor(d, leader: false);
    String chef(Map<String, String> d) => pushRouteFor(d, leader: true);

    expect(
      chef({'type': 'zone_request.created', 'requestId': 'r1'}),
      '/requests',
    );
    expect(chef({'type': 'zone_request.reminder'}), '/requests');
    expect(agent({'type': 'zone_request.approved'}), '/day');
    expect(agent({'type': 'zone.deactivated'}), '/day');
    expect(
      agent({'type': 'mission.assigned', 'missionId': 'm1'}),
      '/missions/m1',
    );
    expect(
      agent({'type': 'submission.rejected', 'missionId': 'm2'}),
      '/missions/m2',
    );
    expect(agent({'type': 'pay.paid'}), '/profile/earnings');
    expect(chef({'type': 'pay.adjustment_proposed'}), '/profile/team-earnings');
    expect(chef({'type': 'alert.late_start'}), '/alerts');
    expect(chef({'type': 'zone_exit'}), '/alerts');
    expect(chef({'type': 'team.message'}), '/report');
    expect(agent({'type': 'team.message'}), '/notifications');
    // Type inconnu ou avis d'abonnement : la liste des notifications.
    expect(agent({'type': 'subscription.suspended'}), '/notifications');
    expect(agent({}), '/notifications');
  });

  test('fonctionnalité de la formule', () {
    expect(fakeMe().hasPush, isFalse);
    expect(fakeMe(features: {'missions', pushFeature}).hasPush, isTrue);
  });

  Future<ProviderContainer> leaderApp(
    WidgetTester tester,
    FakeRepository repo,
  ) async {
    await tester.pumpWidget(
      testApp(
        auth: () => SignedInAuth(fakeMe(role: 'team_lead', first: 'Yao')),
        repo: repo,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return ProviderScope.containerOf(
      tester.element(find.byType(SuiviAgentApp)),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('bouton « Approuver » : la demande est validée', (tester) async {
    final repo = FakeRepository();
    final container = await leaderApp(tester, repo);
    container
        .read(pushInboxProvider.notifier)
        .put(
          const PushOpen({
            'type': 'zone_request.created',
            'requestId': 'r1',
          }, action: zoneApproveAction),
        );
    await settle(tester);
    expect(repo.decisions, [(id: 'r1', approve: true)]);
    expect(find.text('Demande de zone approuvée.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('bouton « Refuser » : écran Demandes, sans décision', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = await leaderApp(tester, repo);
    container
        .read(pushInboxProvider.notifier)
        .put(
          const PushOpen({
            'type': 'zone_request.created',
            'requestId': 'r1',
          }, action: zoneRejectAction),
        );
    await settle(tester);
    expect(repo.decisions, isEmpty);
    expect(find.text('Indiquez le motif du refus.'), findsOneWidget);
    expect(find.text('Serge Gbagbo'), findsWidgets);
    await close(tester);
  });

  testWidgets('alerte touchée : écran des alertes', (tester) async {
    final container = await leaderApp(tester, FakeRepository());
    container
        .read(pushInboxProvider.notifier)
        .put(const PushOpen({'type': 'alert.late_start'}));
    await settle(tester);
    expect(find.byType(AlertsScreen), findsOneWidget);
    await close(tester);
  });
}
