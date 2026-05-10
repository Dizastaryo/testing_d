import 'package:flutter/material.dart';

import 'face_tracking_service.dart';
import 'mask_catalog.dart';

/// Overlay AR-маски поверх CameraPreview. Слушает `FaceTrackingService.stream`
/// (на mobile активный, на web ничего не шлёт), обновляет static
/// `maskCurrentTrackedFace` и триггерит rebuild для перерисовки painter'а
/// в новой позиции.
///
/// Если descriptor == null → ничего не рендерится. Если detection не запущен
/// или ещё нет первого face-event'а → painter использует static-heuristic
/// frame (см. `_FaceFrame.fromSize` fallback).
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
    _sub; // touch lazy field to subscribe
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.descriptor == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: widget.descriptor!.painter()),
      ),
    );
  }
}
