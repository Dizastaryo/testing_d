import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'calibration_painter.dart';
import 'face_tracking_service.dart';

enum LottieAnchorType { fullFace, topOfHead, foreheadCenter }

class MaskDescriptor {
  final String id;
  final String label;
  final IconData previewIcon;
  final CustomPainter Function()? painter;
  final String? lottiePath;
  final LottieAnchorType? lottieAnchor;

  const MaskDescriptor({
    required this.id,
    required this.label,
    required this.previewIcon,
    this.painter,
    this.lottiePath,
    this.lottieAnchor,
  });
}

/// Current tracked face — updated by MaskOverlay, read by painters.
TrackedFace? maskCurrentTrackedFace;

// ─── Face frame (computed from 468 mesh landmarks) ───────────────────────

class FaceFrame {
  final Offset leftEye;
  final Offset rightEye;
  final Offset noseBase;
  final Offset forehead;
  final Offset mouthCenter;
  final Offset center;
  final double eyeDistance;
  final double rollRad;
  final double yawRad;
  final double faceWidth;
  final double faceHeight;

  /// Estimated top of head — extrapolated above forehead by ~45% of faceHeight.
  /// Adapts to each person's face proportions (longer face → higher top).
  late final Offset topOfHead = Offset(
    forehead.dx,
    forehead.dy - faceHeight * 0.45,
  );

  FaceFrame._({
    required this.leftEye,
    required this.rightEye,
    required this.noseBase,
    required this.forehead,
    required this.mouthCenter,
    required this.center,
    required this.eyeDistance,
    required this.rollRad,
    required this.yawRad,
    required this.faceWidth,
    required this.faceHeight,
  });

  /// Build from tracked face. [canvasSize] is the preview widget size.
  /// Points in TrackedFace are in image-space; we map to canvas using the
  /// same geometry as BoxFit.cover: single uniform scale + centering offset.
  static int _logCounter = 0;
  factory FaceFrame.fromTracked(TrackedFace face, Size canvasSize) {
    final imageW = face.imageWidth.toDouble();
    final imageH = face.imageHeight.toDouble();
    final scale = math.max(canvasSize.width / imageW, canvasSize.height / imageH);
    final dx = (canvasSize.width - imageW * scale) / 2;
    final dy = (canvasSize.height - imageH * scale) / 2;
    if (++_logCounter % 120 == 1) {
      debugPrint(
        '[FaceFrame] canvas=${canvasSize.width.toInt()}x${canvasSize.height.toInt()} '
        'image=${face.imageWidth}x${face.imageHeight} '
        'scale=${scale.toStringAsFixed(3)} dx=${dx.toStringAsFixed(1)} dy=${dy.toStringAsFixed(1)}',
      );
    }
    Offset pt(int idx) {
      final p = face.pt(idx);
      return Offset(p.dx * scale + dx, p.dy * scale + dy);
    }

    final le = pt(MeshIdx.leftEyeOuter);
    final re = pt(MeshIdx.rightEyeOuter);
    final nose = pt(MeshIdx.noseBottom);
    final fh = pt(MeshIdx.forehead);
    final lm = pt(MeshIdx.leftMouth);
    final rm = pt(MeshIdx.rightMouth);
    final lf = pt(MeshIdx.leftFace);
    final rf = pt(MeshIdx.rightFace);
    final chin = pt(MeshIdx.chin);

    final eyeDist = (re - le).distance;
    final eyeCenter = Offset((le.dx + re.dx) / 2, (le.dy + re.dy) / 2);
    final mouth = Offset((lm.dx + rm.dx) / 2, (lm.dy + rm.dy) / 2);

    return FaceFrame._(
      leftEye: le,
      rightEye: re,
      noseBase: nose,
      forehead: fh,
      mouthCenter: mouth,
      center: eyeCenter,
      eyeDistance: eyeDist,
      rollRad: math.atan2(re.dy - le.dy, re.dx - le.dx),
      yawRad: face.yawRad,
      faceWidth: (rf - lf).distance,
      faceHeight: (chin - fh).distance,
    );
  }

