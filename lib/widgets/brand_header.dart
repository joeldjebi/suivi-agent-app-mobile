import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/providers.dart';
import '../design/tokens.dart';
import '../features/profile/notifications_screen.dart';
import 'common.dart';

/// Grand titre (style iOS) : la date en petites capitales, le titre, puis à droite
/// les notifications et le logo de la structure.
class BrandHeader extends ConsumerWidget {
  const BrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = true,
  });

  final String title;

  /// Ligne au-dessus du titre ; par défaut, la date du jour.
  final String? subtitle;

  /// Notifications et logo à droite.
  final bool actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(brandingProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final unread = ref.watch(unreadCountProvider).value ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.page + Space.xs,
        MediaQuery.paddingOf(context).top + Space.lg,
        Space.page,
        Space.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (subtitle ?? formatDay(DateTime.now())).toUpperCase(),
                  style: text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(title, style: text.displayMedium),
              ],
            ),
          ),
          if (actions) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Semantics(
                button: true,
                label: unread > 0
                    ? 'Notifications, $unread non lues'
                    : 'Notifications',
                excludeSemantics: true,
                child: Material(
                  color: scheme.surfaceContainerHighest,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.push('/notifications'),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Badge(
                        isLabelVisible: unread > 0,
                        smallSize: 8,
                        label: null,
                        alignment: const AlignmentDirectional(0.55, -0.6),
                        child: Icon(
                          Icons.notifications_none_rounded,
                          size: 19,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: BrandLogo(branding: branding, size: 34),
            ),
          ],
        ],
      ),
    );
  }
}

/// Écran défilant : en-tête puis contenu, avec la place pour une barre d'action en bas.
class HeroScaffoldBody extends StatelessWidget {
  const HeroScaffoldBody({
    super.key,
    required this.header,
    required this.children,
    this.onRefresh,
  });

  final Widget header;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        header,
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
    return onRefresh == null
        ? list
        : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// Ligne « icône + libellé + valeur » utilisée dans les fiches.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: tone == null
                ? scheme.onSurfaceVariant
                : toneColor(context, tone!),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Text(value, style: text.titleSmall),
        ],
      ),
    );
  }
}
