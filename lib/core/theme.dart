import 'package:flutter/material.dart';

import 'branding.dart';

/// Thème de l'app : la couleur de la structure, Plus Jakarta Sans, grandes zones tactiles.
ThemeData buildTheme(Branding branding, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: branding.primary,
    brightness: brightness,
  );
  final scheme = base.copyWith(
    // En clair, la couleur exacte de la structure ; en sombre, la teinte claire dérivée (lisible).
    primary: dark ? base.primary : branding.primary,
    onPrimary: dark ? base.onPrimary : branding.onPrimary,
    // Palette des listes groupées d'iOS : fond gris, cartes blanches.
    surface: dark ? Colors.black : const Color(0xFFF2F2F7),
    surfaceContainerLowest: dark ? const Color(0xFF1C1C1E) : Colors.white,
    surfaceContainerHighest: dark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFE5E5EA),
    onSurface: dark ? Colors.white : const Color(0xFF0B0B0F),
    onSurfaceVariant: dark ? const Color(0xFF98989F) : const Color(0xFF6C6C70),
    outlineVariant: dark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8),
    error: dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
  );

  final text = _textTheme(dark ? Colors.white : const Color(0xFF0B0B0F));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'PlusJakartaSans',
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,

    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 0.5,
      space: 0.5,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: text.titleMedium,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: text.titleMedium,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: text.labelLarge,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: text.labelLarge,
      selectedColor: scheme.primary.withValues(alpha: 0.14),
      checkmarkColor: scheme.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      prefixIconColor: scheme.onSurfaceVariant,
      hintStyle: text.bodyLarge?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: dark ? const Color(0xFF2A2F3A) : const Color(0xFF0F172A),
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 0,
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.1),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelSmall?.copyWith(
          fontSize: 12,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      titleTextStyle: text.titleSmall,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Styles typographiques. La police est variable : la graisse est fixée par l'axe « wght »
/// pour un rendu identique sur Android et iOS.
TextTheme _textTheme(Color color) {
  TextStyle style(
    double size,
    int weight, {
    double height = 1.3,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: size,
    height: height,
    letterSpacing: spacing,
    color: color,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight.toDouble())],
  );
  return TextTheme(
    displayMedium: style(30, 700, height: 1.1, spacing: -0.8),
    displaySmall: style(26, 700, height: 1.15, spacing: -0.5),
    headlineMedium: style(22, 700, height: 1.2, spacing: -0.4),
    headlineSmall: style(19, 700, height: 1.25, spacing: -0.2),
    titleLarge: style(17, 700, spacing: -0.1),
    titleMedium: style(15, 600),
    titleSmall: style(13.5, 600),
    bodyLarge: style(15, 400, height: 1.45),
    bodyMedium: style(13.5, 400, height: 1.45),
    bodySmall: style(12, 400, height: 1.4),
    labelLarge: style(14, 600),
    labelMedium: style(12, 600),
    labelSmall: style(11, 600, spacing: 0.4),
  );
}
