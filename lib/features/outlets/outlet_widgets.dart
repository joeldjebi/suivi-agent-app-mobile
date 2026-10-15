import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/lucide.dart';
import 'outlet_models.dart';
import 'outlets_controller.dart';

/// Statut : icône et libellé, jamais la couleur seule.
class OutletStatusPill extends StatelessWidget {
  const OutletStatusPill(this.status, {super.key, this.dense = false});

  final OutletStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: 4),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LucideIcon(status.icon, size: dense ? 13 : 15, color: status.color),
        const SizedBox(width: 4),
        Text(
          status.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: status.color,
            fontSize: dense ? 11 : null,
          ),
        ),
      ],
    ),
  );
}

/// Icône du type de commerce sur un rond de la couleur du statut.
class OutletAvatar extends StatelessWidget {
  const OutletAvatar({
    super.key,
    required this.category,
    required this.status,
    this.size = 40,
  });

  final String? category;
  final OutletStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
    child: Center(
      child: LucideIcon(
        categoryIcon(category),
        color: Colors.white,
        size: size * 0.5,
      ),
    ),
  );
}

/// Épingle de carte : couleur du statut, icône du type de commerce, ‖ ou × pour les
/// statuts éteints (mêmes repères que sur le site).
class OutletPin extends StatelessWidget {
  const OutletPin({
    super.key,
    required this.category,
    required this.status,
    this.selected = false,
    this.overdue = false,
  });

  /// Couleur du repère « en retard de visite » (comme sur le site).
  static const overdueColor = Color(0xFFEA580C);

  /// Horloge orange en haut à gauche : en retard de visite.
  final bool overdue;

  static const width = 34.0;
  static const height = 42.0;

  final String? category;
  final OutletStatus status;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scale = selected ? 1.2 : 1.0;
    final badge = switch (status) {
      OutletStatus.inactive => Icons.pause_rounded,
      OutletStatus.closed => Icons.close_rounded,
      _ => null,
    };
    return Transform.scale(
      scale: scale,
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PinPainter(status.color, selected ? 3 : 2),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 7,
              child: Center(
                child: LucideIcon(
                  categoryIcon(category),
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
            if (overdue)
              Positioned(
                top: -4,
                left: -4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: overdueColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            if (badge != null)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: status.color, width: 1.5),
                  ),
                  child: Icon(badge, size: 11, color: status.color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter(this.color, this.stroke);

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w / 2, h - 1)
      ..cubicTo(w * 0.42, h * 0.86, w * 0.06, h * 0.6, w * 0.06, h * 0.38)
      ..arcToPoint(
        Offset(w * 0.94, h * 0.38),
        radius: Radius.circular(w * 0.44),
      )
      ..cubicTo(w * 0.94, h * 0.6, w * 0.58, h * 0.86, w / 2, h - 1)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_PinPainter old) =>
      old.color != color || old.stroke != stroke;
}

/// Photo déjà envoyée (fiche du point de vente).
class RemotePhoto extends ConsumerWidget {
  const RemotePhoto({
    super.key,
    required this.id,
    required this.label,
    this.height = 180,
  });

  final String id;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = ref.watch(photoBytesProvider(id));
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: height,
        width: double.infinity,
        color: scheme.surfaceContainerHighest,
        child: switch (bytes) {
          AsyncData(:final value) when value != null => Image.memory(
            Uint8List.fromList(value),
            fit: BoxFit.cover,
            semanticLabel: label,
          ),
          AsyncLoading() => const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          _ => Icon(
            Icons.hide_image_outlined,
            color: scheme.onSurfaceVariant,
            semanticLabel: 'Photo indisponible',
          ),
        },
      ),
    );
  }
}

/// « 120 m », « 1,4 km ».
String formatDistance(int meters) => meters < 1000
    ? '$meters m'
    : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

/// « En retard » : pastille orange avec une horloge.
class OverduePill extends StatelessWidget {
  const OverduePill({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: 4),
    decoration: BoxDecoration(
      color: OutletPin.overdueColor.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.schedule_rounded,
          size: dense ? 13 : 15,
          color: OutletPin.overdueColor,
        ),
        const SizedBox(width: 4),
        Text(
          'En retard',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: OutletPin.overdueColor,
            fontSize: dense ? 11 : null,
          ),
        ),
      ],
    ),
  );
}
