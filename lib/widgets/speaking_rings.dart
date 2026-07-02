import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Пульсирующие кольца вокруг аватара — визуализация голосовой активности.
/// [audioLevel] 0.0..1.0 — нормализованный уровень звука.
/// Кольца видны только когда level > 0.05; масштаб и прозрачность
/// пропорциональны громкости. Переходы сглажены TweenAnimationBuilder.
/// Используется в CallScreen и RoomScreen._ParticipantBubble.
class SpeakingRings extends StatelessWidget {
  final double audioLevel;
  final Widget child;

  /// Базовый диаметр дочернего виджета — кольца рисуются с этим размером
  /// и масштабируются наружу, не задевая сам аватар.
  final double size;

  final Color color;

  const SpeakingRings({
    super.key,
    required this.audioLevel,
    required this.child,
    required this.size,
    this.color = const Color(0xFF2FA84F),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: audioLevel.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      builder: (_, lv, ch) {
        final show = lv > 0.05;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none, // кольца могут выходить за bounds
          children: [
            // Outer ring — дальше, прозрачнее
            if (show)
              Transform.scale(
                scale: 1.0 + lv * 0.44,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(
                          alpha: math.max(0.0, lv * 0.30)),
                      width: 2,
                    ),
                  ),
                ),
              ),
            // Inner ring — ближе, насыщеннее
            if (show)
              Transform.scale(
                scale: 1.0 + lv * 0.22,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(
                          alpha: math.max(0.0, lv * 0.55)),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ch!,
          ],
        );
      },
      child: child,
    );
  }
}
