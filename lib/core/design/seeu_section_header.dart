import 'package:flutter/material.dart';

import 'seeu_theme_colors.dart';
import 'tokens.dart';

/// Editorial-заголовок секции: мелкая mono-рубрика (kicker, капс + трекинг),
/// опциональный серифный заголовок, опциональное действие справа и hairline.
/// Заменяет ~20 копипастнутых `TextStyle('JetBrains Mono')`-заголовков.
class SeeUSectionHeader extends StatelessWidget {
  /// Рубрика-eyebrow (приводится к верхнему регистру).
  final String kicker;

  /// Крупный серифный заголовок (Fraunces). null → только kicker.
  final String? title;

  /// Действие справа (напр. `Text('Все →')` / кнопка).
  final Widget? action;

  /// Нижний hairline-разделитель.
  final bool hairline;

  final EdgeInsetsGeometry padding;

  const SeeUSectionHeader({
    super.key,
    required this.kicker,
    this.title,
    this.action,
    this.hairline = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kicker.toUpperCase(),
                        style: SeeUTypography.kicker.copyWith(color: c.ink3)),
                    if (title != null && title!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(title!,
                            style: SeeUTypography.displayS
                                .copyWith(color: c.ink)),
                      ),
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
          if (hairline)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Divider(height: 0.5, thickness: 0.5, color: c.line),
            ),
        ],
      ),
    );
  }
}
