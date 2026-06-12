import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';

enum CaptureButtonState { photoReady, videoReady, recording }

/// Record / shutter button.
///
/// Tap → [onTap].
/// Visual state driven by [state]:
///   - photoReady  : white filled circle
///   - videoReady  : orange gradient circle
///   - recording   : pulsing outer glow + orange square stop
class CameraRecordButton extends StatefulWidget {
  final CaptureButtonState state;
  final double totalPct;
  final VoidCallback onTap;

  const CameraRecordButton({
    super.key,
    required this.state,
    required this.totalPct,
    required this.onTap,
  });

  @override
  State<CameraRecordButton> createState() => _CameraRecordButtonState();
}

class _CameraRecordButtonState extends State<CameraRecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.state == CaptureButtonState.recording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(CameraRecordButton old) {
    super.didUpdateWidget(old);
    final wasRecording = old.state == CaptureButtonState.recording;
    final isRecording = widget.state == CaptureButtonState.recording;
    if (isRecording && !wasRecording) {
      _pulseController.repeat(reverse: true);
    } else if (!isRecording && wasRecording) {
      _pulseController.stop();
      _pulseController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double btnSize = 96;
    const double whiteRingSize = 78;
    const double innerFullSize = 64;
    const double innerStopSize = 30;

    final isRecording = widget.state == CaptureButtonState.recording;
    final isPhoto = widget.state == CaptureButtonState.photoReady;
    final innerSize = isRecording ? innerStopSize : innerFullSize;
    final innerRadius = isRecording ? 8.0 : innerFullSize / 2;

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: btnSize,
        height: btnSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulse glow (recording only)
            if (isRecording)
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    width: btnSize,
                    height: btnSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFF8060).withValues(alpha: 0.30),
                          const Color(0xFFFF5A3C).withValues(alpha: 0.12),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

            // Progress ring (video modes only)
            if (!isPhoto)
              CustomPaint(
                size: const Size(btnSize, btnSize),
                painter: _RingPainter(
                  totalPct: widget.totalPct,
                  ringRadius: 46.0,
                  isRecording: isRecording,
                ),
              ),

            // White outer ring
            Container(
              width: whiteRingSize,
              height: whiteRingSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),

            // Inner circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                color: isPhoto ? Colors.white : null,
                gradient: isPhoto
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFF8060),
                          Color(0xFFFF5A3C),
                          Color(0xFFFF3B6B),
                        ],
                      ),
                borderRadius: BorderRadius.circular(innerRadius),
                boxShadow: [
                  if (isPhoto)
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.30),
                      blurRadius: 12,
                    )
                  else
                    BoxShadow(
                      color: const Color(0xFFFF5A3C).withValues(alpha: 0.55),
                      blurRadius: 22,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double totalPct;
  final double ringRadius;
  final bool isRecording;

  const _RingPainter({
    required this.totalPct,
    required this.ringRadius,
    required this.isRecording,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, ringRadius, trackPaint);

    const int tickCount = 60;
    for (int i = 0; i < tickCount; i++) {
      final angle = (i / tickCount) * 2 * math.pi - math.pi / 2;
      final isMajor = i % 5 == 0;
      final tickLen = isMajor ? 6.0 : 3.5;
      final tickWidth = isMajor ? 1.8 : 1.0;
      final tickOpacity = isMajor ? 0.55 : 0.28;
      final outerR = ringRadius + 6;
      final innerR = outerR - tickLen;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final tickPaint = Paint()
        ..color = Colors.white.withValues(alpha: tickOpacity)
        ..strokeWidth = tickWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(center.dx + innerR * cosA, center.dy + innerR * sinA),
        Offset(center.dx + outerR * cosA, center.dy + outerR * sinA),
        tickPaint,
      );
    }

    if (totalPct <= 0) return;
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * totalPct;
    final rect = Rect.fromCircle(center: center, radius: ringRadius);
    const gradientColors = [Color(0xFFFFB547), Color(0xFFFF5A3C), Color(0xFFFF3B6B)];
    final sweepGradient = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweepAngle,
      colors: gradientColors,
      tileMode: TileMode.clamp,
    );
    final progressPaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
    canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.totalPct != totalPct || old.isRecording != isRecording;
}

/// Animated countdown number (3, 2, 1) for timer mode.
class CameraCountdownNumber extends StatefulWidget {
  final int value;
  const CameraCountdownNumber({super.key, required this.value});

  @override
  State<CameraCountdownNumber> createState() => _CameraCountdownNumberState();
}

class _CameraCountdownNumberState extends State<CameraCountdownNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _ac.forward();
  }

  @override
  void didUpdateWidget(CameraCountdownNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _ac.forward(from: 0);
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
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Text(
            '${widget.value}',
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 140,
              color: Colors.white,
              fontWeight: FontWeight.w400,
              shadows: [
                Shadow(color: SeeUColors.mediumScrim, blurRadius: 32, offset: Offset(0, 8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
