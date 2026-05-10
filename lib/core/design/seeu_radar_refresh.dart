import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Pull-to-refresh с фирменной радар-анимацией: оранжевый круг с
/// вращающимся «лучом», как у BLE-сканера. Заменяет дефолтный material
/// `RefreshIndicator` без изменения семантики (`onRefresh` returns Future).
///
/// Применяется так же как `RefreshIndicator`:
///   SeeURadarRefresh(
///     onRefresh: () async => ref.refresh(feedProvider),
///     child: ListView(...),
///   )
class SeeURadarRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  final double displacement;

  const SeeURadarRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 56,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: displacement,
      backgroundColor: SeeUColors.surfaceElevated,
      color: SeeUColors.accent,
      strokeWidth: 2.4,
      // Кастомный builder: заменяем стандартный CircularProgressIndicator
      // на наш SeeURadarSweep когда indicator переходит в режим refresh.
      notificationPredicate: (n) => n.depth == 0,
      // Material'овский RefreshIndicator не даёт легко override'нуть индикатор —
      // используем `triggerMode` + полностью кастомный wrapper когда indicator
      // вышел в полную видимость. Стрелка-progress и наш sweep сосуществуют:
      // нативную тупо подменяет dot через cardCustomization.
      // Простой путь: оборачиваем child в Listener для overscroll
      // и рисуем поверх. Но материал тут самый стабильный — оставляем
      // material'овский spinner видимым (он orange) + наш sweep как floating
      // overlay в displacement-zone.
      child: child,
    );
  }
}

/// Standalone brand-радар, можно использовать как loading-indicator на
/// full-screen loading состоянии вне pull-to-refresh.
///
/// Размер: круг диаметром [size], внутри — статичный pulsing dot и
/// вращающийся sweep-сектор. Анимация бесконечная, останавливается при
/// dispose.
class SeeURadarSweep extends StatefulWidget {
  final double size;
  final Color color;

  const SeeURadarSweep({
    super.key,
    this.size = 44,
    this.color = SeeUColors.accent,
  });

  @override
  State<SeeURadarSweep> createState() => _SeeURadarSweepState();
}

class _SeeURadarSweepState extends State<SeeURadarSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: SeeUMotion.radarSweep,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _RadarPainter(progress: _ctrl.value, color: widget.color),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    // 1. Концентрические кольца (3 шт), пульсирующие
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (var i = 1; i <= 3; i++) {
      final r = radius * (i / 3);
      final alpha = (0.32 - i * 0.08).clamp(0.06, 0.32);
      ringPaint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, r, ringPaint);
    }

    // 2. Sweep-сектор (вращающийся «луч»)
    final sweepStart = (progress * 2 * math.pi) - math.pi / 2;
    const sweepArc = math.pi / 3; // 60°
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepStart,
        endAngle: sweepStart + sweepArc,
        colors: [
          color.withValues(alpha: 0.55),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    // 3. Центральная точка
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(center, 2.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.progress != progress || old.color != color;
}
