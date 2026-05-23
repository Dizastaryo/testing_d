import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'calibration_painter.dart';
import 'face_tracking_service.dart';

class MaskDescriptor {
  final String id;
  final String label;
  final IconData previewIcon;
  final CustomPainter Function() painter;

  const MaskDescriptor({
    required this.id,
    required this.label,
    required this.previewIcon,
    required this.painter,
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
    final outer = Paint()..color = const Color(0xFF1F1A18);
    final inner = Paint()..color = const Color(0xFFFF8AA6);

    for (final side in [-1, 1]) {
      final eye = side < 0 ? f.leftEye : f.rightEye;
      final base = Offset(eye.dx, f.topOfHead.dy);
      final tip = Offset(base.dx + side * earW * 0.3, base.dy - earH);
      final p1 = Offset(base.dx - side * earW * 0.4, base.dy);
      final p2 = Offset(base.dx + side * earW * 0.5, base.dy);

      canvas.drawPath(
          Path()..moveTo(p1.dx, p1.dy)..lineTo(tip.dx, tip.dy)..lineTo(p2.dx, p2.dy)..close(),
          outer);
      canvas.drawPath(
          Path()
            ..moveTo(p1.dx + side * earW * 0.15, p1.dy - earH * 0.03)
            ..lineTo(tip.dx + side * earW * 0.02, tip.dy + earH * 0.18)
            ..lineTo(p2.dx - side * earW * 0.18, p2.dy - earH * 0.03)
            ..close(),
          inner);
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
    final frame = Paint()..color = const Color(0xFF0A0A0A);
    final lens = Paint()..color = const Color(0xFF1A1A1A);
    final hl = Paint()..color = Colors.white.withValues(alpha: 0.25);

    canvas.drawCircle(f.leftEye, lensR + 4, frame);
    canvas.drawCircle(f.rightEye, lensR + 4, frame);
    canvas.drawCircle(f.leftEye, lensR, lens);
    canvas.drawCircle(f.rightEye, lensR, lens);
    canvas.drawCircle(f.leftEye + Offset(-lensR * 0.4, -lensR * 0.4), lensR * 0.25, hl);
    canvas.drawCircle(f.rightEye + Offset(-lensR * 0.4, -lensR * 0.4), lensR * 0.25, hl);

    final bridge = Offset((f.leftEye.dx + f.rightEye.dx) / 2, (f.leftEye.dy + f.rightEye.dy) / 2);
    canvas.drawRect(
        Rect.fromCenter(center: bridge, width: f.eyeDistance - lensR * 2 + 8, height: 5), frame);
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
    final pink = Paint()..color = const Color(0xFFFF3B6B);
    _drawHeart(canvas, f.leftEye, s, pink);
    _drawHeart(canvas, f.rightEye, s, pink);

    final bridge = Offset((f.leftEye.dx + f.rightEye.dx) / 2, (f.leftEye.dy + f.rightEye.dy) / 2);
    canvas.drawRect(Rect.fromCenter(center: bridge, width: f.eyeDistance - s + 6, height: 4), pink);
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
    final baseY = f.topOfHead.dy;
    final tipY = baseY - crownH;
    final cx = f.center.dx;

    final gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE36B), Color(0xFFFFAB1A), Color(0xFFD18B12)],
      ).createShader(Rect.fromLTWH(cx - crownW / 2, tipY, crownW, crownH * 1.2));

    canvas.drawPath(
        Path()
          ..moveTo(cx - crownW / 2, baseY + crownH * 0.1)
          ..lineTo(cx - crownW * 0.40, tipY + crownH * 0.45)
          ..lineTo(cx - crownW * 0.22, tipY)
          ..lineTo(cx, tipY + crownH * 0.25)
          ..lineTo(cx + crownW * 0.22, tipY)
          ..lineTo(cx + crownW * 0.40, tipY + crownH * 0.45)
          ..lineTo(cx + crownW / 2, baseY + crownH * 0.1)
          ..close(),
        gold);

    final jewR = crownH * 0.08;
    canvas.drawCircle(Offset(cx - crownW * 0.22, baseY - crownH * 0.05), jewR, Paint()..color = const Color(0xFF5DB1FF));
    canvas.drawCircle(Offset(cx, baseY - crownH * 0.05), jewR * 1.25, Paint()..color = const Color(0xFFFF3B6B));
    canvas.drawCircle(Offset(cx + crownW * 0.22, baseY - crownH * 0.05), jewR, Paint()..color = const Color(0xFF2FA84F));
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

    final brown = Paint()..color = const Color(0xFF8A5A3B);
    final black = Paint()..color = const Color(0xFF1A1A1A);
    final pink = Paint()..color = const Color(0xFFFF8AA6);

