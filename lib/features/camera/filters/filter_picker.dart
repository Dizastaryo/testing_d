import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import 'filter_presets.dart';
import 'filter_state.dart';

/// Picker пресетов + кнопка «Настроить» для перехода в slider-sheet.
/// Selected определяется по `selectedPresetId`. Если юзер крутил slider'ы
/// вручную → preset снимается, на UI показывается «Свой» с ✓ маркером.
class FilterPicker extends StatelessWidget {
  final String? selectedPresetId;
  final FilterState state;
  final ValueChanged<FilterPreset?> onPresetSelected;
  final VoidCallback onOpenSliders;

  const FilterPicker({
    super.key,
    required this.selectedPresetId,
    required this.state,
    required this.onPresetSelected,
    required this.onOpenSliders,
  });

  @override
  Widget build(BuildContext context) {
    final isCustomNoPreset =
        selectedPresetId == null && !state.isIdentity;
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: FilterPresets.all.length + 2,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            final off = state.isIdentity;
            return _FilterBubble(
              isSelected: off,
              label: 'Без',
              onTap: () {
                HapticFeedback.selectionClick();
                onPresetSelected(null);
              },
              child: Icon(
                PhosphorIcons.x(),
                color: Colors.white.withValues(alpha: 0.85),
                size: 22,
              ),
            );
          }
          if (i == FilterPresets.all.length + 1) {
            // Sliders entry — всегда последняя ячейка.
            return _FilterBubble(
              isSelected: isCustomNoPreset,
              label: isCustomNoPreset ? 'Свой' : 'Точнее',
              onTap: () {
                HapticFeedback.mediumImpact();
                onOpenSliders();
              },
              child: const Icon(
                Icons.tune,
                color: Colors.white,
                size: 22,
              ),
            );
          }
          final p = FilterPresets.all[i - 1];
          final isSelected = selectedPresetId == p.id;
          return _FilterBubble(
            isSelected: isSelected,
            label: p.label,
            onTap: () {
              HapticFeedback.selectionClick();
              onPresetSelected(p);
            },
            child: Icon(p.previewIcon, color: Colors.white, size: 22),
          );
        },
      ),
    );
  }
}

class _FilterBubble extends StatelessWidget {
  final bool isSelected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  const _FilterBubble({
    required this.isSelected,
    required this.label,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: SeeUMotion.quick,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(
                color: isSelected
                    ? SeeUColors.accent
                    : Colors.white.withValues(alpha: 0.18),
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: Center(child: child),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isSelected
                  ? SeeUColors.accent
                  : Colors.white.withValues(alpha: 0.75),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
