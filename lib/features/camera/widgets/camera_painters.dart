import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Rule-of-thirds grid overlay.
class CameraGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(2 * size.width / 3, 0), Offset(2 * size.width / 3, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, 2 * size.height / 3), Offset(size.width, 2 * size.height / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Multi-segment progress bar shown above the record button area.
class CameraSegmentBarPainter extends CustomPainter {
  final List<double> segments;
  final double currentSegDur;
  final double maxDuration;
  final bool isRecording;
  final Color accentColor;
  /// 0→1: the last completed segment flashes from accent color to white.
  final double lastSegmentFlash;

  const CameraSegmentBarPainter({
    required this.segments,
    required this.currentSegDur,
    required this.maxDuration,
    required this.isRecording,
    required this.accentColor,
    this.lastSegmentFlash = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(3),
    );
    canvas.drawRRect(rrect, trackPaint);

    double offsetX = 0;
    const gap = 2.0;

    for (int i = 0; i < segments.length; i++) {
      final w = (segments[i] / maxDuration) * size.width;
      // Last segment: lerp from accentColor → white during flash animation
      final Color segColor = (i == segments.length - 1)
          ? Color.lerp(accentColor, Colors.white, lastSegmentFlash)!
          : Colors.white;
      final segPaint = Paint()
        ..color = segColor
        ..style = PaintingStyle.fill;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(offsetX, 0, w - gap, size.height),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, segPaint);
      offsetX += w;
    }

    if (isRecording && currentSegDur > 0) {
      final w = (currentSegDur / maxDuration) * size.width;
      final redPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final redPaintSolid = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(offsetX, 0, w, size.height),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, redPaint);
      canvas.drawRRect(r, redPaintSolid);
    }
  }

  @override
  bool shouldRepaint(CameraSegmentBarPainter old) =>
      old.segments != segments ||
      old.currentSegDur != currentSegDur ||
      old.isRecording != isRecording ||
      old.lastSegmentFlash != lastSegmentFlash;
}

/// Animated 3-bar waveform shown during audio recording.
class CameraWaveform extends StatefulWidget {
  const CameraWaveform({super.key});

  @override
  State<CameraWaveform> createState() => _CameraWaveformState();
}

class _CameraWaveformState extends State<CameraWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        final heights = [
          4.0 + 6.0 * math.sin(t * math.pi),
          4.0 + 6.0 * math.sin(t * math.pi + 1.2),
          4.0 + 6.0 * math.sin(t * math.pi + 2.4),
        ];
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (i) {
            return Container(
              width: 2,
              height: heights[i],
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(1),
              ),
            );
          }),
        );
      },
    );
  }
}
