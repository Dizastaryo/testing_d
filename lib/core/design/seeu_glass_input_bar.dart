import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'seeu_theme_colors.dart';
import 'tappable.dart';
import 'tokens.dart';

/// Стеклянный бар ввода (чат / room / sbor-chat): матовая оболочка (blur) +
/// внутреннее ПЛОСКОЕ pill-поле (без второго блюра — no glass-on-glass) +
/// круглая accent-кнопка отправки. Заменяет плоские `Container(c.bg)`-бары.
class SeeUGlassInputBar extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final VoidCallback? onSend;
  final ValueChanged<String>? onChanged;

  /// Левый слот (напр. кнопка вложения) — рендерится как плоская nested-кнопка.
  final Widget? leading;

  /// Активна ли отправка (иначе кнопка приглушена).
  final bool canSend;
  final double blur;

  const SeeUGlassInputBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = 'Сообщение…',
    this.onSend,
    this.onChanged,
    this.leading,
    this.canSend = true,
    this.blur = 24,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: SeeUColors.background.withValues(alpha: 0.72),
            border: Border(top: BorderSide(color: c.line, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    // Плоское внутреннее поле — стекло не вкладываем.
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                        border: Border.all(color: c.line, width: 0.5),
                      ),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: onChanged,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
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
                  ),
                  const SizedBox(width: 8),
                  Tappable.scaled(
                    onTap: canSend ? onSend : null,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canSend
                            ? SeeUColors.accent
                            : SeeUColors.accent.withValues(alpha: 0.4),
                      ),
                      child: Center(
                        child: PhosphorIcon(
                          PhosphorIcons.paperPlaneTilt(
                              PhosphorIconsStyle.fill),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
