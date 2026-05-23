import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

// ─── 468-mesh landmark indices ───────────────────────────────────────────

class MeshIdx {
  MeshIdx._();
  static const int leftEyeOuter = 33;
  static const int rightEyeOuter = 263;
  static const int leftEyeInner = 133;
  static const int rightEyeInner = 362;
  static const int noseBottom = 2;
  static const int noseTip = 1;
  static const int forehead = 10;
  static const int leftMouth = 61;
  static const int rightMouth = 291;
  static const int upperLip = 13;
  static const int lowerLip = 14;
  static const int leftFace = 234;
  static const int rightFace = 454;
  static const int chin = 152;
}

// ─── One-Euro Filter ─────────────────────────────────────────────────────

class _OneEuroFilter {
  double _xPrev = 0;
  double _dxPrev = 0;
  double _tPrev = -1;
  final double minCutoff;
  final double beta;
  final double dCutoff;

  _OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.007, this.dCutoff = 1.0});

  double _alpha(double te, double cutoff) {
    final r = 2 * math.pi * cutoff * te;
    return r / (r + 1);
  }

  double filter(double x, double t) {
    if (_tPrev < 0) {
      _tPrev = t;
      _xPrev = x;
      _dxPrev = 0;
      return x;
    }
    final te = t - _tPrev;
    if (te <= 0) return _xPrev;
    final aD = _alpha(te, dCutoff);
    final dx = (x - _xPrev) / te;
    final dxHat = aD * dx + (1 - aD) * _dxPrev;
    final cutoff = minCutoff + beta * dxHat.abs();
    final a = _alpha(te, cutoff);
    final xHat = a * x + (1 - a) * _xPrev;
    _xPrev = xHat;
    _dxPrev = dxHat;
    _tPrev = t;
    return xHat;
  }

  void reset() => _tPrev = -1;
}

class TransformSmoother {
  final _fx = _OneEuroFilter(minCutoff: 1.5, beta: 0.01);
  final _fy = _OneEuroFilter(minCutoff: 1.5, beta: 0.01);
  final _fr = _OneEuroFilter(minCutoff: 1.0, beta: 0.005);
  final _fs = _OneEuroFilter(minCutoff: 1.0, beta: 0.005);
  final _fsx = _OneEuroFilter(minCutoff: 1.0, beta: 0.003);

  ({Offset pos, double rot, double scale, double scaleX}) smooth(
      double x, double y, double rot, double scale, double scaleX, double t) {
    return (
      pos: Offset(_fx.filter(x, t), _fy.filter(y, t)),
      rot: _fr.filter(rot, t),
      scale: _fs.filter(scale, t),
      scaleX: _fsx.filter(scaleX, t),
    );
  }

  void reset() {
    _fx.reset();
    _fy.reset();
    _fr.reset();
    _fs.reset();
    _fsx.reset();
  }
}

// ─── Tracked face result ─────────────────────────────────────────────────

class TrackedFace {
  /// 468 landmarks as pixel-space Offsets (mapped to preview size).
  final List<Offset> points;
  final int imageWidth;
  final int imageHeight;

  const TrackedFace({
    required this.points,
    required this.imageWidth,
    required this.imageHeight,
  });

  Offset pt(int idx) => points[idx];

  double get eyeDistance => (pt(MeshIdx.rightEyeOuter) - pt(MeshIdx.leftEyeOuter)).distance;

  Offset get eyeCenter => Offset(
        (pt(MeshIdx.leftEyeOuter).dx + pt(MeshIdx.rightEyeOuter).dx) / 2,
        (pt(MeshIdx.leftEyeOuter).dy + pt(MeshIdx.rightEyeOuter).dy) / 2,
      );

  double get rollRad {
    final le = pt(MeshIdx.leftEyeOuter);
    final re = pt(MeshIdx.rightEyeOuter);
    return math.atan2(re.dy - le.dy, re.dx - le.dx);
  }

  double get yawRad {
    final nose = pt(MeshIdx.noseTip);
    final left = pt(MeshIdx.leftFace);
    final right = pt(MeshIdx.rightFace);
    final mid = (left.dx + right.dx) / 2;
    final halfW = (right.dx - left.dx).abs() / 2;
    if (halfW < 1) return 0;
    return math.asin(((nose.dx - mid) / halfW).clamp(-1.0, 1.0));
  }
}

// ─── Face Tracking Service (mediapipe_face_mesh) ─────────────────────────

class FaceTrackingService {
  FaceTrackingService._();
  static final FaceTrackingService instance = FaceTrackingService._();

  FaceDetectorProcessor? _detector;
  FaceMeshProcessor? _mesh;
  FaceMeshInferencePipeline? _pipeline;
  CameraController? _camera;
  bool _busy = false;
  bool _running = false;
  int _frameSkip = 0;

  /// Last rotation degrees passed to MediaPipe (debug).
  int debugRotDeg = 0;

  final _smoother = TransformSmoother();

  final StreamController<TrackedFace?> _ctrl =
      StreamController<TrackedFace?>.broadcast();
  Stream<TrackedFace?> get stream => _ctrl.stream;
  bool get isRunning => _running;

