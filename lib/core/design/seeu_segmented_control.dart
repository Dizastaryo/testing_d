import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'seeu_theme_colors.dart';
import 'tappable.dart';
import 'tokens.dart';

/// Единый сегмент-контрол (в сборах жило 4 разных реализации).
/// Плоская pill-полоса на `surface2`, активный сегмент — `accentSoft`-тинт +
/// accent-hairline + accent-текст (акцент как акцент, не заливка).
class SeeUSegmentedControl extends StatelessWidget {
  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const SeeUSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        border: Border.all(color: c.line, width: 0.5),
      ),
      child: Row(
        children: List.generate(segments.length, (i) {
          final bool active = i == selectedIndex;
          return Expanded(
            child: Tappable.faded(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: SeeUMotion.quick,
                curve: SeeUMotion.smooth,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? c.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                  border: active
                      ? Border.all(
                          color: SeeUColors.accent.withValues(alpha: 0.55),
                          width: 0.8,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  segments[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeeUTypography.caption.copyWith(
                    color: active ? SeeUColors.accent : c.ink2,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Единый числовой степпер «− значение +» (дублировался в сборах).
class SeeUStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  /// Форматирование значения (напр. `(v) => '$v чел.'`).
  final String Function(int value)? format;

  const SeeUStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.format,
  });

  Widget _btn(BuildContext context, IconData icon, bool enabled, int delta) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: enabled ? () => onChanged((value + delta).clamp(min, max)) : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.surface2,
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: Center(
          child: PhosphorIcon(
            icon,
            size: 16,
            color: enabled ? SeeUColors.accent : c.ink4,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(context, PhosphorIcons.minus(), value > min, -1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            format?.call(value) ?? '$value',
            style: SeeUTypography.subtitle.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        _btn(context, PhosphorIcons.plus(), value < max, 1),
      ],
    );
  }
}
