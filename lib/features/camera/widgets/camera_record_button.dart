import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';

/// Унифицированная кнопка съёмки в духе нового дизайна SeeU.
///
/// Одна кнопка, два жеста (как в TikTok / Instagram):
///   • Нажатие (tap)            → [onTap]      — снять фото.
///   • Удержание (long-press)   → [onRecordStart] … [onRecordStop] — снять видео.
///
/// Визуально: чистое белое кольцо с белым диском в покое; во время записи диск
/// превращается в красный скруглённый квадрат, кольцо становится дорожкой
/// прогресса с коралловой дугой, вокруг идёт мягкая пульсация.
class CameraRecordButton extends StatefulWidget {
  final bool isRecording;
  final double totalPct;
  final VoidCallback onTap;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;

  const CameraRecordButton({
    super.key,
    required this.isRecording,
    required this.totalPct,
    required this.onTap,
    required this.onRecordStart,
    required this.onRecordStop,
  });

  @override
  State<CameraRecordButton> createState() => _CameraRecordButtonState();
}

class _CameraRecordButtonState extends State<CameraRecordButton>
    with TickerProviderStateMixin {
  // Press-down feedback (tactile scale).
  late final AnimationController _pressCtrl;
  // Soft pulse ring while recording.
  late final AnimationController _pulseCtrl;

  static const Color _recordRed = Color(0xFFFF3B30);

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didUpdateWidget(CameraRecordButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !old.isRecording) {
      _pulseCtrl.repeat();
    } else if (!widget.isRecording && old.isRecording) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double btnSize = 88;
    const double ringDiameter = 78;

    final isRecording = widget.isRecording;

    // Inner morphing shape: white disc (photo) → red rounded square (recording).
    final double innerSize = isRecording ? 32 : 62;
    final double innerRadius = isRecording ? 10 : innerSize / 2;
    final Color innerColor = isRecording ? _recordRed : Colors.white;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      onLongPressStart: (_) {
        _pressCtrl.forward();
        widget.onRecordStart();
      },
      onLongPressEnd: (_) {
        _pressCtrl.reverse();
        widget.onRecordStop();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_pressCtrl, _pulseCtrl]),
        builder: (_, __) {
          final press = Curves.easeOut.transform(_pressCtrl.value);
          final scale = 1.0 - 0.06 * press;
          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: btnSize,
              height: btnSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Ambient glow ring at rest (fades out when recording starts).
                  if (!isRecording)
                    Container(
                      width: ringDiameter + 10,
                      height: ringDiameter + 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                    ),

                  // Expanding pulse ring while recording.
                  if (isRecording)
                    Container(
                      width: ringDiameter +
                          28 * Curves.easeOut.transform(_pulseCtrl.value),
                      height: ringDiameter +
                          28 * Curves.easeOut.transform(_pulseCtrl.value),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _recordRed.withValues(
                            alpha: 0.28 * (1 - _pulseCtrl.value)),
                      ),
                    ),

                  // Ring + progress arc.
                  CustomPaint(
                    size: const Size(btnSize, btnSize),
                    painter: _RingPainter(
                      diameter: ringDiameter,
                      stroke: isRecording ? 4.0 : 4.5,
                      progress: widget.totalPct,
                      showProgress: isRecording,
                      ringColor: Colors.white,
                      progressColor: SeeUColors.accent,
                    ),
                  ),

                  // Inner morphing shape: disc → red square.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    width: innerSize,
                    height: innerSize,
                    decoration: BoxDecoration(
                      color: innerColor,
                      borderRadius: BorderRadius.circular(innerRadius),
                      boxShadow: [
                        BoxShadow(
                          color: innerColor.withValues(
                              alpha: isRecording ? 0.45 : 0.25),
                          blurRadius: isRecording ? 20 : 14,
                          spreadRadius: isRecording ? 2 : 0,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double diameter;
  final double stroke;
  final double progress; // 0..1
  final bool showProgress;
  final Color ringColor;
  final Color progressColor;

  const _RingPainter({
    required this.diameter,
    required this.stroke,
    required this.progress,
    required this.showProgress,
    required this.ringColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = diameter / 2;

    final ringPaint = Paint()
      ..color = ringColor.withValues(alpha: showProgress ? 0.4 : 1.0)
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, ringPaint);

    if (!showProgress || progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.showProgress != showProgress ||
      old.ringColor != ringColor ||
      old.progressColor != progressColor;
}

/// Animated countdown number (3, 2, 1) for timer mode.
class CameraCountdownNumber extends StatefulWidget {
  final int value;
  const CameraCountdownNumber({super.key, required this.value});

  @override
  State<CameraCountdownNumber> createState() => _CameraCountdownNumberState();
}

class _CameraCountdownNumberState extends State<CameraCountdownNumber>
    with TickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  // Smoothly-depleting ring for the current second.
  late AnimationController _ring;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _ring = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..forward();
    _ac.forward();
  }

  @override
  void didUpdateWidget(CameraCountdownNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _ac.forward(from: 0);
      _ring.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ac.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_ac, _ring]),
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Depleting accent ring for the current second.
                CustomPaint(
                  size: const Size(180, 180),
                  painter: _CountdownRingPainter(progress: 1.0 - _ring.value),
                ),
                Text(
                  '${widget.value}',
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 120,
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    shadows: [
                      Shadow(
                          color: SeeUColors.mediumScrim,
                          blurRadius: 32,
                          offset: Offset(0, 8)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  final double progress; // 1 → 0 over the second
  const _CountdownRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..color = SeeUColors.accent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // top
      6.28319 * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_CountdownRingPainter old) => old.progress != progress;
}
