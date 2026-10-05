import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/components.dart';
import '../team/team_controller.dart';

/// Agent : Journée, Missions, Profil.
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
  NavItem(
    label: 'Profil',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

/// Chef d'équipe : Équipe, Carte, Demandes, Missions, Profil.
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
    final pending = leader ? ref.watch(requestsProvider).value?.length ?? 0 : 0;
    return Scaffold(
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
              badge: tab.label == 'Demandes' ? pending : 0,
            ),
        ],
      ),
    );
  }
}
