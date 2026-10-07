import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contact.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';

/// Équipe de l'agent (groupe, chef, zones), relue à chaque modification annoncée.
final myTeamProvider = FutureProvider<AgentTeam>(
  (ref) => ref.read(repositoryProvider).myTeam(),
);

/// Pourquoi l'agent n'a pas de zone à choisir, s'il n'en a pas.
String? teamWarning(AgentTeam team) {
  if (team.groupMissing) {
    return 'Vous n’êtes rattaché à aucun groupe : vos zones et les missions de votre groupe apparaîtront dès que votre structure vous y aura ajouté.';
  }
  if (team.zones.isEmpty) {
    return team.usesGroups
        ? 'Votre groupe n’a pas encore de zone. Contactez votre chef d’équipe.'
        : 'Aucune zone ne vous est encore ouverte. Contactez votre chef d’équipe.';
  }
  return null;
}

/// Boutons Appeler et WhatsApp d'un chef d'équipe.
class _ContactButtons extends StatelessWidget {
  const _ContactButtons({required this.lead});

  final TeamLeadContact lead;

  @override
  Widget build(BuildContext context) {
    final phone = lead.phone;
    if (phone == null || phone.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Appeler ${lead.fullName}',
          icon: const Icon(Icons.call_rounded, color: Color(0xFF34A853)),
          onPressed: () {
            HapticFeedback.selectionClick();
            unawaited(callPhone(phone));
          },
        ),
        IconButton(
          tooltip: 'WhatsApp ${lead.fullName}',
          icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
          onPressed: () {
            HapticFeedback.selectionClick();
            unawaited(openWhatsApp(phone));
          },
        ),
      ],
    );
  }
}

Widget _initials(
  BuildContext context,
  TeamLeadContact lead, {
  double size = 40,
}) {
  final scheme = Theme.of(context).colorScheme;
  return CircleAvatar(
    radius: size / 2,
    backgroundColor: scheme.primary.withValues(alpha: 0.12),
    child: Text(
      lead.initials,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: scheme.primary,
        fontSize: size * 0.36,
      ),
    ),
  );
}

/// Profil de l'agent : son groupe, son chef (à appeler) et ses zones.
class MyTeamSection extends ConsumerWidget {
  const MyTeamSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(myTeamProvider);
    final scheme = Theme.of(context).colorScheme;
    return team.when(
      loading: () => const GroupedList(
        header: 'Mon équipe',
        children: [ListRow(title: 'Chargement…')],
      ),
      error: (_, _) => GroupedList(
        header: 'Mon équipe',
        children: [
          ListRow(
            title: 'Équipe indisponible hors connexion',
            titleColor: scheme.onSurfaceVariant,
            onTap: () => ref.invalidate(myTeamProvider),
          ),
        ],
      ),
      data: (t) => GroupedList(
        header: 'Mon équipe',
        footer: teamWarning(t),
        children: [
          if (t.usesGroups)
            ListRow(
              leading: const IconSquircle(
                icon: Icons.groups_rounded,
                color: Color(0xFF8B5CF6),
                size: 28,
                solid: true,
              ),
              title: 'Groupe',
              value: t.groupName ?? 'Aucun',
              subtitle: t.groupName == null
                  ? null
                  : '${t.members} agent${t.members > 1 ? 's' : ''}',
            ),
          for (final lead in t.leads)
            ListRow(
              leading: _initials(context, lead, size: 34),
              title: lead.fullName,
              subtitle: 'Chef d’équipe',
              trailing: _ContactButtons(lead: lead),
              chevron: false,
            ),
          if (t.leads.isEmpty)
            ListRow(
              leading: const IconSquircle(
                icon: Icons.person_off_rounded,
                color: Color(0xFF8E8E93),
                size: 28,
                solid: true,
              ),
              title: 'Chef d’équipe',
              value: 'Non désigné',
            ),
          ListRow(
            leading: const IconSquircle(
              icon: Icons.map_rounded,
              color: Color(0xFF14B8A6),
              size: 28,
              solid: true,
            ),
            title: t.zones.length > 1 ? 'Mes zones' : 'Ma zone',
            value: t.zones.isEmpty ? 'Aucune' : '${t.zones.length}',
            subtitle: t.zones.isEmpty
                ? null
                : t.zones.map((z) => z.name).join(', '),
          ),
        ],
      ),
    );
  }
}

/// Écran Journée : rappel compact du groupe et du chef, ou de ce qui manque.
class MyTeamCard extends ConsumerWidget {
  const MyTeamCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(myTeamProvider).value;
    if (team == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final warning = teamWarning(team);
    final lead = team.leads.firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lead != null || team.groupName != null)
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.sm,
                Space.md,
              ),
              child: Row(
                children: [
                  if (lead != null)
                    _initials(context, lead)
                  else
                    const CircleAvatar(
                      radius: 20,
                      child: Icon(Icons.groups_rounded),
                    ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead == null ? 'Mon groupe' : lead.fullName,
                          style: text.titleSmall?.semibold,
                        ),
                        Text(
                          [
                            if (lead != null) 'Mon chef d’équipe',
                            if (team.groupName != null) team.groupName!,
                          ].join(' · '),
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (lead != null) _ContactButtons(lead: lead),
                ],
              ),
            ),
          if (warning != null) ...[
            if (lead != null || team.groupName != null)
              const SizedBox(height: Space.md),
            InfoBanner(icon: Icons.info_outline_rounded, message: warning),
          ],
        ],
      ),
    );
  }
}
