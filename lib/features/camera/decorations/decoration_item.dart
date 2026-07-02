import 'package:flutter/material.dart';

import '../filters/filter_presets.dart';
import '../masks/mask_catalog.dart';

enum DecorationCategory { filter, mask }

/// Unified decoration model for camera (color filter or 3D AR mask).
class DecorationItem {
  final String id;
  final String label;
  final DecorationCategory category;
  final Color previewColor;
  final IconData previewIcon;
  final FilterPreset? filterPreset;
  final MaskDescriptor? mask;

  const DecorationItem({
    required this.id,
    required this.label,
    required this.category,
    required this.previewColor,
    required this.previewIcon,
    this.filterPreset,
    this.mask,
  });
}

/// Catalog of all decorations: filters first, then 3D masks.
class DecorationCatalog {
  DecorationCatalog._();

  static final List<DecorationItem> all = _build();

  static List<DecorationItem> _build() {
    final items = <DecorationItem>[];

    for (final p in FilterPresets.all) {
      items.add(DecorationItem(
        id: 'f_${p.id}',
        label: p.label,
        category: DecorationCategory.filter,
        previewColor: _filterColor(p),
        previewIcon: p.previewIcon,
        filterPreset: p,
      ));
    }

    for (final m in MaskCatalog.all) {
      items.add(DecorationItem(
        id: 'm_${m.id}',
        label: m.label,
        category: DecorationCategory.mask,
        previewColor: const Color(0xFF5ABFFA),
        previewIcon: m.previewIcon,
        mask: m,
      ));
    }

    return items;
  }

  static Color _filterColor(FilterPreset p) {
    final s = p.state;
    if (s.warmth > 0.2) return const Color(0xFFD9854E);
    if (s.warmth < -0.15) return const Color(0xFF4A82D0);
    if (s.saturation < -0.3) return const Color(0xFF888888);
    if (s.grain > 0.3) return const Color(0xFF9A7055);
    if (s.liftBlacks > 0.15) return const Color(0xFF8A6EA8);
    if (s.fadeHighlights > 0.15) return const Color(0xFF7AAA88);
    return const Color(0xFF6A98C0);
  }
}
