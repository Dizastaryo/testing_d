import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';

/// Record / shutter button with pulse animation and progress ring.
class CameraRecordButton extends StatefulWidget {
  final bool isRecording;
  final double totalPct;
  final bool isPhotoMode;
  final VoidCallback onPress;

  const CameraRecordButton({
    super.key,
    required this.isRecording,
    required this.totalPct,
    required this.isPhotoMode,
    required this.onPress,
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
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isRecording) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(CameraRecordButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !old.isRecording) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && old.isRecording) {
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
    const double innerPhotoSize = 64;
    const double innerRecordSize = 30;

    final isRecording = widget.isRecording && !widget.isPhotoMode;
    final innerSize = isRecording ? innerRecordSize : innerPhotoSize;
    final innerRadius = isRecording ? 8.0 : innerPhotoSize / 2;

    return GestureDetector(
      onTap: widget.onPress,
      child: SizedBox(
        width: btnSize,
        height: btnSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
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
            CustomPaint(
              size: const Size(btnSize, btnSize),
              painter: _RingPainter(
                totalPct: widget.isPhotoMode ? 0.0 : widget.totalPct,
                ringRadius: 46.0,
                isRecording: isRecording,
              ),
            ),
            Container(
              width: whiteRingSize,
              height: whiteRingSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: const Cubic(0.34, 1.56, 0.64, 1.0),
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF8060), Color(0xFFFF5A3C), Color(0xFFFF3B6B)],
                ),
                borderRadius: BorderRadius.circular(innerRadius),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5A3C).withValues(alpha: 0.55),
                    blurRadius: 22,
                  ),
                ],
              ),
              child: Align(
                alignment: const Alignment(-0.3, -0.55),
                child: Container(
                  width: innerSize * 0.38,
                  height: innerSize * 0.14,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
