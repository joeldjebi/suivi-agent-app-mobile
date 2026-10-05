import 'package:flutter/material.dart';

/// Jetons du design « Suivi Agent » : inspiré d'iOS (listes groupées, grands titres,
/// couleurs unies), grille de 4.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// Marge latérale des écrans.
  static const page = 16.0;
}

abstract final class Radii {
  static const card = 13.0;
  static const tile = 12.0;
  static const button = 13.0;
  static const control = 12.0;
  static const pill = 999.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const curve = Curves.easeOutCubic;

  /// Respect du réglage « réduire les animations ».
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : d;
}

/// Filet d'un demi-point (séparateurs, barre d'onglets).
BorderSide hairline(BuildContext context) =>
    BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5);

/// Graisses de la police variable (l'axe « wght » doit suivre fontWeight).
extension TextWeight on TextStyle {
  TextStyle weight(int w) => copyWith(
    fontWeight: FontWeight.values[(w ~/ 100) - 1],
    fontVariations: [FontVariation('wght', w.toDouble())],
  );

  TextStyle get medium => weight(500);
  TextStyle get semibold => weight(600);
  TextStyle get bold => weight(700);
}

extension ColorTone on Color {
  Color darken(double amount) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color lighten(double amount) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }
}
