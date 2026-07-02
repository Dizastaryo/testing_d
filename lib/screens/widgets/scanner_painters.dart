import 'package:flutter/material.dart';
import '../../core/design/tokens.dart';

/// Мягкий «дышащий» радар (без сонар-развёртки): статичные направляющие кольца
/// + расходящиеся тёплые волны, которые плавно тают на краю. Центр — фото
/// профиля пользователя (рисуется поверх, не здесь).
class ScannerRadarPainter extends CustomPainter {
  final double pulseProgress;

  ScannerRadarPainter({required this.pulseProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const color = SeeUColors.accent;

    // Мягкое центральное свечение — «тепло» пользователя.
    canvas.drawCircle(
      center,
      maxRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: maxRadius)),
    );

    // Дышащие размытые гало — 3 концентрических волны, расходятся из центра
    // и мягко тают на краю. Без сонар-луча и без жёстких колец.
    for (var i = 0; i < 3; i++) {
      final t = (pulseProgress + i * 0.33) % 1.0;
      final eased = Curves.easeOut.transform(t);
      final radius = 40 + eased * (maxRadius - 40);
      final opacity = (1.0 - t) * 0.28;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7.0 * (1.0 - t) + 2.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ScannerRadarPainter old) =>
      old.pulseProgress != pulseProgress;
}
