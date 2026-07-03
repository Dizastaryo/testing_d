import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'seeu_bottom_sheet.dart';
import 'seeu_theme_colors.dart';
import 'tappable.dart';
import 'tokens.dart';

/// Единый стеклянный диалог подтверждения (вместо Material `AlertDialog`).
/// Возвращает `true` при подтверждении, иначе `false`.
///
/// ```dart
/// if (await showSeeUConfirm(context, title: 'Удалить?', message: '...',
///     confirmLabel: 'Удалить', destructive: true)) { ... }
/// ```
Future<bool> showSeeUConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Подтвердить',
  String cancelLabel = 'Отмена',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showSeeUBottomSheet<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.seeuColors;
      final Color accent = destructive ? SeeUColors.danger : SeeUColors.accent;
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.of(ctx).padding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Center(
                    child: PhosphorIcon(icon, color: accent, size: 26)),
              ),
              const SizedBox(height: 14),
            ],
            Text(title,
                textAlign: TextAlign.center,
                style: SeeUTypography.displayS.copyWith(color: c.ink)),
            if (message != null && message.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: SeeUTypography.body.copyWith(color: c.ink2)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ConfirmButton(
                    label: cancelLabel,
                    filled: false,
                    accent: accent,
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ConfirmButton(
                    label: confirmLabel,
                    filled: true,
                    accent: accent,
                    onTap: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}

/// Пилюля-действие для кастомных стеклянных шитов (напр. диалог с полем
/// ввода), где `showSeeUConfirm` не подходит из-за отсутствия произвольного
/// контента. `filled: true` — сплошная заливка [color] (по умолчанию accent);
/// иначе — outline с текстом [color] (по умолчанию — обычный ink).
class SeeUDialogAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool filled;

  const SeeUDialogAction({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final Color fg = filled ? Colors.white : (color ?? c.ink);
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? (color ?? SeeUColors.accent) : Colors.transparent,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: filled ? null : Border.all(color: c.line, width: 1),
        ),
        child: Text(
          label,
          style: SeeUTypography.subtitle.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final String label;
  final bool filled;
  final Color accent;
  final VoidCallback onTap;
  const _ConfirmButton({
    required this.label,
    required this.filled,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: filled ? null : Border.all(color: c.line, width: 1),
        ),
        child: Text(
          label,
          style: SeeUTypography.subtitle.copyWith(
            color: filled ? Colors.white : c.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
