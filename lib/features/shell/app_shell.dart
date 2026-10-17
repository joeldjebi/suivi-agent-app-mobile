import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/components.dart';
import '../team/team_controller.dart';
import 'live_updates.dart';
import 'push_handler.dart';
import 'update_screen.dart';

/// Points de vente (formule qui les inclut).
const outletsTab = NavItem(
  label: 'Points de vente',
  icon: Icons.storefront_outlined,
  selectedIcon: Icons.storefront_rounded,
);

/// Agent : Journée, Missions, Points de vente, Profil.
const agentTabs = [
  NavItem(
    label: 'Journée',
    icon: Icons.today_outlined,
    selectedIcon: Icons.today_rounded,
  ),
  NavItem(
    label: 'Missions',
    icon: Icons.flag_outlined,
    selectedIcon: Icons.flag_rounded,
  ),
  outletsTab,
  NavItem(
    label: 'Profil',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

/// Chef d'équipe : Équipe, Carte, Demandes (ou Points de vente), Missions, Profil.
const leaderTabs = [
  NavItem(
    label: 'Équipe',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups_rounded,
  ),
  NavItem(
    label: 'Carte',
    icon: Icons.map_outlined,
    selectedIcon: Icons.map_rounded,
  ),
  NavItem(
    label: 'Demandes',
    icon: Icons.pending_actions_outlined,
    selectedIcon: Icons.pending_actions_rounded,
  ),
  outletsTab,
  NavItem(
    label: 'Missions',
    icon: Icons.flag_outlined,
    selectedIcon: Icons.flag_rounded,
  ),
  NavItem(
    label: 'Profil',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.shell,
    required this.tabs,
    this.leader = false,
  });

  final StatefulNavigationShell shell;
  final List<NavItem> tabs;
  final bool leader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mises à jour en direct tant que l'espace connecté est affiché.
    ref.watch(liveUpdatesProvider);
    final pending = leader ? ref.watch(requestsProvider).value?.length ?? 0 : 0;
    return PushHandler(
      leader: leader,
      // Mise à jour recommandée : fenêtre à l'ouverture.
      child: UpdatePrompt(
        child: Scaffold(
          body: shell,
          bottomNavigationBar: AppNavBar(
            index: shell.currentIndex,
            onSelect: (i) =>
                shell.goBranch(i, initialLocation: i == shell.currentIndex),
            items: [
              for (final tab in tabs)
                NavItem(
                  label: tab.label,
                  icon: tab.icon,
                  selectedIcon: tab.selectedIcon,
                  // Sans onglet « Demandes », leur nombre s'affiche sur « Équipe ».
                  badge:
                      tab.label == 'Demandes' ||
                          (tab.label == 'Équipe' &&
                              !tabs.any((t) => t.label == 'Demandes'))
                      ? pending
                      : 0,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
