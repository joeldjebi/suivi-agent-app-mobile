import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Carte unie, sans bordure ni ombre : le contraste avec le fond suffit
/// (comme les listes groupées d'iOS).
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.onTap,
    this.color,
    this.radius = Radii.card,
    this.border,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final BorderSide? border;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Material(
      color: color ?? scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: border ?? BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    return semanticLabel == null
        ? card
        : Semantics(label: semanticLabel, button: onTap != null, child: card);
  }
}

/// Icône sur une pastille arrondie : teintée, ou pleine avec un pictogramme
/// blanc (style Réglages).
class IconSquircle extends StatelessWidget {
  const IconSquircle({
    super.key,
    required this.icon,
    this.color,
    this.size = 36,
    this.solid = false,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solid ? c : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * (solid ? 0.24 : 0.28)),
      ),
      child: Icon(
        icon,
        color: solid ? Colors.white : c,
        size: size * (solid ? 0.6 : 0.52),
      ),
    );
  }
}

/// `outline` est un bouton secondaire gris (fond neutre, sans contour).
enum PillStyle { primary, tonal, outline, danger }

/// Bouton plein de 50 px, coins de 14 px.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = PillStyle.primary,
    this.loading = false,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final PillStyle style;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null && !loading;
    final (Color bg, Color fg) = switch (style) {
      PillStyle.primary => (scheme.primary, scheme.onPrimary),
      PillStyle.danger => (scheme.error, scheme.onError),
      PillStyle.tonal => (
        scheme.primary.withValues(alpha: 0.12),
        scheme.primary,
      ),
      PillStyle.outline => (
        scheme.onSurface.withValues(alpha: 0.07),
        scheme.onSurface,
      ),
    };
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: enabled
            ? () {
                HapticFeedback.selectionClick();
                onPressed!();
              }
            : null,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: bg.a * 0.45),
          disabledForegroundColor: fg.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontSize: 15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            else if (icon != null)
              Icon(icon, size: 19),
            if (loading || icon != null) const SizedBox(width: Space.sm),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

/// Avatar aux initiales, avec un petit point de statut.
class StatusAvatar extends StatelessWidget {
  const StatusAvatar({
    super.key,
    required this.initials,
    required this.ringColor,
    this.size = 40,
    this.badgeIcon,
  });

  final String initials;

  /// Couleur du statut (point en bas à droite).
  final Color ringColor;
  final double size;
  final IconData? badgeIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: scheme.surfaceContainerHighest,
            child: Text(
              initials,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontSize: size * 0.34),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                color: ringColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.surfaceContainerLowest,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre de progression fine.
class ThinProgress extends StatelessWidget {
  const ThinProgress({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: height,
        color: c,
        backgroundColor: c.withValues(alpha: 0.14),
      ),
    );
  }
}

/// Anneau de progression (style Activité) : piste teintée, arc à bouts ronds.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 120,
    this.stroke = 12,
    this.color,
    this.child,
  });

  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.clamp(0, 1).toDouble(),
          stroke: stroke,
          color: c,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.color,
  });

  final double value;
  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      paint..color = color.withValues(alpha: 0.16),
    );
    if (value > 0.005) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.stroke != stroke;
}

/// Point de statut (fixe).
class LiveDot extends StatelessWidget {
  const LiveDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Pastille de statut : point et libellé sur un fond teinté.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiveDot(color: color, size: 6),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    ),
  );
}

/// Titre de section, en petites capitales grises au-dessus d'un groupe.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.xl,
        Space.lg,
        Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Liste groupée (style Réglages) : titre facultatif, une carte avec séparateurs
/// en retrait, note facultative en dessous.
class GroupedList extends StatelessWidget {
  const GroupedList({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.indent = 54,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;

  /// Retrait des séparateurs (début du texte des lignes).
  final double indent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) SectionHeader(header!),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: indent,
                    color: scheme.outlineVariant,
                  ),
                children[i],
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: Text(
              footer!,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// Ligne de liste groupée : pictogramme, titre, sous-titre, valeur à droite, chevron.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.centered = false,
    this.chevron,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  /// Titre centré, sans pictogramme (action seule, ex. « Se déconnecter »).
  final bool centered;

  /// Par défaut : un chevron si la ligne est cliquable.
  final bool? chevron;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = text.bodyLarge?.medium.copyWith(color: titleColor);
    final showChevron = chevron ?? (onTap != null && !centered);

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: 9,
          ),
          child: centered
              ? Center(child: Text(title, style: titleStyle))
              : Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: Space.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: titleStyle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              subtitle!,
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (value != null) ...[
                      const SizedBox(width: Space.sm),
                      Text(
                        value!,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(width: Space.sm),
                      trailing!,
                    ],
                    if (showChevron) ...[
                      const SizedBox(width: Space.xs),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Sélecteur segmenté (style iOS) : piste grise, segment choisi en blanc.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final Map<T, String> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 33,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF767680).withValues(alpha: dark ? 0.24 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final entry in segments.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: entry.key == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (entry.key == selected) return;
                    HapticFeedback.selectionClick();
                    onChanged(entry.key);
                  },
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.fast),
                    curve: Motion.curve,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.key == selected
                          ? (dark
                                ? const Color(0xFF636366)
                                : scheme.surfaceContainerLowest)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      entry.value,
                      style: entry.key == selected
                          ? text.labelMedium?.copyWith(fontSize: 13)
                          : text.labelMedium?.copyWith(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Élément de la barre d'onglets.
class NavItem {
  const NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badge;
}

/// Barre d'onglets (style iOS) : icône et petit libellé, sans indicateur,
/// l'onglet actif prend la couleur de la structure.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF121212) : const Color(0xFFF9F9F9),
        border: Border(top: hairline(context)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: _tab(context, items[i], i, scheme, text)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    NavItem item,
    int i,
    ColorScheme scheme,
    TextTheme text,
  ) {
    final selected = i == index;
    final color = selected
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: 0.85);
    return Semantics(
      button: true,
      selected: selected,
      label: item.badge > 0
          ? '${item.label}, ${item.badge} en attente'
          : item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onSelect(i);
        },
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: item.badge > 0,
              label: Text('${item.badge}'),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 23,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: text.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 0.1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
