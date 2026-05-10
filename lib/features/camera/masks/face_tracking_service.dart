import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Найденное лицо в image-space камеры. Координаты — в **canvasSize**, не
/// в pixel-size CameraImage'а: сервис нормализует bounding-box к 0..1 чтобы
/// клиент мог применить к любому preview-размеру через размножение.
class TrackedFace {
  /// Относительные координаты bounding-box'а лица: 0..1 от width/height
  /// исходного `CameraImage`. Применяется к canvas через
  /// `Rect.fromLTWH(rel.left*canvasW, rel.top*canvasH, rel.width*canvasW, ...)`.
  final Rect boundingBoxRelative;

  /// Угол наклона головы по Z (roll, в радианах). Нужен для масок-аксессуаров
  /// которые должны крутиться вместе с головой.
  final double rollRadians;

  /// Угол поворота головы по Y (yaw — влево/вправо). Маска может «уходить
  /// за щёку» если abs > π/4.
  final double yawRadians;

  const TrackedFace({
    required this.boundingBoxRelative,
    this.rollRadians = 0,
    this.yawRadians = 0,
  });
}

/// Singleton face-tracking сервис. Платформозависим: на iOS/Android
/// подключается к `CameraController.startImageStream`, на web — noop.
///
/// Использование:
///   final svc = FaceTrackingService.instance;
///   await svc.start(controller);
///   svc.stream.listen((face) { setState(...); });
///   ...
///   await svc.stop();
class FaceTrackingService {
  FaceTrackingService._();
  static final FaceTrackingService instance = FaceTrackingService._();

  FaceDetector? _detector;
  CameraController? _camera;
  bool _busy = false; // защита от concurrent processImage
  bool _running = false;

  final StreamController<TrackedFace?> _ctrl =
      StreamController<TrackedFace?>.broadcast();
  Stream<TrackedFace?> get stream => _ctrl.stream;

  /// `true` если сервис активно слушает image-stream.
  bool get isRunning => _running;

  /// Запускает image-stream и face-detection. На web возвращает сразу.
  /// `controller` должен уже быть `initialize()`'нут.
  Future<void> start(CameraController controller) async {
    if (kIsWeb) {
      // На web stream'инг кадров через CameraController нестабилен.
      // Маски на web живут в static-heuristic режиме (см. _FaceFrame.fromSize).
      return;
    }
    if (_running) return;
    _camera = controller;
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: false, // bounding-box достаточно для MVP
        enableClassification: false,
        enableTracking: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    try {
      await controller.startImageStream(_handleFrame);
      _running = true;
    } catch (_) {
      // Camera image-stream может не поддерживаться на текущем backend'е
      // (например при использовании platform views).
      _running = false;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _camera?.stopImageStream();
    } catch (_) {}
    await _detector?.close();
    _detector = null;
    _camera = null;
    _ctrl.add(null);
  }

  Future<void> _handleFrame(CameraImage image) async {
    if (_busy || _detector == null || _camera == null) return;
    _busy = true;
    try {
      final input = _toInputImage(image, _camera!);
      if (input == null) return;
      final faces = await _detector!.processImage(input);
      if (faces.isEmpty) {
        _ctrl.add(null);
        return;
      }
      // Берём самое крупное лицо (ближе всего к камере).
      faces.sort((a, b) =>
          (b.boundingBox.width * b.boundingBox.height)
              .compareTo(a.boundingBox.width * a.boundingBox.height));
      final f = faces.first;
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      final rel = Rect.fromLTWH(
        f.boundingBox.left / w,
        f.boundingBox.top / h,
        f.boundingBox.width / w,
        f.boundingBox.height / h,
      );
      _ctrl.add(TrackedFace(
        boundingBoxRelative: rel,
        rollRadians: (f.headEulerAngleZ ?? 0) * 3.14159265 / 180.0,
        yawRadians: (f.headEulerAngleY ?? 0) * 3.14159265 / 180.0,
      ));
    } catch (_) {
      // Кадр пропускаем — не критично, следующий придёт через ~30ms.
    } finally {
      _busy = false;
    }
  }

  /// CameraImage → InputImage. Платформозависимая конверсия — выживает на
  /// канонических форматах: BGRA8888 (iOS) и NV21 (Android, если задан в
  /// `CameraController(imageFormatGroup: ImageFormatGroup.nv21)`).
  ///
  /// Если формат не подходит — возвращает null, кадр игнорируется. Это OK:
  /// detector обновляет state не из каждого кадра.
  InputImage? _toInputImage(CameraImage image, CameraController controller) {
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      const orientations = {
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };
      var rotationCompensation =
          orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation =
            (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    // ML Kit on iOS supports only bgra8888, Android only nv21.
    if ((Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
