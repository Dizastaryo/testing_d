import 'dart:ui';
import 'package:flutter/material.dart';
import 'tokens.dart';

class SeeUCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool _glass;
  final double _blur;
  final Color? _glassTint;

  const SeeUCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = SeeURadii.card,
    this.onTap,
  })  : _glass = false,
        _blur = 0,
        _glassTint = null;

  /// Frosted-glass вариант. Поверх blur'а — полупрозрачный fill цвета [tint]
  /// (по умолчанию — оранжевый brand). Подходит для bottom-sheet'ов, top-bar
  /// поверх скроллящегося контента, плавающего mini-player'а.
  const SeeUCard.glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = SeeURadii.card,
    this.onTap,
    double blur = 18,
    Color? tint,
  })  : _glass = true,
        _blur = blur,
        _glassTint = tint;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final body = Padding(padding: padding, child: child);

    if (!_glass) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: SeeUColors.surfaceElevated,
            borderRadius: r,
            boxShadow: SeeUShadows.md,
          ),
          child: body,
        ),
      );
    }

    // Glass: blur of underlying content + soft orange fill + 1px hairline.
    final tint = _glassTint ?? SeeUColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tint.withValues(alpha: 0.14),
                  tint.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: tint.withValues(alpha: 0.18),
                width: 1,
              ),
              borderRadius: r,
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
