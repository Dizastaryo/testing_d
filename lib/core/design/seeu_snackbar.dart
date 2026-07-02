import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'seeu_theme_colors.dart';
import 'tokens.dart';

/// Единый брендовый тост вместо ~350 сырых Material `SnackBar` в приложении.
/// Плавающий, скруглённый, на surface с hairline-бордюром, Phosphor-иконка +
/// текст на `SeeUColors`. Использовать ВЕЗДЕ вместо `ScaffoldMessenger...SnackBar`.
///
/// ```dart
/// showSeeUSnackBar(context, 'Ссылка скопирована', icon: PhosphorIcons.link());
/// showSeeUSnackBar(context, 'Не удалось', icon: PhosphorIcons.warning(), tone: SeeUTone.danger);
/// ```
enum SeeUTone { neutral, success, danger }

void showSeeUSnackBar(
  BuildContext context,
  String message, {
  IconData? icon,
  SeeUTone tone = SeeUTone.neutral,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 3),
}) {
  final c = context.seeuColors;
  final Color accentColor = switch (tone) {
    SeeUTone.success => SeeUColors.success,
    SeeUTone.danger => SeeUColors.danger,
    SeeUTone.neutral => SeeUColors.accent,
  };
  final IconData resolved = icon ??
      switch (tone) {
        SeeUTone.success => PhosphorIcons.checkCircle(),
        SeeUTone.danger => PhosphorIcons.warning(),
        SeeUTone.neutral => PhosphorIcons.info(),
      };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surface,
        elevation: 8,
        duration: duration,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          side: BorderSide(color: c.line, width: 0.5),
        ),
        content: Row(
          children: [
            PhosphorIcon(resolved, size: 18, color: accentColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: SeeUTypography.body.copyWith(color: c.ink)),
            ),
          ],
        ),
        action: action,
      ),
    );
}
