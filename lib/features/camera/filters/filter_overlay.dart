import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'filter_state.dart';

/// Обёртка вокруг preview. Применяет ColorMatrix (brightness/contrast/
/// saturation/warmth) через ColorFiltered, поверх — vignette gradient и
/// анимированный grain noise (~18 fps смена seed).
class FilterOverlay extends StatefulWidget {
  final FilterState state;
  final Widget child;

  const FilterOverlay({
    super.key,
    required this.state,
    required this.child,
  });

  @override
  State<FilterOverlay> createState() => _FilterOverlayState();
}

class _FilterOverlayState extends State<FilterOverlay>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  int _grainSeed = 0;
  Duration _lastUpdate = Duration.zero;

  // Обновляем seed ~18 раз в секунду — достаточно для плёночного ощущения,
  // не грузит CPU как 60 fps.
  static const _kGrainInterval = Duration(milliseconds: 56);

  @override
  void initState() {
    super.initState();
    if (widget.state.grain > 0) _startTicker();
  }

  @override
  void didUpdateWidget(FilterOverlay old) {
    super.didUpdateWidget(old);
    final wasActive = old.state.grain > 0;
    final isActive = widget.state.grain > 0;
    if (!wasActive && isActive) _startTicker();
    if (wasActive && !isActive) _stopTicker();
  }

  void _startTicker() {
    if (_ticker != null) return;
    _ticker = createTicker((elapsed) {
      if (elapsed - _lastUpdate >= _kGrainInterval) {
        _lastUpdate = elapsed;
        setState(() => _grainSeed++);
      }
    })..start();
  }

  void _stopTicker() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    Widget filtered = widget.child;
    if (!s.isIdentity) {
      filtered = ColorFiltered(
        colorFilter: ColorFilter.matrix(s.toMatrix()),
        child: filtered,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        filtered,
        if (s.vignette > 0)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.9,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: s.vignette * 0.75),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        // RepaintBoundary изолирует grain от ColorFiltered —
        // при смене seed перерисовывается только grain-слой.
        if (s.grain > 0)
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _GrainPainter(s.grain, _grainSeed),
              ),
            ),
          ),
        // Halation: тёплый ореол плёнки вокруг ярких зон (screen blend).
        if (s.halation > 0)
          IgnorePointer(
            child: CustomPaint(
              painter: _HalationPainter(s.halation),
            ),
          ),
      ],
    );
  }
}

/// Анимированный grain — seed меняется каждые ~56ms, Random(seed) даёт
/// новое распределение точек. Два размера зерна (0.6 / 1.4px) имитируют
/// смесь мелкого и крупного зерна плёнки.
class _GrainPainter extends CustomPainter {
  final double intensity; // 0..1
  final int seed;

  _GrainPainter(this.intensity, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final count = (intensity * 6000).round().clamp(0, 14000);
    final rng = math.Random(seed);
    final bright = Paint()
      ..color = Colors.white.withValues(alpha: intensity * 0.06);
    final dark = Paint()
      ..color = Colors.black.withValues(alpha: intensity * 0.10);
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      // ~60% мелкое зерно, ~40% крупное
      final r = rng.nextDouble() < 0.6 ? 0.6 : 1.4;
      canvas.drawCircle(
        Offset(x, y),
        r,
        rng.nextDouble() < 0.5 ? bright : dark,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter old) =>
      old.intensity != intensity || old.seed != seed;
}

/// Запекает grain в финальное фото. Использует фиксированный seed = 42.
void bakeGrain(Canvas canvas, Size size, double intensity) {
  if (intensity <= 0) return;
  _GrainPainter(intensity, 42).paint(canvas, size);
}

/// Запекает halation в финальное фото.
void bakeHalation(Canvas canvas, Size size, double intensity) {
  if (intensity <= 0) return;
  _HalationPainter(intensity).paint(canvas, size);
}

/// Halation — тёплый ореол, имитирующий свечение вокруг ярких зон плёнки.
/// Рисует мягкий радиальный градиент (центр→края) в режиме BlendMode.screen,
/// что создаёт эффект «засветки» без пересветки тёмных участков.
class _HalationPainter extends CustomPainter {
  final double intensity; // 0..1

  _HalationPainter(this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.92,
          colors: [
            Colors.transparent,
            const Color(0xFFFF6B35).withValues(alpha: intensity * 0.28),
          ],
          stops: const [0.35, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _HalationPainter old) =>
      old.intensity != intensity;
}
