import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'seeu_theme_colors.dart';
import 'tokens.dart';

/// Матовая (frosted-glass) шапка приложения — единый glass-бар вместо десятков
/// плоских `AppBar`/`Container`-шапок. Плавает поверх контента: свой
/// `BackdropFilter` (blur) + мягкий тинт фона + нижний hairline.
///
/// Использование как шапки экрана:
/// ```dart
/// Scaffold(
///   extendBodyBehindAppBar: true,
///   body: Stack(children: [ content, Align(alignment: Alignment.topCenter,
///     child: SeeUGlassBar(titleText: 'Заголовок', leading: BackButton(), actions: [...])) ]),
/// )
/// ```
/// или как pinned-заголовок в `CustomScrollView` (обернуть в SliverPersistentHeader).
class SeeUGlassBar extends StatelessWidget {
  /// Готовый заголовок (обычно `Text(..., style: SeeUTypography.displayS)`).
  final Widget? title;

  /// Быстрый серифный заголовок (перекрывается [title], если задан оба).
  final String? titleText;

  /// Мелкая editorial-метка над заголовком (капс/трекинг). Автоматически
  /// приводится к верхнему регистру и стилю `SeeUTypography.kicker`.
  final String? kicker;

  /// Левый слот (обычно кнопка «назад»).
  final Widget? leading;

  /// Правые действия.
  final List<Widget> actions;

  /// Сила размытия. По умолчанию — панельный blur из эталона камеры.
  final double blur;

  /// Показывать нижний hairline-разделитель.
  final bool hairline;

  /// Центрировать заголовок (иначе — прижат влево, editorial-стиль).
  final bool centerTitle;

  const SeeUGlassBar({
    super.key,
    this.title,
    this.titleText,
    this.kicker,
    this.leading,
    this.actions = const [],
    this.blur = 24,
    this.hairline = true,
    this.centerTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    // Морозный тинт: полупрозрачный фон темы (крем/тёмный) поверх blur.
    final tint = SeeUColors.background.withValues(alpha: 0.72);

    final Widget titleWidget = title ??
        (titleText == null
            ? const SizedBox.shrink()
            : Text(
                titleText!,
                style: SeeUTypography.displayS.copyWith(color: c.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ));

    final Widget titleColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (kicker != null && kicker!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              kicker!.toUpperCase(),
              style: SeeUTypography.kicker.copyWith(color: c.ink3),
            ),
          ),
        titleWidget,
      ],
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: tint,
            border: hairline
                ? Border(bottom: BorderSide(color: c.line, width: 0.5))
                : null,
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 4),
                  ] else
                    const SizedBox(width: 8),
                  Expanded(
                    child: centerTitle
                        ? Center(child: titleColumn)
                        : titleColumn,
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
