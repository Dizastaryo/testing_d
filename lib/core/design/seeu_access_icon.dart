import 'dart:math' as math;

import 'package:flutter/material.dart';

/// §05: фирменная иконка «доступа» — человек в пунктирном круге
/// (SVG-эквивалент: circle r9 dasharray 2.2/3.2 + голова r2.5 + плечи,
/// stroke 1.8, скруглённые концы). Используется в топбаре профиля и на
/// кнопке «Запросить доступ».
class SeeUAccessIcon extends StatelessWidget {
  final double size;
  final Color color;
  const SeeUAccessIcon({super.key, this.size = 23, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AccessIconPainter(color),
    );
  }
}

class _AccessIconPainter extends CustomPainter {
  final Color color;
  _AccessIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24; // дизайн-сетка 24
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Пунктирный круг r9 (dash 2.2, gap 3.2).
    final center = Offset(12 * s, 12 * s);
    final r = 9.0 * s;
    const dash = 2.2, gap = 3.2;
    final circumference = 2 * math.pi * 9.0; // в единицах сетки
    final steps = (circumference / (dash + gap)).floor();
    final dashAngle = dash / 9.0; // радианы: длина дуги / радиус
    final stepAngle = (2 * math.pi) / steps;
    for (var i = 0; i < steps; i++) {
      final start = i * stepAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start,
        dashAngle,
        false,
        paint,
      );
    }

    // Голова: круг r2.5 в (12, 9.7).
    canvas.drawCircle(Offset(12 * s, 9.7 * s), 2.5 * s, paint);

    // Плечи: дуга M7.6 16.8 C7.6 13.7, 9.8 13.1, 12 13.1 C14.2 13.1, 16.4 13.7, 16.4 16.8
    final path = Path()
      ..moveTo(7.6 * s, 16.8 * s)
      ..cubicTo(7.6 * s, 13.7 * s, 9.8 * s, 13.1 * s, 12 * s, 13.1 * s)
      ..cubicTo(14.2 * s, 13.1 * s, 16.4 * s, 13.7 * s, 16.4 * s, 16.8 * s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_AccessIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
