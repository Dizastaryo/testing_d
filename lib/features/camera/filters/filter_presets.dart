import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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

/// Пресеты фильтров камеры.
/// Все иконки — Phosphor. Список final (не const) — PhosphorIcons.xxx()
/// возвращает IconData через метод, что несовместимо с const-контекстом.
class FilterPresets {
  FilterPresets._();

  // ── Оригинальные 7 пресетов ────────────────────────────────────────────

  static final List<FilterPreset> all = [
    FilterPreset(
      id: 'vintage_90s',
      label: 'Винтаж 90s',
      previewIcon: PhosphorIcons.camera(),
      state: const FilterState(
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
      previewIcon: PhosphorIcons.filmStrip(),
      state: const FilterState(
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
      previewIcon: PhosphorIcons.cloud(),
      state: const FilterState(
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
      previewIcon: PhosphorIcons.lightning(),
      state: const FilterState(
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
      previewIcon: PhosphorIcons.circleHalf(),
      state: const FilterState(
        contrast: 0.20,
        saturation: -1.0,
        grain: 0.18,
        vignette: 0.12,
      ),
    ),
    FilterPreset(
      id: 'soft',
      label: 'Мягко',
      previewIcon: PhosphorIcons.drop(),
      state: const FilterState(
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
      previewIcon: PhosphorIcons.sunHorizon(),
      state: const FilterState(
        brightness: 0.05,
        contrast: 0.10,
        saturation: 0.20,
        warmth: 0.50,
        vignette: 0.20,
      ),
    ),

    // ── 8 новых плёночных пресетов ─────────────────────────────────────

    // Тёплая золотистая плёнка — аналог Kodak Gold 200.
    // Чуть поднятые тени и лёгкое зерно создают классический print-look.
    FilterPreset(
      id: 'kodak_gold',
      label: 'Kodak',
      previewIcon: PhosphorIcons.sun(),
      state: const FilterState(
        brightness: 0.03,
        contrast: 0.12,
        saturation: 0.08,
        warmth: 0.28,
        grain: 0.22,
        vignette: 0.15,
      ),
    ),

    // Насыщенный слайд-фильм — аналог Kodachrome 64.
    // Высокий контраст, тёплые тени, выраженная виньетка.
    FilterPreset(
      id: 'kodachrome',
      label: 'Slide',
      previewIcon: PhosphorIcons.palette(),
      state: const FilterState(
        contrast: 0.32,
        saturation: 0.28,
        warmth: 0.18,
        grain: 0.12,
        vignette: 0.22,
      ),
    ),

    // Яркие холодноватые тона — аналог Fujifilm Velvia 50.
    // Синие и зелёные уходят в сочность, небо становится глубже.
    FilterPreset(
      id: 'fuji_velvia',
      label: 'Velvia',
      previewIcon: PhosphorIcons.leaf(),
      state: const FilterState(
        contrast: 0.28,
        saturation: 0.42,
        warmth: -0.12,
        vignette: 0.15,
      ),
    ),

    // Кросс-процесс — проявка слайда в химии для негатива.
    // Сильный сдвиг цветов: синие тени, жёлто-зелёные светлые.
    FilterPreset(
      id: 'cross_process',
      label: 'Cross',
      previewIcon: PhosphorIcons.shuffle(),
      state: const FilterState(
        brightness: -0.05,
        contrast: 0.45,
        saturation: 0.42,
        warmth: -0.30,
        vignette: 0.18,
      ),
    ),

    // Выцветшая плёнка — поднятые тени, низкий контраст, бледные цвета.
    // Эффект старых сканированных негативов.
    FilterPreset(
      id: 'faded',
      label: 'Fade',
      previewIcon: PhosphorIcons.ghost(),
      state: const FilterState(
        brightness: 0.10,
        contrast: -0.22,
        saturation: -0.28,
        warmth: 0.06,
      ),
    ),

    // Ломографический эффект — сильная виньетка, насыщенные цвета,
    // чуть тёплый тон. Аналог Lomo LC-A.
    FilterPreset(
      id: 'lomo',
      label: 'Lomo',
      previewIcon: PhosphorIcons.aperture(),
      state: const FilterState(
        contrast: 0.32,
        saturation: 0.38,
        warmth: 0.14,
        grain: 0.18,
        vignette: 0.58,
      ),
    ),

    // Матовый flat look — компрессированные светлые и тени,
    // нейтральная цветовая температура. Популярен в кино последних лет.
    FilterPreset(
      id: 'matte',
      label: 'Matte',
      previewIcon: PhosphorIcons.squaresFour(),
      state: const FilterState(
        brightness: 0.05,
        contrast: -0.22,
        saturation: -0.14,
        warmth: 0.04,
      ),
    ),

    // Нуар — чёрно-белое с высоким контрастом, зерном и виньеткой.
    // Тёмные тени, выбеленные светлые, драматика.
    FilterPreset(
      id: 'noir',
      label: 'Нуар',
      previewIcon: PhosphorIcons.moon(),
      state: const FilterState(
        contrast: 0.38,
        saturation: -1.0,
        grain: 0.28,
        vignette: 0.40,
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
