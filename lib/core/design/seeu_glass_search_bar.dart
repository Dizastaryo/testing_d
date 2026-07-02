import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'seeu_theme_colors.dart';
import 'tokens.dart';

/// Плавающий стеклянный поиск — единый glass-search вместо ~10 переизобретённых
/// `surface2`-полей с разными радиусами. Матовая pill-оболочка (blur) + иконка
/// поиска + поле + крестик очистки.
class SeeUGlassSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final double blur;
  final EdgeInsetsGeometry padding;

  const SeeUGlassSearchBar({
    super.key,
    this.controller,
    this.hintText = 'Поиск',
    this.onChanged,
    this.onClear,
    this.focusNode,
    this.blur = 24,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: SeeUColors.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18), width: 0.8),
            ),
            child: Row(
              children: [
                PhosphorIcon(PhosphorIcons.magnifyingGlass(),
                    size: 18, color: c.ink3),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    style: SeeUTypography.body.copyWith(color: c.ink),
                    cursorColor: SeeUColors.accent,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: hintText,
                      hintStyle:
                          SeeUTypography.body.copyWith(color: c.ink3),
                    ),
                  ),
                ),
                if (onClear != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: PhosphorIcon(PhosphorIcons.x(),
                          size: 16, color: c.ink3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
