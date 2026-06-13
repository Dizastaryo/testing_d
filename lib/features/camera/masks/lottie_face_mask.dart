import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'face_tracking_service.dart';
import 'mask_catalog.dart';

/// Renders a Lottie animation anchored to detected face landmarks.
///
/// Subscribes to [FaceTrackingService.stream] independently and repositions
/// the animation widget on every tracked frame. Falls back to a screen-centre
/// position when no face is detected.
class LottieFaceMask extends StatefulWidget {
  final String assetPath;
  final LottieAnchorType anchor;
  final double lottieCanvasWidth;
  final double lottieCanvasHeight;

  const LottieFaceMask({
    super.key,
    required this.assetPath,
    required this.anchor,
    required this.lottieCanvasWidth,
    required this.lottieCanvasHeight,
  });

  @override
  State<LottieFaceMask> createState() => _LottieFaceMaskState();
}

class _LottieFaceMaskState extends State<LottieFaceMask> {
  StreamSubscription<TrackedFace?>? _sub;
  TrackedFace? _lastFace;

  @override
  void initState() {
    super.initState();
    _sub = FaceTrackingService.instance.stream.listen(_onFace);
  }

  void _onFace(TrackedFace? face) {
    if (mounted) setState(() => _lastFace = face);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Scale factor per anchor type ──────────────────────────────────────────

  double _scale(FaceFrame frame) {
    switch (widget.anchor) {
      case LottieAnchorType.fullFace:
        return frame.faceWidth / widget.lottieCanvasWidth;
      case LottieAnchorType.topOfHead:
        return (frame.faceWidth * 1.2) / widget.lottieCanvasWidth;
      case LottieAnchorType.foreheadCenter:
        return (frame.faceWidth * 1.3) / widget.lottieCanvasWidth;
    }
  }

  // ── Top-left offset per anchor type ──────────────────────────────────────

  ({double left, double top}) _offset(
      FaceFrame frame, double scaledW, double scaledH) {
    switch (widget.anchor) {
      case LottieAnchorType.fullFace:
        // Canvas maps to full face oval; slight upward shift so tears start
        // above the eyes.
        return (
          left: frame.center.dx - scaledW / 2,
          top: frame.topOfHead.dy - scaledH * 0.1,
        );
      case LottieAnchorType.topOfHead:
        // Bottom edge of Lottie canvas = topOfHead landmark.
        return (
          left: frame.center.dx - scaledW / 2,
          top: frame.topOfHead.dy - scaledH,
        );
      case LottieAnchorType.foreheadCenter:
        // Bottom-centre of Lottie canvas = forehead landmark; ears rise above.
        return (
          left: frame.forehead.dx - scaledW / 2,
          top: frame.forehead.dy - scaledH,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

        final face = _lastFace;
        final frame = (face != null && face.points.length >= 468)
            ? FaceFrame.fromTracked(face, canvasSize)
            : FaceFrame.fallback(canvasSize);

        final scale = _scale(frame);
        final scaledW = widget.lottieCanvasWidth * scale;
        final scaledH = widget.lottieCanvasHeight * scale;
        final pos = _offset(frame, scaledW, scaledH);

        return SizedBox.expand(
          child: Stack(
            children: [
              Positioned(
                left: pos.left,
                top: pos.top,
                width: scaledW,
                height: scaledH,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateZ(frame.rollRad),
                  child: IgnorePointer(
                    child: Lottie.asset(
                      widget.assetPath,
                      width: scaledW,
                      height: scaledH,
                      fit: BoxFit.fill,
                      repeat: true,
                      animate: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
