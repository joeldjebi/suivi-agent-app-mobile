import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'lucide_icons.dart';

/// Icône Lucide (les mêmes que le site web), à la couleur du thème ou donnée.
class LucideIcon extends StatelessWidget {
  const LucideIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 2,
    this.semanticLabel,
  });

  /// Clé dans [lucideIcons] (ex. « store »).
  final String name;
  final double size;
  final Color? color;
  final double strokeWidth;
  final String? semanticLabel;

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black;
    final body = lucideIcons[name] ?? lucideIcons['store']!;
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke="${_hex(c)}" stroke-opacity="${c.a}" stroke-width="$strokeWidth" '
      'stroke-linecap="round" stroke-linejoin="round">$body</svg>',
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
