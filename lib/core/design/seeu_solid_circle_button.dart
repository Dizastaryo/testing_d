import 'package:flutter/material.dart';

import 'seeu_theme_colors.dart';
import 'tappable.dart';

/// Круглая кнопка на СПЛОШНОМ фоне (шапки лент/сборов/профиля и т.п.).
///
/// В отличие от [SeeUGlassCircleButton] (стекло, рассчитанное на фон-МЕДИА —
/// видео/фото/эфир), здесь сплошная тёплая `surface2` + hairline-бордюр: над
/// непрозрачным фоном полупрозрачное «стекло» мутнеет в невнятный серый.
/// [tint] задаёт цветной CTA (напр. коралл) — тогда бордюр не рисуем.
class SeeUSolidCircleButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final double size;
  final Color? tint;

  const SeeUSolidCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tint ?? c.surface2,
          border: tint == null ? Border.all(color: c.line) : null,
        ),
        child: Center(child: icon),
      ),
    );
  }
}
