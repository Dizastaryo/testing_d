import 'package:flutter/material.dart';

import 'seeu_theme_colors.dart';
import 'tokens.dart';

/// Бейдж роли участника с иерархией: primary (Создатель/владелец) — акцент,
/// secondary (Админ) — нейтраль/outline. Раньше оба были `accent 0.12` и не
/// различались.
class SeeURoleBadge extends StatelessWidget {
  final String label;

  /// true → главная роль (Создатель) — акцентная заливка.
  final bool primary;

  const SeeURoleBadge({super.key, required this.label, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: primary
            ? SeeUColors.accent.withValues(alpha: 0.14)
            : c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        border: Border.all(
          color: primary
              ? SeeUColors.accent.withValues(alpha: 0.5)
              : c.line,
          width: 0.8,
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: SeeUTypography.kicker.copyWith(
          color: primary ? SeeUColors.accent : c.ink2,
        ),
      ),
    );
  }
}