  /// Start face mesh tracking. Call after CameraController.initialize().
  Future<void> start(CameraController controller) async {
    if (_running) return;
    _camera = controller;

    _detector = await FaceDetectorProcessor.create(
      model: FaceDetectionModel.shortRange,
      delegate: FaceMeshDelegate.xnnpack,
      maxResults: 1,
    );
    _mesh = await FaceMeshProcessor.create(
      delegate: FaceMeshDelegate.xnnpack,
      enableSmoothing: true,
      enableRoiTracking: true,
      enableIris: false,
    );
    _pipeline = FaceMeshInferencePipeline(
      detector: _detector!,
      mesh: _mesh!,
    );

    _smoother.reset();
    _frameSkip = 0;

    try {
      await controller.startImageStream(_handleFrame);
      _running = true;
    } catch (_) {
      _running = false;
      _cleanup();
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _camera?.stopImageStream();
    } catch (_) {}
    _cleanup();
    _ctrl.add(null);
  }

  void _cleanup() {
    _mesh?.close();
    _detector?.close();
    _mesh = null;
    _detector = null;
    _pipeline = null;
    _camera = null;
    _smoother.reset();
  }

  Future<void> _handleFrame(CameraImage image) async {
    if (_busy || _pipeline == null || _camera == null) return;

    // Throttle: every 2nd frame → ~15 FPS inference from 30 FPS camera
    _frameSkip++;
    if (_frameSkip % 2 != 0) return;

    _busy = true;
    try {
      final rotDeg = _rotationDegrees(_camera!);
      debugRotDeg = rotDeg;
      final isFront =
          _camera!.description.lensDirection == CameraLensDirection.front;

      FaceMeshInferenceResult result;

      if (Platform.isAndroid) {
        final nv21 = _toNv21(image);
        if (nv21 == null) {
          return;
        }
        result = _pipeline!.processNv21(
          nv21,
          rotationDegrees: rotDeg,
          mirrorHorizontal: isFront,
        );
      } else {
        // iOS: BGRA
        final rgba = _toBgra(image);
        if (rgba == null) {
          return;
        }
        result = _pipeline!.process(
          rgba,
          rotationDegrees: rotDeg,
          mirrorHorizontal: isFront,
        );
      }

      final mesh = result.meshResult;
      if (mesh == null || mesh.landmarks.isEmpty) {
        _ctrl.add(null);
        return;
      }

      // Landmarks from MediaPipe are normalized (0..1) in the SENSOR's
      // native coordinate system (landscape). rotationDegrees was passed
      // to the detector/mesh for correct face DETECTION, but the output
      // landmarks remain in the original orientation.
      //
      // landmarksAsOffsets accepts rotationDegrees + mirrorHorizontal to
      // remap the normalized coords into the portrait preview space.
      // After rotation by 90°/270° the effective image dimensions swap.
      final bool swapped = (rotDeg == 90 || rotDeg == 270);
      final double outW = swapped ? mesh.imageHeight.toDouble() : mesh.imageWidth.toDouble();
      final double outH = swapped ? mesh.imageWidth.toDouble() : mesh.imageHeight.toDouble();
      final portraitSize = Size(outW, outH);

      final offsets = mesh.landmarksAsOffsets(
        targetSize: portraitSize,
        rotationDegrees: rotDeg,
        mirrorHorizontal: isFront,
      );

      final outWidth = outW.toInt();
      final outHeight = outH.toInt();

      // ── DEBUG: log mesh dimensions + raw input + landmarks ──
      if (_frameSkip % 60 == 0) {
        final tracked = TrackedFace(
          points: offsets,
          imageWidth: outWidth,
          imageHeight: outHeight,
        );
        debugPrint(
          '[FaceTrack] input=${image.width}x${image.height} '
          'rotDeg=$rotDeg isFront=$isFront '
          'meshRaw=${mesh.imageWidth}x${mesh.imageHeight} '
          'meshOut=${outWidth}x$outHeight '
          'rollRad=${tracked.rollRad.toStringAsFixed(3)} '
          'yawRad=${tracked.yawRad.toStringAsFixed(3)} '
          'eyeCenter=${tracked.eyeCenter}',
        );
      }

      _ctrl.add(TrackedFace(
        points: offsets,
        imageWidth: outWidth,
        imageHeight: outHeight,
      ));
    } catch (_) {
      // Drop frame on error — next one arrives in ~33ms
    } finally {
      _busy = false;
    }
  }

  int _rotationDegrees(CameraController controller) {
    final sensor = controller.description.sensorOrientation;
    if (Platform.isIOS) return sensor;
    const orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final deviceRot = orientations[controller.value.deviceOrientation] ?? 0;
    final isFront =
        controller.description.lensDirection == CameraLensDirection.front;
    if (isFront) {
      return (sensor + deviceRot) % 360;
    }
    return (sensor - deviceRot + 360) % 360;
  }

  /// Android NV21: planes[0]=Y, planes[1]=VU (interleaved).
  FaceMeshNv21Image? _toNv21(CameraImage image) {
    if (image.planes.length < 2) return null;
    return FaceMeshNv21Image(
      yPlane: image.planes[0].bytes,
      vuPlane: image.planes[1].bytes,
      width: image.width,
      height: image.height,
      yBytesPerRow: image.planes[0].bytesPerRow,
      vuBytesPerRow: image.planes[1].bytesPerRow,
    );
  }

  /// iOS BGRA: single plane.
  FaceMeshImage? _toBgra(CameraImage image) {
    if (image.planes.isEmpty) return null;
    return FaceMeshImage(
      pixels: image.planes[0].bytes,
      width: image.width,
      height: image.height,
      pixelFormat: FaceMeshPixelFormat.bgra,
      bytesPerRow: image.planes[0].bytesPerRow,
    );
  }
}
