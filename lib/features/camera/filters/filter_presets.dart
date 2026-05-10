import 'package:flutter/material.dart';

import 'filter_state.dart';

class FilterPreset {
  final String id;
  final String label;
  final IconData previewIcon;
  final FilterState state;

  const FilterPreset({
    required this.id,
    required this.label,
    required this.previewIcon,
    required this.state,
  });
}

/// Встроенные «киношные» пресеты. Подобраны вручную, mature LUT'ы — отдельная задача.
class FilterPresets {
  FilterPresets._();

  static const List<FilterPreset> all = [
    FilterPreset(
      id: 'vintage_90s',
      label: 'Винтаж 90s',
      previewIcon: Icons.camera_alt_outlined,
      state: FilterState(
        brightness: -0.05,
        contrast: 0.15,
        saturation: -0.25,
        warmth: 0.30,
        grain: 0.35,
        vignette: 0.25,
      ),
    ),
    FilterPreset(
      id: 'cinematic',
      label: 'Кино',
      previewIcon: Icons.movie_filter_outlined,
      state: FilterState(
        brightness: -0.10,
        contrast: 0.30,
        saturation: -0.15,
        warmth: -0.10,
        vignette: 0.35,
      ),
    ),
    FilterPreset(
      id: 'dreamy',
      label: 'Мечта',
      previewIcon: Icons.cloud_outlined,
      state: FilterState(
        brightness: 0.12,
        contrast: -0.10,
        saturation: 0.05,
        warmth: 0.20,
        vignette: 0.15,
      ),
    ),
    FilterPreset(
      id: 'cyberpunk',
      label: 'Кибер',
      previewIcon: Icons.electric_bolt_outlined,
      state: FilterState(
        brightness: -0.05,
        contrast: 0.40,
        saturation: 0.50,
        warmth: -0.35,
        vignette: 0.20,
      ),
    ),
    FilterPreset(
      id: 'bw',
      label: 'Ч/Б',
      previewIcon: Icons.contrast,
      state: FilterState(
        contrast: 0.20,
        saturation: -1.0,
      ),
    ),
    FilterPreset(
      id: 'soft',
      label: 'Мягко',
      previewIcon: Icons.blur_on_outlined,
      state: FilterState(
        brightness: 0.08,
        contrast: -0.15,
        saturation: -0.10,
        warmth: 0.10,
        grain: 0.15,
      ),
    ),
    FilterPreset(
      id: 'sunset',
      label: 'Закат',
      previewIcon: Icons.wb_twilight,
      state: FilterState(
        brightness: 0.05,
        contrast: 0.10,
        saturation: 0.20,
        warmth: 0.50,
        vignette: 0.20,
      ),
    ),
  ];

  static FilterPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
