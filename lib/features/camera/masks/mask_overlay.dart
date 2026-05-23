import 'package:flutter/material.dart';

import 'face_tracking_service.dart';
import 'mask_catalog.dart';
import 'mask_debug_config.dart';

/// Overlay AR-маски поверх CameraPreview. Слушает `FaceTrackingService.stream`
/// (на mobile активный, на web ничего не шлёт), обновляет static
/// `maskCurrentTrackedFace` и триггерит rebuild для перерисовки painter'а
/// в новой позиции.
class MaskOverlay extends StatefulWidget {
  final MaskDescriptor? descriptor;
  const MaskOverlay({super.key, this.descriptor});

  @override
  State<MaskOverlay> createState() => _MaskOverlayState();
}

class _MaskOverlayState extends State<MaskOverlay> {
  late final _sub = FaceTrackingService.instance.stream.listen(_onFace);

  void _onFace(TrackedFace? f) {
    maskCurrentTrackedFace = f;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _sub;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.descriptor == null) return const SizedBox.shrink();
    final innerPainter = widget.descriptor!.painter();

    if (!kMaskTuning) {
      return Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: innerPainter),
        ),
      );
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<int>(
          valueListenable: MaskDebugConfig.notifier,
          builder: (_, __, ___) {
            return CustomPaint(
              painter: _AdjustedMaskPainter(
                inner: innerPainter,
                maskId: widget.descriptor!.id,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Wrapper painter that applies canvas-level offset + scale OUTSIDE
/// the inner painter's own save/applyRotation/restore cycle.
class _AdjustedMaskPainter extends CustomPainter {
  final CustomPainter inner;
  final String maskId;

  _AdjustedMaskPainter({required this.inner, required this.maskId});

  @override
  void paint(Canvas canvas, Size size) {
    final adj = MaskDebugConfig.get(maskId);
    if (adj.isIdentity) {
      inner.paint(canvas, size);
      return;
    }

    // Get face center for scale pivot + eyeDistance for offset units.
    final ff = FaceFrame.fromSize(size);
    final eyeDist = ff.eyeDistance;
    final pivot = ff.center;

    canvas.save();
    // Translate by offset (in eyeDistance units)
    canvas.translate(adj.dx * eyeDist, adj.dy * eyeDist);
    // Scale around face center
    canvas.translate(pivot.dx, pivot.dy);
    canvas.scale(adj.scale);
    canvas.translate(-pivot.dx, -pivot.dy);
    // Inner painter does its own save/applyRotation/restore inside
    inner.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AdjustedMaskPainter old) => true;
}
