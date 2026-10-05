import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/day/day_screen.dart';
import 'features/day/zone_map.dart';
import 'features/team/alerts_screen.dart';
import 'features/team/report_screen.dart';
import 'features/missions/mission_editor_screen.dart';
import 'features/shell/live_updates.dart';
import 'features/missions/mission_form_screen.dart';
import 'features/missions/mission_screen.dart';
import 'features/missions/missions_screen.dart';
import 'features/pay/pay_screens.dart';
import 'features/profile/account_screens.dart';
import 'features/profile/notifications_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/suspended_screen.dart';
import 'features/team/requests_screen.dart';
import 'features/team/team_map_screen.dart';
import 'features/team/team_screen.dart';

/// Rafraîchit le routeur quand la session change.
class _AuthListenable extends ChangeNotifier {
  void notify() => notifyListeners();
}

final _missionRoutes = GoRoute(
  path: '/missions',
  builder: (_, _) => const MissionsScreen(),
  routes: [
    // Chef d'équipe : nouvelle mission (avant « :id » pour ne pas être prise pour un identifiant).
    GoRoute(path: 'create', builder: (_, _) => const MissionEditorScreen()),
    GoRoute(
      path: ':id',
      builder: (_, s) => MissionScreen(id: s.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (_, s) =>
              MissionEditorScreen(missionId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: 'new',
          builder: (_, s) => MissionFormScreen(id: s.pathParameters['id']!),
        ),
      ],
    ),
  ],
);

/// Profil et ses écrans de modification (agents et chefs d'équipe).
final _profileRoute = GoRoute(
  path: '/profile',
  builder: (_, _) => const ProfileScreen(),
  routes: [
    GoRoute(path: 'edit', builder: (_, _) => const EditProfileScreen()),
    GoRoute(path: 'password', builder: (_, _) => const ChangePasswordScreen()),
    GoRoute(path: 'earnings', builder: (_, _) => const EarningsScreen()),
    GoRoute(
      path: 'team-earnings',
      builder: (_, _) => const TeamEarningsScreen(),
    ),
  ],
);

/// Écrans de l'agent : sa journée, ses missions (si la formule les inclut), son profil.
StatefulShellRoute _agentShell({required bool missions}) =>
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(
        shell: shell,
        tabs: [
          for (final tab in agentTabs)
            if (missions || tab.label != 'Missions') tab,
        ],
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/day',
              builder: (_, _) => const DayScreen(),
              routes: [
                GoRoute(path: 'zone', builder: (_, _) => const MyZoneScreen()),
              ],
            ),
          ],
        ),
        if (missions) StatefulShellBranch(routes: [_missionRoutes]),
        StatefulShellBranch(routes: [_profileRoute]),
      ],
    );

/// Écrans du chef d'équipe : son équipe en direct, la carte, les demandes à valider,
/// les missions du groupe (si la formule les inclut).
StatefulShellRoute _leaderShell({
  required bool missions,
}) => StatefulShellRoute.indexedStack(
  builder: (_, _, shell) => AppShell(
    shell: shell,
    tabs: [
      for (final tab in leaderTabs)
        if (missions || tab.label != 'Missions') tab,
    ],
    leader: true,
  ),
  branches: [
    StatefulShellBranch(
      routes: [GoRoute(path: '/team', builder: (_, _) => const TeamScreen())],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: '/map',
          builder: (_, s) =>
              TeamMapScreen(agentId: s.uri.queryParameters['agent']),
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(path: '/requests', builder: (_, _) => const RequestsScreen()),
      ],
    ),
    if (missions) StatefulShellBranch(routes: [_missionRoutes]),
    StatefulShellBranch(routes: [_profileRoute]),
  ],
);

/// Le routeur est reconstruit quand le rôle change (connexion, déconnexion).
final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable();
  // Seuls la connexion et la déconnexion déplacent l'utilisateur : une mise à jour du
  // profil ou de l'apparence ne doit pas recalculer la navigation en cours.
  ref.listen(
    authProvider.select((a) => a.runtimeType),
    (_, _) => listenable.notify(),
  );
  final role = ref.watch(
    authProvider.select((a) => a is SignedIn ? a.me.role : null),
  );
  // La formule de la structure décide des onglets ; un abonnement suspendu bloque l'app.
  final missions = ref.watch(
    authProvider.select((a) => a is SignedIn && a.me.hasMissions),
  );
  final suspended = ref.watch(
    authProvider.select((a) => a is SignedIn && a.me.suspended),
  );
  final leader = role == 'team_lead';
  final home = leader ? '/team' : '/day';
  final router = GoRouter(
    initialLocation: home,
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final atLogin = state.matchedLocation == '/login';
      return switch (auth) {
        AuthLoading() => state.matchedLocation == '/splash' ? null : '/splash',
        SignedOut() => atLogin ? null : '/login',
        SignedIn() when suspended =>
          state.matchedLocation == '/suspended' ? null : '/suspended',
        SignedIn() =>
          atLogin ||
                  state.matchedLocation == '/splash' ||
                  state.matchedLocation == '/suspended'
              ? home
              : null,
      };
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/suspended', builder: (_, _) => const SuspendedScreen()),
      if (role != null)
        leader
            ? _leaderShell(missions: missions)
            : _agentShell(missions: missions),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen()),
      GoRoute(path: '/report', builder: (_, _) => const DailyReportScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class SuiviAgentApp extends ConsumerStatefulWidget {
  const SuiviAgentApp({super.key});

  @override
  ConsumerState<SuiviAgentApp> createState() => _SuiviAgentAppState();
}

class _SuiviAgentAppState extends ConsumerState<SuiviAgentApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retour dans l'app : formule et apparence relues (changées entre-temps par la structure
  /// ou l'éditeur).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authProvider.notifier).refresh();
      // Écrans relus au retour : les annonces ont pu être manquées en arrière-plan.
      if (ref.exists(liveUpdatesProvider)) {
        ref.read(liveUpdatesProvider).resume();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apparence de la structure une fois l'agent connecté, apparence neutre sinon.
    final branding = ref.watch(brandingProvider);
    return MaterialApp.router(
      title: 'Suivi Agent',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(branding, Brightness.light),
      darkTheme: buildTheme(branding, Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