    // Ears
    for (final side in [-1, 1]) {
      final eye = side < 0 ? f.leftEye : f.rightEye;
      final base = Offset(eye.dx + side * f.eyeDistance * 0.4, eye.dy);
      final tip = Offset(base.dx + side * f.eyeDistance * 0.1, base.dy + f.eyeDistance * 0.9);
      final mid = Offset(base.dx - side * f.eyeDistance * 0.05, base.dy + f.eyeDistance * 0.5);
      canvas.drawPath(
          Path()
            ..moveTo(base.dx - side * f.eyeDistance * 0.08, base.dy)
            ..quadraticBezierTo(tip.dx + side * f.eyeDistance * 0.15, tip.dy, mid.dx, mid.dy)
            ..lineTo(base.dx + side * f.eyeDistance * 0.12, base.dy - f.eyeDistance * 0.05)
            ..close(),
          brown);
    }

    // Nose
    final n = f.noseBase;
    final nW = f.eyeDistance * 0.22;
    canvas.drawPath(
        Path()
          ..moveTo(n.dx, n.dy - nW * 0.4)
          ..cubicTo(n.dx + nW, n.dy - nW * 0.3, n.dx + nW * 0.4, n.dy + nW * 0.5, n.dx, n.dy + nW * 0.5)
          ..cubicTo(n.dx - nW * 0.4, n.dy + nW * 0.5, n.dx - nW, n.dy - nW * 0.3, n.dx, n.dy - nW * 0.4)
          ..close(),
        black);

    // Tongue
    final t = Offset(f.mouthCenter.dx, f.mouthCenter.dy + f.eyeDistance * 0.1);
    final tw = f.eyeDistance * 0.12;
    final th = f.eyeDistance * 0.25;
    canvas.drawPath(
        Path()
          ..moveTo(t.dx - tw, t.dy)
          ..quadraticBezierTo(t.dx, t.dy + th, t.dx + tw, t.dy)
          ..quadraticBezierTo(t.dx, t.dy - th * 0.08, t.dx - tw, t.dy)
          ..close(),
        pink);

    // Whiskers
    final wp = Paint()..color = const Color(0xFFF7E1C2)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    for (final side in [-1, 1]) {
      for (var k = 0; k < 3; k++) {
        canvas.drawLine(
          Offset(n.dx + side * nW * 1.2, n.dy + (k - 1) * 4),
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
    final r = f.eyeDistance * 0.8;
    canvas.drawCircle(c, r + 8,
        Paint()..color = const Color(0xFFFFE36B).withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 0.55),
        Paint()..color = const Color(0xFFFFD23C)..strokeWidth = 6..style = PaintingStyle.stroke);

    final starP = Paint()..color = const Color(0xFFFFE36B);
    for (var i = 0; i < 6; i++) {
      final a = math.pi + i * math.pi / 5;
      canvas.drawCircle(Offset(c.dx + math.cos(a) * r * 1.02, c.dy + math.sin(a) * r * 0.27), 3, starP);
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

    final paint = Paint()..color = const Color(0xFFFF3B6B);
    final positions = [
      (Offset(f.leftEye.dx - f.eyeDistance * 0.5, f.forehead.dy + 10), 22.0),
      (Offset(f.rightEye.dx + f.eyeDistance * 0.5, f.forehead.dy + 30), 18.0),
      (Offset(f.leftEye.dx, f.forehead.dy - f.eyeDistance * 0.4), 16.0),
      (Offset(f.rightEye.dx, f.forehead.dy - f.eyeDistance * 0.5), 22.0),
      (Offset(f.center.dx, f.forehead.dy - f.eyeDistance * 0.7), 14.0),
    ];
    for (final (p, s) in positions) {
      canvas.drawPath(
          Path()
            ..moveTo(p.dx, p.dy + s * 0.6)
            ..cubicTo(p.dx + s * 1.2, p.dy - s * 0.2, p.dx + s * 0.4, p.dy - s * 1.1, p.dx, p.dy - s * 0.2)
            ..cubicTo(p.dx - s * 0.4, p.dy - s * 1.1, p.dx - s * 1.2, p.dy - s * 0.2, p.dx, p.dy + s * 0.6)
            ..close(),
          paint);
    }
    canvas.restore();
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

    final white = Paint()..color = Colors.white;
    final pink = Paint()..color = const Color(0xFFFFC9D6);
    final earH = f.eyeDistance * 1.5;
    final earW = f.eyeDistance * 0.35;

    for (final side in [-1, 1]) {
      final eye = side < 0 ? f.leftEye : f.rightEye;
      final cx = eye.dx;
      final cy = f.topOfHead.dy - earH * 0.3;
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: earW, height: earH), white);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy + earH * 0.05), width: earW * 0.55, height: earH * 0.78), pink);
    }
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
  ];
}
