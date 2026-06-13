import 'package:flutter/material.dart';

/// Set to true while tuning masks, false when done. Works in release builds.
const bool kMaskTuning = false;

/// Per-mask adjustment values for debug tuning.
class MaskAdjust {
  double dx;
  double dy;
  double scale;

  MaskAdjust({this.dx = 0.0, this.dy = 0.0, this.scale = 1.0});

  bool get isIdentity => dx == 0.0 && dy == 0.0 && scale == 1.0;
}

/// Stores per-mask debug adjustments. Keyed by MaskDescriptor.id.
class MaskDebugConfig {
  MaskDebugConfig._();

  static final Map<String, MaskAdjust> _adjustments = {};

  /// Notifier that fires when any slider changes (triggers repaint).
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static MaskAdjust get(String maskId) {
    return _adjustments.putIfAbsent(maskId, MaskAdjust.new);
  }

  static void notify() {
    notifier.value = notifier.value + 1;
  }
}
