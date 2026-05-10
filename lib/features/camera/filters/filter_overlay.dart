import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'filter_state.dart';

/// Обёртка вокруг preview. Применяет ColorMatrix (brightness/contrast/
/// saturation/warmth) через ColorFiltered, поверх — vignette gradient и
/// grain noise.
class FilterOverlay extends StatelessWidget {
  final FilterState state;
  final Widget child;

  const FilterOverlay({
    super.key,
    required this.state,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget filtered = child;
    if (!state.isIdentity) {
      filtered = ColorFiltered(
        colorFilter: ColorFilter.matrix(state.toMatrix()),
        child: filtered,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        filtered,
        if (state.vignette > 0)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.9,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: state.vignette * 0.75),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        if (state.grain > 0)
          IgnorePointer(
            child: CustomPaint(painter: _GrainPainter(state.grain)),
          ),
      ],
    );
  }
}

/// Простой grain — псевдо-рандомные точки в seed'е по интенсивности.
/// Не animated (статичный noise) — для preview-overlay'я этого достаточно.
class _GrainPainter extends CustomPainter {
  final double intensity; // 0..1
  _GrainPainter(this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    final n = (intensity * 4000).round().clamp(0, 8000);
    final rng = math.Random(42);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: intensity * 0.05);
    final paintD = Paint()
      ..color = Colors.black.withValues(alpha: intensity * 0.08);
    for (var i = 0; i < n; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = rng.nextDouble() < 0.5 ? 0.5 : 1.0;
      canvas.drawCircle(Offset(x, y), r,
          rng.nextDouble() < 0.5 ? paint : paintD);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter old) =>
      old.intensity != intensity;
}
