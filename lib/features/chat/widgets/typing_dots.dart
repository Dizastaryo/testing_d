import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated three dots (●●●) that pulse in sequence. Used for "typing..." indicator.
class TypingDots extends StatefulWidget {
  final Color color;
  final double size;
  const TypingDots({super.key, required this.color, this.size = 6});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
            final bounce = math.sin(phase * math.pi);
            return Container(
              width: widget.size,
              height: widget.size,
              margin: EdgeInsets.only(right: i < 2 ? 3 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.4 + 0.6 * bounce),
              ),
            );
          }),
        );
      },
    );
  }
}
