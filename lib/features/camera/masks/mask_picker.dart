import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import 'mask_catalog.dart';

/// Горизонтальная плашка масок над bottom-controls. Первая ячейка — «без
/// маски» (X-иконка), затем preview каждой маски. Selected — orange-ring 2px.
class MaskPicker extends StatelessWidget {
  final MaskDescriptor? selected;
  final ValueChanged<MaskDescriptor?> onChanged;

  const MaskPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: MaskCatalog.all.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            final off = selected == null;
            return _MaskBubble(
              isSelected: off,
              label: 'Без',
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(null);
              },
              child: Icon(
                PhosphorIcons.x(),
                color: Colors.white.withValues(alpha: 0.85),
                size: 22,
              ),
            );
          }
          final m = MaskCatalog.all[i - 1];
          final isSelected = selected?.id == m.id;
          return _MaskBubble(
            isSelected: isSelected,
            label: m.label,
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(m);
            },
            child: Icon(m.previewIcon, color: Colors.white, size: 22),
          );
        },
      ),
    );
  }
}

class _MaskBubble extends StatelessWidget {
  final bool isSelected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  const _MaskBubble({
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
