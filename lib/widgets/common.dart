import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/branding.dart';
import '../design/components.dart';
import '../design/tokens.dart';

/// Logo de la structure, ou pictogramme par défaut, sur une tuile arrondie.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.branding, this.size = 44});

  final Branding branding;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.fromBorderSide(hairline(context)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(
        branding.logo == null ? size * 0.22 : size * 0.08,
      ),
      child: branding.logo == null
          ? Icon(
              Icons.place_rounded,
              color: branding.primary,
              size: size * 0.55,
            )
          : Image.memory(
              branding.logo!,
              fit: BoxFit.contain,
              semanticLabel: 'Logo ${branding.displayName}',
            ),
    );
  }
}

enum Tone { success, warning, danger, neutral, info }

/// Pastille de statut : toujours une icône et un libellé, jamais la couleur seule.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

Color toneColor(BuildContext context, Tone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (tone) {
    Tone.success => dark ? const Color(0xFF6EE7A0) : const Color(0xFF15803D),
    Tone.warning => dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
    Tone.danger => Theme.of(context).colorScheme.error,
    Tone.info => Theme.of(context).colorScheme.primary,
    Tone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

/// Carte de section avec titre discret.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(18),
  });

  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Bandeau d'information (hors connexion, erreur…).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    required this.message,
    this.tone = Tone.warning,
    this.action,
  });

  final IconData icon;
  final String message;
  final Tone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

/// Retour haptique léger sur les actions importantes.
void tapFeedback() => HapticFeedback.mediumImpact();

void showMessage(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? scheme.error : null,
      ),
    );
}

/// Feuille de confirmation (fin de journée, déconnexion…).
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconSquircle(
                icon: destructive
                    ? Icons.warning_amber_rounded
                    : Icons.help_outline_rounded,
                color: destructive ? scheme.error : null,
                size: 40,
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Space.sm),
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.xxl),
            PillButton(
              label: confirmLabel,
              style: destructive ? PillStyle.danger : PillStyle.primary,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: Space.md),
            PillButton(
              label: 'Annuler',
              style: PillStyle.outline,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}

/// Choix dans une liste (feuille du bas, coche sur l'option active).
/// Renvoie null si on ferme sans choisir ; sinon la valeur (qui peut être null).
Future<({T value})?> pickOption<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required Map<T, String> options,
}) => showModalBottomSheet<({T value})>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  builder: (context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: Space.lg),
        GroupedList(
          indent: Space.lg,
          children: [
            for (final o in options.entries)
              ListRow(
                title: o.value,
                chevron: false,
                trailing: o.key == selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(context, (value: o.key)),
              ),
          ],
        ),
      ],
    ),
  ),
);