  /// Fallback for when there's no detection (static position).
  factory FaceFrame.fallback(Size s) {
    return FaceFrame._(
      leftEye: Offset(s.width * 0.36, s.height * 0.39),
      rightEye: Offset(s.width * 0.64, s.height * 0.39),
      noseBase: Offset(s.width * 0.50, s.height * 0.44),
      forehead: Offset(s.width * 0.50, s.height * 0.32),
      mouthCenter: Offset(s.width * 0.50, s.height * 0.50),
      center: Offset(s.width * 0.50, s.height * 0.39),
      eyeDistance: s.width * 0.28,
      rollRad: 0,
      yawRad: 0,
      faceWidth: s.width * 0.52,
      faceHeight: s.height * 0.34,
    );
  }

  static int _fromSizeLogCounter = 0;
  factory FaceFrame.fromSize(Size s) {
    final face = maskCurrentTrackedFace;
    if (face != null && face.points.length >= 468) {
      final ff = FaceFrame.fromTracked(face, s);
      if (++_fromSizeLogCounter % 120 == 1) {
        debugPrint(
          '[FaceFrame.fromSize] TRACKED canvas=${s.width.toInt()}x${s.height.toInt()} '
          'leftEye=${ff.leftEye} rightEye=${ff.rightEye} '
          'center=${ff.center} eyeDist=${ff.eyeDistance.toStringAsFixed(1)} '
          'rollRad=${ff.rollRad.toStringAsFixed(3)}',
        );
      }
      return ff;
    }
    if (++_fromSizeLogCounter % 120 == 1) {
      debugPrint(
        '[FaceFrame.fromSize] FALLBACK canvas=${s.width.toInt()}x${s.height.toInt()} '
        'face=${face == null ? "null" : "pts=${face.points.length}"}',
      );
    }
    return FaceFrame.fallback(s);
  }

  double get yawScale => math.cos(yawRad).clamp(0.5, 1.0);

  void applyRotation(Canvas canvas) {
    if (rollRad.abs() > 0.01) {
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rollRad);
      canvas.translate(-center.dx, -center.dy);
    }
  }
}

// ─── 1. Cat ears ─────────────────────────────────────────────────────────

class CatEarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = FaceFrame.fromSize(size);
    canvas.save();
    f.applyRotation(canvas);

    final earH = f.eyeDistance * 1.1;
    final earW = f.eyeDistance * 0.7;

    for (final side in [-1, 1]) {
      final eye = side < 0 ? f.leftEye : f.rightEye;
      final base = Offset(eye.dx, f.forehead.dy - f.faceHeight * 0.1);
      final tip = Offset(base.dx + side * earW * 0.3, base.dy - earH);
      final p1 = Offset(base.dx - side * earW * 0.4, base.dy);
      final p2 = Offset(base.dx + side * earW * 0.5, base.dy);

      final outerPath = Path()..moveTo(p1.dx, p1.dy)..lineTo(tip.dx, tip.dy)..lineTo(p2.dx, p2.dy)..close();
      final innerPath = Path()
        ..moveTo(p1.dx + side * earW * 0.15, p1.dy - earH * 0.03)
        ..lineTo(tip.dx + side * earW * 0.02, tip.dy + earH * 0.18)
        ..lineTo(p2.dx - side * earW * 0.18, p2.dy - earH * 0.03)
        ..close();

      // Shadow
      canvas.drawPath(outerPath, Paint()..color = const Color(0x40000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      // Outer fur with gradient
      final outerPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF3D3230), const Color(0xFF1A1412)],
        ).createShader(Rect.fromLTWH(p1.dx, tip.dy, earW, earH));
      canvas.drawPath(outerPath, outerPaint);
      // Inner pink gradient
      final innerPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFFFFB3C6), const Color(0xFFFF7096)],
        ).createShader(Rect.fromLTWH(p1.dx, tip.dy, earW, earH));
      canvas.drawPath(innerPath, innerPaint);
    }

    // Nose
    final n = f.noseBase;
    final nW = f.eyeDistance * 0.14;
    final nosePath = Path()
      ..moveTo(n.dx, n.dy - nW * 0.3)
      ..cubicTo(n.dx + nW, n.dy, n.dx + nW * 0.5, n.dy + nW * 0.6, n.dx, n.dy + nW * 0.4)
      ..cubicTo(n.dx - nW * 0.5, n.dy + nW * 0.6, n.dx - nW, n.dy, n.dx, n.dy - nW * 0.3)
      ..close();
    canvas.drawPath(nosePath, Paint()..color = const Color(0xFF2A2A2A));
    canvas.drawPath(nosePath, Paint()..color = const Color(0x20FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 0.5);

    // Whiskers
    final wp = Paint()..color = Colors.white.withValues(alpha: 0.7)..strokeWidth = 1.2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    for (final side in [-1, 1]) {
      for (var k = 0; k < 3; k++) {
        final angle = (k - 1) * 0.15;
        canvas.drawLine(
          Offset(n.dx + side * nW * 1.5, n.dy + (k - 1) * 3),
          Offset(n.dx + side * f.eyeDistance * 0.55, n.dy + (k - 1) * 8 + angle * 10),
          wp,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── 2. Sunglasses ───────────────────────────────────────────────────────

class SunglassesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = FaceFrame.fromSize(size);
    canvas.save();
    f.applyRotation(canvas);

    final lensR = f.eyeDistance * 0.35;
    final frameW = lensR * 0.12;

    for (final eye in [f.leftEye, f.rightEye]) {
      final lensRect = Rect.fromCircle(center: eye, radius: lensR);
      // Shadow
      canvas.drawCircle(eye + Offset(0, 2), lensR + frameW, Paint()..color = const Color(0x30000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      // Frame
      canvas.drawCircle(eye, lensR + frameW, Paint()..color = const Color(0xFF1A1A1A));
      // Lens gradient
      canvas.drawCircle(eye, lensR, Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [const Color(0xFF3A3A4A), const Color(0xFF0A0A12)],
        ).createShader(lensRect));
      // Reflection arc
      final hlPath = Path()
        ..addArc(Rect.fromCircle(center: eye, radius: lensR * 0.75), -2.3, 1.2);
      canvas.drawPath(hlPath, Paint()..color = Colors.white.withValues(alpha: 0.18)..strokeWidth = lensR * 0.12..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    }

    // Bridge
    final bridgeY = (f.leftEye.dy + f.rightEye.dy) / 2;
    final bridgePath = Path()
      ..moveTo(f.leftEye.dx + lensR * 0.7, bridgeY - 2)
      ..cubicTo(f.center.dx - 4, bridgeY - lensR * 0.3, f.center.dx + 4, bridgeY - lensR * 0.3, f.rightEye.dx - lensR * 0.7, bridgeY - 2);
    canvas.drawPath(bridgePath, Paint()..color = const Color(0xFF1A1A1A)..strokeWidth = frameW * 1.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);

    // Temples (arms)
    for (final (eye, dir) in [(f.leftEye, -1.0), (f.rightEye, 1.0)]) {
      canvas.drawLine(
        Offset(eye.dx + dir * lensR, eye.dy),
        Offset(eye.dx + dir * (lensR + f.eyeDistance * 0.35), eye.dy + 4),
        Paint()..color = const Color(0xFF1A1A1A)..strokeWidth = frameW * 1.3..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── 3. Heart sunglasses ─────────────────────────────────────────────────

class HeartGlassesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = FaceFrame.fromSize(size);
    canvas.save();
    f.applyRotation(canvas);

    final s = f.eyeDistance * 0.4;

    for (final eye in [f.leftEye, f.rightEye]) {
      // Glow
      _drawHeart(canvas, eye, s * 1.15, Paint()..color = const Color(0x40FF3B6B)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      // Main heart with gradient
      final heartRect = Rect.fromCenter(center: eye, width: s * 2, height: s * 2);
      _drawHeart(canvas, eye, s, Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.3),
          colors: [const Color(0xFFFF6B8A), const Color(0xFFE0224E)],
        ).createShader(heartRect));
      // Highlight
      _drawHeart(canvas, eye + Offset(-s * 0.15, -s * 0.15), s * 0.3, Paint()..color = Colors.white.withValues(alpha: 0.3));
    }

    // Bridge
    final bridgeY = (f.leftEye.dy + f.rightEye.dy) / 2;
    canvas.drawPath(
      Path()
        ..moveTo(f.leftEye.dx + s * 0.6, bridgeY)
        ..cubicTo(f.center.dx - 3, bridgeY - s * 0.3, f.center.dx + 3, bridgeY - s * 0.3, f.rightEye.dx - s * 0.6, bridgeY),
      Paint()..color = const Color(0xFFE0224E)..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _drawHeart(Canvas canvas, Offset c, double size, Paint paint) {
    final s = size / 2;
    canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy + s * 0.5)
          ..cubicTo(c.dx + s * 1.4, c.dy - s * 0.4, c.dx + s * 0.6, c.dy - s * 1.3, c.dx, c.dy - s * 0.4)
          ..cubicTo(c.dx - s * 0.6, c.dy - s * 1.3, c.dx - s * 1.4, c.dy - s * 0.4, c.dx, c.dy + s * 0.5)
          ..close(),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── 4. Crown ────────────────────────────────────────────────────────────

class CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = FaceFrame.fromSize(size);
    canvas.save();
    f.applyRotation(canvas);

    final crownW = f.eyeDistance * 2.2;
    final crownH = f.eyeDistance * 0.9;
    final baseY = f.forehead.dy - f.faceHeight * 0.15;
    final tipY = baseY - crownH;
    final cx = f.center.dx;

    final crownPath = Path()
      ..moveTo(cx - crownW / 2, baseY + crownH * 0.1)
      ..lineTo(cx - crownW * 0.40, tipY + crownH * 0.45)
      ..lineTo(cx - crownW * 0.22, tipY)
      ..lineTo(cx, tipY + crownH * 0.25)
      ..lineTo(cx + crownW * 0.22, tipY)
      ..lineTo(cx + crownW * 0.40, tipY + crownH * 0.45)
      ..lineTo(cx + crownW / 2, baseY + crownH * 0.1)
      ..close();

    // Shadow
    canvas.drawPath(crownPath, Paint()..color = const Color(0x35000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // Gold gradient body
    canvas.drawPath(crownPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFFFFE36B), const Color(0xFFFFAB1A), const Color(0xFFD18B12)],
      ).createShader(Rect.fromLTWH(cx - crownW / 2, tipY, crownW, crownH * 1.2)));
    // Outline
    canvas.drawPath(crownPath, Paint()..color = const Color(0xFFB8860B)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    // Band at base
    canvas.drawRect(
      Rect.fromLTWH(cx - crownW / 2, baseY - crownH * 0.05, crownW, crownH * 0.15),
      Paint()..color = const Color(0xFFB8860B).withValues(alpha: 0.4),
    );

    // Jewels with glow
    final jewR = crownH * 0.09;
    final jewels = [
      (Offset(cx - crownW * 0.22, baseY - crownH * 0.05), const Color(0xFF5DB1FF), jewR),
      (Offset(cx, baseY - crownH * 0.08), const Color(0xFFFF3B6B), jewR * 1.3),
      (Offset(cx + crownW * 0.22, baseY - crownH * 0.05), const Color(0xFF2FA84F), jewR),
    ];
    for (final (pos, color, r) in jewels) {
      canvas.drawCircle(pos, r + 3, Paint()..color = color.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(pos, r, Paint()..color = color);
      canvas.drawCircle(pos + Offset(-r * 0.25, -r * 0.3), r * 0.3, Paint()..color = Colors.white.withValues(alpha: 0.5));
    }

    // Tip sparkles
    for (final tipX in [cx - crownW * 0.22, cx, cx + crownW * 0.22]) {
      canvas.drawCircle(Offset(tipX, tipY + (tipX == cx ? crownH * 0.25 : 0) - 2), 3,
        Paint()..color = const Color(0xFFFFE36B)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── 5. Dog ──────────────────────────────────────────────────────────────

class DogPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = FaceFrame.fromSize(size);
    canvas.save();
    f.applyRotation(canvas);

    // Ears — floppy with gradient
    for (final side in [-1, 1]) {
      final eye = side < 0 ? f.leftEye : f.rightEye;
      final base = Offset(eye.dx + side * f.eyeDistance * 0.4, eye.dy);
      final tip = Offset(base.dx + side * f.eyeDistance * 0.1, base.dy + f.eyeDistance * 0.9);
      final earPath = Path()
        ..moveTo(base.dx - side * f.eyeDistance * 0.1, base.dy - f.eyeDistance * 0.05)
        ..cubicTo(
          base.dx + side * f.eyeDistance * 0.2, base.dy + f.eyeDistance * 0.3,
          tip.dx + side * f.eyeDistance * 0.15, tip.dy - f.eyeDistance * 0.1,
          tip.dx, tip.dy,
        )
        ..cubicTo(
          tip.dx - side * f.eyeDistance * 0.1, tip.dy + f.eyeDistance * 0.05,
          base.dx - side * f.eyeDistance * 0.15, base.dy + f.eyeDistance * 0.4,
          base.dx + side * f.eyeDistance * 0.12, base.dy - f.eyeDistance * 0.05,
        )
        ..close();

      canvas.drawPath(earPath, Paint()..color = const Color(0x30000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawPath(earPath, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFFA06838), const Color(0xFF6B3F20)],
        ).createShader(Rect.fromPoints(base, tip)));
      // Inner ear
      canvas.drawPath(earPath, Paint()..color = const Color(0xFFD4956A).withValues(alpha: 0.3));
    }

    // Nose — shiny black
    final n = f.noseBase;
    final nW = f.eyeDistance * 0.22;
    final nosePath = Path()
      ..moveTo(n.dx, n.dy - nW * 0.4)
      ..cubicTo(n.dx + nW, n.dy - nW * 0.3, n.dx + nW * 0.4, n.dy + nW * 0.5, n.dx, n.dy + nW * 0.5)
      ..cubicTo(n.dx - nW * 0.4, n.dy + nW * 0.5, n.dx - nW, n.dy - nW * 0.3, n.dx, n.dy - nW * 0.4)
      ..close();
    canvas.drawPath(nosePath, Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawCircle(Offset(n.dx - nW * 0.2, n.dy - nW * 0.15), nW * 0.15, Paint()..color = Colors.white.withValues(alpha: 0.25));

    // Tongue
    final t = Offset(f.mouthCenter.dx, f.mouthCenter.dy + f.eyeDistance * 0.08);
    final tw = f.eyeDistance * 0.13;
    final th = f.eyeDistance * 0.28;
    final tonguePath = Path()
      ..moveTo(t.dx - tw, t.dy)
      ..quadraticBezierTo(t.dx, t.dy + th, t.dx + tw, t.dy)
      ..quadraticBezierTo(t.dx, t.dy - th * 0.05, t.dx - tw, t.dy)
      ..close();
    canvas.drawPath(tonguePath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFFFF8AAA), const Color(0xFFFF5C8A)],
      ).createShader(Rect.fromLTWH(t.dx - tw, t.dy, tw * 2, th)));
    // Tongue line
    canvas.drawLine(Offset(t.dx, t.dy + 2), Offset(t.dx, t.dy + th * 0.65),
      Paint()..color = const Color(0xFFE04070)..strokeWidth = 1..strokeCap = StrokeCap.round);

    // Whiskers
    final wp = Paint()..color = const Color(0xFFF0DCC0)..strokeWidth = 1.3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    for (final side in [-1, 1]) {
      for (var k = 0; k < 3; k++) {
        canvas.drawLine(
          Offset(n.dx + side * nW * 1.3, n.dy + (k - 1) * 4),
          Offset(n.dx + side * f.eyeDistance * 0.6, n.dy + (k - 1) * 10),
          wp,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── 6. Halo ─────────────────────────────────────────────────────────────

class HaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = FaceFrame.fromSize(size);
    canvas.save();
    f.applyRotation(canvas);

    final c = Offset(f.center.dx, f.topOfHead.dy - f.eyeDistance * 0.2);
    final r = f.eyeDistance * 0.85;

    // Outer glow
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 2.4, height: r * 0.7),
      Paint()..color = const Color(0xFFFFE36B).withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
    // Medium glow
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 2.1, height: r * 0.6),
      Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Ring — double stroke for thickness
    final ringRect = Rect.fromCenter(center: c, width: r * 2, height: r * 0.55);
    canvas.drawOval(ringRect, Paint()..color = const Color(0xFFFFD23C)..strokeWidth = 7..style = PaintingStyle.stroke);
    canvas.drawOval(ringRect, Paint()..color = const Color(0xFFFFE88A)..strokeWidth = 3..style = PaintingStyle.stroke);
    // Inner bright line
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 1.85, height: r * 0.48),
      Paint()..color = Colors.white.withValues(alpha: 0.15)..strokeWidth = 1..style = PaintingStyle.stroke,
    );

    // Sparkles around halo
    final sparkle = Paint()..color = const Color(0xFFFFE36B);
    for (var i = 0; i < 8; i++) {
      final a = math.pi + i * math.pi / 4 + 0.2;
      final sp = Offset(c.dx + math.cos(a) * r * 1.08, c.dy + math.sin(a) * r * 0.32);
      canvas.drawCircle(sp, 2.5, sparkle);
      canvas.drawCircle(sp, 5, Paint()..color = const Color(0xFFFFE36B).withValues(alpha: 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── 7. Floating hearts ──────────────────────────────────────────────────

class FloatingHeartsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = FaceFrame.fromSize(size);
    canvas.save();
    f.applyRotation(canvas);

    final positions = <(Offset, double, Color)>[
      (Offset(f.leftEye.dx - f.eyeDistance * 0.5, f.forehead.dy + 10), 22.0, const Color(0xFFFF3B6B)),
      (Offset(f.rightEye.dx + f.eyeDistance * 0.5, f.forehead.dy + 30), 18.0, const Color(0xFFFF6B8A)),
      (Offset(f.leftEye.dx, f.forehead.dy - f.eyeDistance * 0.4), 16.0, const Color(0xFFFF1744)),
      (Offset(f.rightEye.dx, f.forehead.dy - f.eyeDistance * 0.5), 22.0, const Color(0xFFFF3B6B)),
      (Offset(f.center.dx, f.forehead.dy - f.eyeDistance * 0.7), 14.0, const Color(0xFFFF8AAA)),
      (Offset(f.center.dx - f.eyeDistance * 0.3, f.center.dy), 10.0, const Color(0xFFFF6B8A)),
      (Offset(f.center.dx + f.eyeDistance * 0.4, f.forehead.dy), 12.0, const Color(0xFFFF3B6B)),
    ];
    for (final (p, sz, color) in positions) {
      // Glow
      _drawHeart(canvas, p, sz * 1.2, Paint()..color = color.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      // Heart
      _drawHeart(canvas, p, sz, Paint()..color = color);
      // Highlight
      _drawHeart(canvas, p + Offset(-sz * 0.08, -sz * 0.1), sz * 0.3, Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
    canvas.restore();
  }

  void _drawHeart(Canvas canvas, Offset c, double size, Paint paint) {
    final s = size / 2;
    canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy + s * 0.5)
          ..cubicTo(c.dx + s * 1.4, c.dy - s * 0.4, c.dx + s * 0.6, c.dy - s * 1.3, c.dx, c.dy - s * 0.4)
          ..cubicTo(c.dx - s * 0.6, c.dy - s * 1.3, c.dx - s * 1.4, c.dy - s * 0.4, c.dx, c.dy + s * 0.5)
          ..close(),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── 8. Bunny ears ───────────────────────────────────────────────────────

class BunnyEarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = FaceFrame.fromSize(size);
    canvas.save();
    f.applyRotation(canvas);

    final earH = f.eyeDistance * 1.5;
    final earW = f.eyeDistance * 0.35;

    for (final side in [-1, 1]) {
      final eye = side < 0 ? f.leftEye : f.rightEye;
      final cx = eye.dx;
      final cy = f.topOfHead.dy - earH * 0.3;
      final earRect = Rect.fromCenter(center: Offset(cx, cy), width: earW, height: earH);
      final innerRect = Rect.fromCenter(center: Offset(cx, cy + earH * 0.05), width: earW * 0.55, height: earH * 0.78);

      // Shadow
      canvas.drawOval(earRect.shift(const Offset(2, 3)), Paint()..color = const Color(0x25000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      // Outer — white gradient
      canvas.drawOval(earRect, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, const Color(0xFFEEEEEE)],
        ).createShader(earRect));
      // Outline
      canvas.drawOval(earRect, Paint()..color = const Color(0xFFDDDDDD)..style = PaintingStyle.stroke..strokeWidth = 1);
      // Inner pink gradient
      canvas.drawOval(innerRect, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFFFFD6E0), const Color(0xFFFFB3C6)],
        ).createShader(innerRect));
    }

    // Bunny nose
    final n = f.noseBase;
    final nR = f.eyeDistance * 0.06;
    canvas.drawOval(
      Rect.fromCenter(center: n, width: nR * 2.5, height: nR * 1.8),
      Paint()..color = const Color(0xFFFFB3C6),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── Catalog ─────────────────────────────────────────────────────────────

class MaskCatalog {
  MaskCatalog._();

  static final List<MaskDescriptor> all = [
    MaskDescriptor(id: 'cat', label: 'Котик', previewIcon: Icons.pets, painter: () => CatEarsPainter()),
    MaskDescriptor(id: 'sunglasses', label: 'Очки', previewIcon: Icons.wb_sunny, painter: () => SunglassesPainter()),
    MaskDescriptor(id: 'heart_glasses', label: 'Сердечки', previewIcon: Icons.favorite, painter: () => HeartGlassesPainter()),
    MaskDescriptor(id: 'crown', label: 'Корона', previewIcon: Icons.emoji_events, painter: () => CrownPainter()),
    MaskDescriptor(id: 'dog', label: 'Пёс', previewIcon: Icons.pets, painter: () => DogPainter()),
    MaskDescriptor(id: 'halo', label: 'Ангел', previewIcon: Icons.auto_awesome, painter: () => HaloPainter()),
    MaskDescriptor(id: 'hearts', label: 'Любовь', previewIcon: Icons.favorite_border, painter: () => FloatingHeartsPainter()),
    MaskDescriptor(id: 'bunny', label: 'Зайчик', previewIcon: Icons.cruelty_free, painter: () => BunnyEarsPainter()),
    MaskDescriptor(id: 'calibration', label: 'Калибровка', previewIcon: Icons.grid_on, painter: () => CalibrationPainter()),
    // ── Lottie animated masks ──────────────────────────────────────────────
    MaskDescriptor(
      id: 'lottie_tears',
      label: 'Слёзы',
      previewIcon: Icons.water_drop,
      lottiePath: 'assets/masks/anime_tears.json',
      lottieAnchor: LottieAnchorType.fullFace,
    ),
    MaskDescriptor(
      id: 'lottie_butterflies',
      label: 'Бабочки',
      previewIcon: Icons.flutter_dash,
      lottiePath: 'assets/masks/butterflies.json',
      lottieAnchor: LottieAnchorType.fullFace,
    ),
    MaskDescriptor(
      id: 'lottie_crown',
      label: 'Корона 3D',
      previewIcon: Icons.auto_awesome,
      lottiePath: 'assets/masks/gold_crown.json',
      lottieAnchor: LottieAnchorType.topOfHead,
    ),
    MaskDescriptor(
      id: 'lottie_flowers',
      label: 'Венок',
      previewIcon: Icons.local_florist,
      lottiePath: 'assets/masks/flower_crown.json',
      lottieAnchor: LottieAnchorType.topOfHead,
    ),
    MaskDescriptor(
      id: 'lottie_bunny',
      label: 'Зайчик 3D',
      previewIcon: Icons.cruelty_free,
      lottiePath: 'assets/masks/bunny.json',
      lottieAnchor: LottieAnchorType.foreheadCenter,
    ),
  ];
}
