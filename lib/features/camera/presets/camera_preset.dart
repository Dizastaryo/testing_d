import 'package:flutter/material.dart';
import '../filters/filter_state.dart';
import '../filters/frame_effect.dart';
import '../filters/overlay_effect.dart';

/// Единый пресет камеры — объединяет цветовой фильтр, рамку, оверлей
/// и параметры зерна/halation в одну неизменяемую структуру.
@immutable
class CameraPreset {
  final String id;
  final String name;
  final String emoji;

  /// Основной цвет плашки (для градиентного превью).
  final Color swatchColor;

  /// Второй цвет плашки (конец градиента).
  final Color swatchColor2;

  /// Параметры цветового фильтра.
  final FilterState filter;

  /// Рамочный эффект (null = без рамки).
  final FrameEffect? frame;

  /// Оверлей-эффект (null = без оверлея).
  final OverlayEffect? overlay;

  /// Запекать зерно в финальное фото.
  final bool hasGrain;

  /// Запекать halation в финальное фото.
  final bool hasHalation;

  /// Интенсивность зерна при bake (0..1).
  final double grainAmount;

  /// Интенсивность halation при bake (0..1).
  final double halationAmount;

  const CameraPreset({
    required this.id,
    required this.name,
    required this.emoji,
    required this.swatchColor,
    required this.swatchColor2,
    required this.filter,
    this.frame,
    this.overlay,
    this.hasGrain = false,
    this.hasHalation = false,
    this.grainAmount = 0.0,
    this.halationAmount = 0.0,
  });

  /// Пресет «без эффектов» — исходная камера.
  static const none = CameraPreset(
    id: 'none',
    name: 'Нет',
    emoji: '',
    swatchColor: Color(0xFF1C1C1E),
    swatchColor2: Color(0xFF3A3A3C),
    filter: FilterState.identity,
  );

  bool get isNone => id == 'none';
}
