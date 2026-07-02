import 'package:flutter/material.dart';

/// Состояние фильтра — 9 параметров. Каждое поле ∈ [-1..+1] (для basic-color
/// эффектов) или [0..1] (для overlay'ев vignette/grain/lift/fade/halation).
/// Применяются через composed `ColorMatrix` + Stack-overlay'и.
@immutable
class FilterState {
  final double brightness;     // -1..+1, 0 = identity
  final double contrast;       // -1..+1
  final double saturation;     // -1..+1
  final double warmth;         // -1..+1 (минус = холоднее)
  final double vignette;       // 0..1, сила тёмной виньетки
  final double grain;          // 0..1, плотность шума
  final double liftBlacks;     // 0..1 — поднимает тени (vintage faded look)
  final double fadeHighlights; // 0..1 — компрессирует светлые (matte look)
  final double halation;       // 0..1 — тёплый ореол вокруг ярких зон плёнки

  const FilterState({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
    this.vignette = 0,
    this.grain = 0,
    this.liftBlacks = 0,
    this.fadeHighlights = 0,
    this.halation = 0,
  });

  static const identity = FilterState();

  bool get isIdentity =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      warmth == 0 &&
      vignette == 0 &&
      grain == 0 &&
      liftBlacks == 0 &&
      fadeHighlights == 0 &&
      halation == 0;

  FilterState copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    double? vignette,
    double? grain,
    double? liftBlacks,
    double? fadeHighlights,
    double? halation,
  }) =>
      FilterState(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        warmth: warmth ?? this.warmth,
        vignette: vignette ?? this.vignette,
        grain: grain ?? this.grain,
        liftBlacks: liftBlacks ?? this.liftBlacks,
        fadeHighlights: fadeHighlights ?? this.fadeHighlights,
        halation: halation ?? this.halation,
      );

  /// Композирует ColorMatrix из brightness/contrast/saturation/warmth/
  /// liftBlacks/fadeHighlights. Применяется как `ColorFilter.matrix(toMatrix())`.
  ///
  /// Порядок: contrast × saturation × warmth + brightness-offset,
  /// затем post-transform: liftBlacks поднимает floor теней, fadeHighlights
  /// компрессирует ceiling светлых (slope × input + floor).
  List<double> toMatrix() {
    final b = brightness; // -1..+1
    final c = 1.0 + contrast; // 0..2
    final s = 1.0 + saturation; // 0..2
    final w = warmth; // -1..+1

    // ITU-601 luma weights для desaturation:
    const lr = 0.299;
    const lg = 0.587;
    const lumaB = 0.114;
    final sR = lr * (1 - s);
    final sG = lg * (1 - s);
    final sB = lumaB * (1 - s);

    // contrast: scale around 0.5 — pixel = c*(p - 0.5) + 0.5 = c*p + 0.5*(1-c)
    final co = 0.5 * (1.0 - c);

    // warmth: R += w*0.2, B -= w*0.2 (мягкое сдвигание баланса)
    final wR = w * 0.20;
    final wB = -w * 0.20;

    final bOff = b * 255.0;

    // Post-transform for liftBlacks / fadeHighlights:
    //   fadeHighlights: output = fadeFactor * baseOutput + fadeFloor
    //     fadeFactor=0.80..1.0 compresses highlight headroom,
    //     fadeFloor lifts the absolute minimum so blacks aren't crushed.
    //   liftBlacks: adds liftOff to the constant term, raising shadow floor.
    final ff = 1.0 - fadeHighlights * 0.20; // 0.80..1.0 slope factor
    final totalOff = liftBlacks * 42.0 + fadeHighlights * 36.0;

    // 5×4 matrix (row-major), coefficients pre-multiplied by ff:
    // R' = ff*(c*(sR+s)*R + c*sG*G + c*sB*B) + (ff*(co+wR)*255 + ff*bOff + totalOff)
    final kR = (co * 255 + wR * 255 + bOff) * ff + totalOff;
    final kG = (co * 255 + bOff) * ff + totalOff;
    final kB = (co * 255 + wB * 255 + bOff) * ff + totalOff;

    return [
      c * (sR + s) * ff, c * sG * ff,       c * sB * ff,       0, kR,
      c * sR * ff,       c * (sG + s) * ff, c * sB * ff,       0, kG,
      c * sR * ff,       c * sG * ff,       c * (sB + s) * ff, 0, kB,
      0, 0, 0, 1, 0,
    ];
  }
}
