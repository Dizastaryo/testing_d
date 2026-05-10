import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'tokens.dart';

/// Particle-burst при double-tap-like: 12 маленьких сердечек разлетаются от
/// центра по случайным углам с лёгким разбросом масштаба и поворота.
/// Поверх существующей большой heart-анимации — игривый штрих, без heavy
/// Lottie-зависимости.
///
/// Использование: положить виджет в `Stack` поверх контента и вызвать
/// `key.currentState!.burst()` (или хранить контроллер и дёргать его).
/// Фактически проще — экспонирует [GlobalKey<SeeUHeartBurstState>], тогда
/// родитель зовёт `key.currentState?.burst()` после `setState`.
class SeeUHeartBurst extends StatefulWidget {
  final double size; // радиус разлёта
  final Color color;
  final int particleCount;

  const SeeUHeartBurst({
    super.key,
    this.size = 140,
    this.color = SeeUColors.like,
    this.particleCount = 12,
  });

  @override
  State<SeeUHeartBurst> createState() => SeeUHeartBurstState();
}

class SeeUHeartBurstState extends State<SeeUHeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late List<_Particle> _particles;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _particles = _spawn();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Triggered from parent. Re-rolls particles for each burst — каждое
  /// double-tap даёт уникальный паттерн разлёта (живее ощущается).
  void burst() {
    setState(() {
      _particles = _spawn();
    });
    _ctrl.forward(from: 0);
  }

  List<_Particle> _spawn() {
    return List.generate(widget.particleCount, (i) {
      // Равномерный угол + jitter, чтобы не выглядело как чётко разделённые лучи.
      final baseAngle = (2 * math.pi * i) / widget.particleCount;
      final jitter = (_rng.nextDouble() - 0.5) * 0.4;
      return _Particle(
        angle: baseAngle + jitter,
        distance: widget.size * (0.55 + _rng.nextDouble() * 0.45),
        scale: 0.5 + _rng.nextDouble() * 0.6,
        rotation: (_rng.nextDouble() - 0.5) * 0.7,
        delay: _rng.nextDouble() * 0.15, // 0..150ms задержка
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: _particles.map((p) {
              // Локальная фаза 0..1 с учётом delay'я.
              final t = ((_ctrl.value - p.delay) / (1.0 - p.delay))
                  .clamp(0.0, 1.0);
              if (t == 0) return const SizedBox.shrink();
              final eased = Curves.easeOutCubic.transform(t);
              final dx = math.cos(p.angle) * p.distance * eased;
              final dy = math.sin(p.angle) * p.distance * eased;
              // Fade out across last 40%
              final opacity = (1.0 - ((t - 0.6) / 0.4)).clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(dx, dy),
                child: Transform.rotate(
                  angle: p.rotation * eased,
                  child: Transform.scale(
                    scale: p.scale * (0.6 + 0.4 * eased),
                    child: Opacity(
                      opacity: opacity,
                      child: Icon(
                        PhosphorIconsFill.heart,
                        color: widget.color,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double distance;
  final double scale;
  final double rotation;
  final double delay;

  _Particle({
    required this.angle,
    required this.distance,
    required this.scale,
    required this.rotation,
    required this.delay,
  });
}
