import 'package:flutter/material.dart';

/// Состояние фильтра — 6 параметров. Каждое поле ∈ [-1..+1] (для basic-color
/// эффектов) или [0..1] (для overlay'ев vignette/grain). Применяются через
/// composed `ColorMatrix` + Stack-overlay'и.
@immutable
class FilterState {
  final double brightness; // -1..+1, 0 = identity
  final double contrast; // -1..+1
  final double saturation; // -1..+1
  final double warmth; // -1..+1 (минус = холоднее)
  final double vignette; // 0..1, сила тёмной виньетки
  final double grain; // 0..1, плотность шума

  const FilterState({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
    this.vignette = 0,
    this.grain = 0,
  });

  static const identity = FilterState();

  bool get isIdentity =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      warmth == 0 &&
      vignette == 0 &&
      grain == 0;

  FilterState copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    double? vignette,
    double? grain,
  }) =>
      FilterState(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        warmth: warmth ?? this.warmth,
        vignette: vignette ?? this.vignette,
        grain: grain ?? this.grain,
      );

  /// Композирует ColorMatrix из brightness/contrast/saturation/warmth.
  /// Применяется как `ColorFilter.matrix(toMatrix())` поверх preview.
  ///
  /// Порядок: contrast × saturation × warmth + brightness-offset.
  /// Для простоты — single 5×4 matrix вместо chain'а.
  List<double> toMatrix() {
    final b = brightness; // -1..+1
    final c = 1.0 + contrast; // 0..2
    final s = 1.0 + saturation; // 0..2
    final w = warmth; // -1..+1

    // ITU-601 luma weights для desaturation:
    const lr = 0.299;
    const lg = 0.587;
    const lb = 0.114;
    final sR = lr * (1 - s);
    final sG = lg * (1 - s);
    final sB = lb * (1 - s);

    // contrast: scale around 0.5 — pixel = c*(p - 0.5) + 0.5 = c*p + 0.5*(1-c)
    final co = 0.5 * (1.0 - c);

    // warmth: R += w*0.2, B -= w*0.2 (мягкое сдвигание баланса)
    final wR = w * 0.20;
    final wB = -w * 0.20;

    final bOff = b * 255.0;

    // 5×4 matrix (row-major):
    // R' = (sR+s)*R + sG*G + sB*B + 0*A + (co*255 + wR*255 + bOff)
    // G' = sR*R + (sG+s)*G + sB*B + 0*A + (co*255 + bOff)
    // B' = sR*R + sG*G + (sB+s)*B + 0*A + (co*255 + wB*255 + bOff)
    // A' = A
    return [
      c * (sR + s), c * sG, c * sB, 0, co * 255 + wR * 255 + bOff,
      c * sR, c * (sG + s), c * sB, 0, co * 255 + bOff,
      c * sR, c * sG, c * (sB + s), 0, co * 255 + wB * 255 + bOff,
      0, 0, 0, 1, 0,
    ];
  }
}
