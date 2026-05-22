import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/design/tokens.dart';

class ScannerRadarPainter extends CustomPainter {
  final double sweepProgress;
  final double pulseProgress;

  ScannerRadarPainter({required this.sweepProgress, required this.pulseProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const color = SeeUColors.accent;

    for (var i = 1; i <= 3; i++) {
      final radius = maxRadius * (i / 3.0) * 0.75 + maxRadius * 0.25;
      canvas.drawCircle(center, radius, Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5);
    }

    for (var i = 0; i < 3; i++) {
      final t = (pulseProgress + i * 0.33) % 1.0;
      final radius = 30 + t * (maxRadius - 30);
      final opacity = (1.0 - t) * 0.5;
      canvas.drawCircle(center, radius, Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * (1.0 - t) + 0.5);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    final sweepAngle = sweepProgress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - 1.4,
        endAngle: sweepAngle,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.4),
          color.withValues(alpha: 0.5),
        ],
        stops: const [0.0, 0.6, 0.95, 1.0],
        tileMode: TileMode.clamp,
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: maxRadius));
    canvas.drawCircle(Offset.zero, maxRadius, sweepPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScannerRadarPainter old) => true;
}

class ScannerEyeMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);

    final eyePath = Path();
    eyePath.moveTo(s * 0.12, s / 2);
    eyePath.quadraticBezierTo(s * 0.35, s * 0.2, s / 2, s * 0.2);
    eyePath.quadraticBezierTo(s * 0.65, s * 0.2, s * 0.88, s / 2);
    eyePath.quadraticBezierTo(s * 0.65, s * 0.8, s / 2, s * 0.8);
    eyePath.quadraticBezierTo(s * 0.35, s * 0.8, s * 0.12, s / 2);
    eyePath.close();
    canvas.drawPath(eyePath, Paint()..color = const Color(0xFFFFF6F0));

    final irisPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        colors: [const Color(0xFFFF6E50), const Color(0xFFC12A1A)],
      ).createShader(Rect.fromCircle(center: center, radius: s * 0.18));
    canvas.drawCircle(center, s * 0.18, irisPaint);

    canvas.drawCircle(Offset(s * 0.44, s * 0.44), s * 0.04, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
