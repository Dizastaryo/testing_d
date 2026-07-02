import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tappable.dart';

/// Круглая стеклянная кнопка поверх медиа (видео/фото/эфир): свой backdrop-blur
/// + градиент (верхний блик → нижний тинт) + тонкий светлый бордюр + press-scale.
/// Эталон — `CameraGlassButton`. Использовать для close/share/mute/action над
/// контентом (звонки, эфиры, reels, сторис, полноэкранные вьюеры).
class SeeUGlassCircleButton extends StatelessWidget {
  /// Обычно `PhosphorIcon(..., color: Colors.white)`.
  final Widget icon;
  final VoidCallback? onTap;
  final double size;
  final double blur;

  /// Акцентный оттенок стекла (напр. `SeeUColors.accent`/`danger` для активного
  /// состояния). null → нейтральное стекло.
  final Color? tint;

  const SeeUGlassCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.blur = 18,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final Color top = (tint ?? Colors.white).withValues(alpha: 0.14);
    final Color bottom =
        tint != null ? tint!.withValues(alpha: 0.34) : Colors.black.withValues(alpha: 0.28);
    final Color border =
        (tint ?? Colors.white).withValues(alpha: tint != null ? 0.45 : 0.18);

    return Tappable.scaled(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, bottom],
              ),
              border: Border.all(color: border, width: 0.8),
            ),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
