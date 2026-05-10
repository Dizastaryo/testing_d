import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// **NOOP STUB** временно. Раньше тут жил google_mlkit_face_detection для
/// real-time anchoring масок, но `google_mlkit_commons` требует iOS 15.5+ —
/// поднять Podfile с 13.0 = риск сломать другие pod'ы при сборке в
/// GitHub Actions без Apple-аккаунта.
///
/// Сейчас сервис ничего не делает: `start` возвращает сразу, stream пуст,
/// маски в `mask_catalog.dart` рендерятся через static-heuristic
/// `_FaceFrame.fromSize` (центр-верх preview).
///
/// Когда у юзера будет Apple Developer аккаунт + стабильная iOS 15.5+ pipeline:
///   1. Раскомментировать `google_mlkit_face_detection` в pubspec.yaml
///   2. Восстановить ML Kit detection-flow из git history (commit 243ad7d)
///   3. Поднять Podfile platform до '15.5'
class TrackedFace {
  final Rect boundingBoxRelative;
  final double rollRadians;
  final double yawRadians;

  const TrackedFace({
    required this.boundingBoxRelative,
    this.rollRadians = 0,
    this.yawRadians = 0,
  });
}

class FaceTrackingService {
  FaceTrackingService._();
  static final FaceTrackingService instance = FaceTrackingService._();

  final StreamController<TrackedFace?> _ctrl =
      StreamController<TrackedFace?>.broadcast();
  Stream<TrackedFace?> get stream => _ctrl.stream;
  bool get isRunning => false;

  /// Noop. Когда вернём ML Kit — здесь будет startImageStream + detector.
  Future<void> start(CameraController controller) async {}

  /// Noop.
  Future<void> stop() async {}
}
