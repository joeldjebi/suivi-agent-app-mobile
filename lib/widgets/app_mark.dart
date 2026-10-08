import 'package:flutter/material.dart';

/// Symbole Suivi Agent (« le parcours ») : un trajet du départ à l'arrivée.
/// Dessiné en vectoriel, net à toutes les tailles. [color] : trait et arrivée ;
/// [background] : couleur du fond (intérieur des points).
class AppMark extends StatelessWidget {
  const AppMark({
    super.key,
    this.size = 32,
    this.color = const Color(0xFF2563EB),
    this.background = Colors.white,
  });

  final double size;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Suivi Agent',
    image: true,
    child: CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(color, background),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color, this.background);

  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    // M16 52 C16 40 48 43 48 32 S16 23 16 12
    final route = Path()
      ..moveTo(16, 52)
      ..cubicTo(16, 40, 48, 43, 48, 32)
      ..cubicTo(48, 21, 16, 23, 16, 12);
    canvas.drawPath(route, stroke);
    // Départ : point creux.
    canvas.drawCircle(const Offset(16, 52), 6.5, Paint()..color = background);
    canvas.drawCircle(
      const Offset(16, 52),
      6.5,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    // Arrivée : point plein.
    canvas.drawCircle(const Offset(16, 12), 8, Paint()..color = color);
    canvas.drawCircle(const Offset(16, 12), 3, Paint()..color = background);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.color != color || old.background != background;
}
