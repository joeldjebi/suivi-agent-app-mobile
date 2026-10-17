import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Largeur maximale de l'app sur tablette : au-delà, les écrans conçus pour le téléphone
/// s'étirent (lignes très longues, boutons démesurés).
const tabletContentWidth = 720.0;

/// Sur grand écran (iPad), l'app s'affiche dans une colonne centrée, le fond de l'app
/// remplissant les côtés. Les écrans voient la largeur de la colonne comme celle de l'écran.
class TabletFrame extends StatelessWidget {
  const TabletFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width < tabletContentWidth + 80) return child;
    final width = math.min(media.size.width, tabletContentWidth);
    final side = (media.size.width - width) / 2;
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Container(
          width: width,
          decoration: BoxDecoration(
            border: Border.symmetric(
              vertical: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: MediaQuery(
            data: media.copyWith(
              size: Size(width, media.size.height),
              padding: media.padding.copyWith(
                left: math.max(0, media.padding.left - side),
                right: math.max(0, media.padding.right - side),
              ),
              viewPadding: media.viewPadding.copyWith(
                left: math.max(0, media.viewPadding.left - side),
                right: math.max(0, media.viewPadding.right - side),
              ),
            ),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
