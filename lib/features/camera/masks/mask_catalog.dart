import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'face_tracking_service.dart';

/// Каталог встроенных AR-масок. Каждая маска — CustomPainter, который
/// рисует overlay в области предполагаемого face-frame (top-half of preview,
/// центрировано по X). Анхор-точки рассчитываются как пропорции от
/// `Size canvas`:
///   - center.x = w/2
///   - center.y = h*0.42 (примерное положение носа человека в селфи)
///   - faceWidth ≈ w * 0.52
///
/// На web реальное face-detection недоступно — позиционируем по этим эвристикам.
/// На mobile (iOS/Android) — будущая интеграция ML Kit face-mesh: маска
/// перепозиционируется по реальным landmark'ам.

class MaskDescriptor {
  final String id;
  final String label;
  final IconData previewIcon; // для picker'а
  final CustomPainter Function() painter;

  const MaskDescriptor({
    required this.id,
    required this.label,
    required this.previewIcon,
    required this.painter,
  });
}

/// Текущая отслеженная маркой face. Painters читают это static-поле.
/// Обновляется `MaskOverlay` при event'ах от `FaceTrackingService`.
///
/// Static-design нужен потому что CustomPainter создаётся в каждом `painter()`
/// fabric'е без context'а — нет легитимного способа передать live face-data
/// через дерево виджетов. Альтернатива (рефактор `painter` field на
/// `(Size, TrackedFace?) → CustomPainter`) добавляет boilerplate в каждый
/// callsite. Static field — pragmatic.
TrackedFace? maskCurrentTrackedFace;

/// Подбираем face-frame в canvas-координатах. Если на static-поле выше
/// есть актуальный TrackedFace — используем его (real-time anchoring на
/// mobile). Иначе — fallback на heuristic (центр-верх кадра, для Chrome).
class _FaceFrame {
  final Offset center;
  final double width;
  final double height;
  final double rollRadians; // для будущей rotation масок

  _FaceFrame._(this.center, this.width, this.height, [this.rollRadians = 0]);

  factory _FaceFrame.fromSize(Size s) {
    final face = maskCurrentTrackedFace;
    if (face != null) {
      // image-space relative → canvas-space pixels
      final r = face.boundingBoxRelative;
      // Note: front-camera = mirrored. CameraPreview уже зеркалит. Координаты
      // ML Kit приходят в image-coords (не зеркало), но т.к. preview зеркальный
      // — придётся отзеркалить X: 1.0 - cx_relative.
      final cxRel = 1.0 - (r.left + r.width / 2);
      final cyRel = r.top + r.height / 2;
      return _FaceFrame._(
        Offset(cxRel * s.width, cyRel * s.height),
        r.width * s.width,
        r.height * s.height,
        -face.rollRadians, // mirror roll тоже
      );
    }
    // Fallback heuristic — Chrome или mobile до первого detection-event'а.
    return _FaceFrame._(
      Offset(s.width / 2, s.height * 0.42),
      s.width * 0.52,
      s.height * 0.34,
    );
  }

  Offset get top => Offset(center.dx, center.dy - height / 2);
  Offset get nose => Offset(center.dx, center.dy);
  Offset get leftEye =>
      Offset(center.dx - width * 0.22, center.dy - height * 0.08);
  Offset get rightEye =>
      Offset(center.dx + width * 0.22, center.dy - height * 0.08);
  Offset get mouth => Offset(center.dx, center.dy + height * 0.20);
}

// ─── 1. Cat ears ──────────────────────────────────────────────────────────

class CatEarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = _FaceFrame.fromSize(size);
    final earH = f.height * 0.42;
    final earW = f.width * 0.30;
    final innerScale = 0.55;

    final outer = Paint()..color = const Color(0xFF1F1A18);
    final inner = Paint()..color = const Color(0xFFFF8AA6);

    for (final side in [-1, 1]) {
      final base = Offset(
          f.center.dx + side * f.width * 0.30, f.center.dy - f.height * 0.40);
      final tip = Offset(base.dx + side * earW * 0.25, base.dy - earH);
      final inner1 = Offset(base.dx - side * earW * 0.40, base.dy);
      final inner2 = Offset(base.dx + side * earW * 0.55, base.dy);

      final path = Path()
        ..moveTo(inner1.dx, inner1.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(inner2.dx, inner2.dy)
        ..close();
      canvas.drawPath(path, outer);

      final innerPath = Path()
        ..moveTo(inner1.dx + side * earW * 0.18,
            inner1.dy - earH * 0.05 * innerScale)
        ..lineTo(tip.dx + side * earW * 0.04 * innerScale,
            tip.dy + earH * 0.18 * innerScale)
        ..lineTo(inner2.dx - side * earW * 0.20,
            inner2.dy - earH * 0.05 * innerScale)
        ..close();
      canvas.drawPath(innerPath, inner);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── 2. Sunglasses ───────────────────────────────────────────────────────

class SunglassesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = _FaceFrame.fromSize(size);
    final lensR = f.width * 0.16;
    final lensY = f.center.dy - f.height * 0.08;
    final bridgeY = lensY;

    final frame = Paint()
      ..color = const Color(0xFF0A0A0A)
      ..style = PaintingStyle.fill;
    final lensFill = Paint()
      ..color = const Color(0xFF1A1A1A);
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final leftCenter = Offset(f.center.dx - f.width * 0.22, lensY);
    final rightCenter = Offset(f.center.dx + f.width * 0.22, lensY);

    // Lenses
    canvas.drawCircle(leftCenter, lensR + 4, frame);
    canvas.drawCircle(rightCenter, lensR + 4, frame);
    canvas.drawCircle(leftCenter, lensR, lensFill);
    canvas.drawCircle(rightCenter, lensR, lensFill);
    // Highlights
    canvas.drawCircle(
        leftCenter + Offset(-lensR * 0.4, -lensR * 0.4), lensR * 0.3, highlight);
    canvas.drawCircle(rightCenter + Offset(-lensR * 0.4, -lensR * 0.4),
        lensR * 0.3, highlight);
    // Bridge
    final bridge = Rect.fromCenter(
      center: Offset(f.center.dx, bridgeY),
      width: f.width * 0.13,
      height: 6,
    );
    canvas.drawRect(bridge, frame);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── 3. Heart sunglasses (с двумя сердцами) ──────────────────────────────

class HeartGlassesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = _FaceFrame.fromSize(size);
    final lensSize = f.width * 0.18;
    final y = f.center.dy - f.height * 0.08;
    final leftC = Offset(f.center.dx - f.width * 0.22, y);
    final rightC = Offset(f.center.dx + f.width * 0.22, y);

    final pink = Paint()..color = const Color(0xFFFF3B6B);
    final bridge = Paint()..color = const Color(0xFFFF3B6B);

    _drawHeart(canvas, leftC, lensSize, pink);
    _drawHeart(canvas, rightC, lensSize, pink);
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(f.center.dx, y), width: f.width * 0.12, height: 5),
      bridge,
    );
  }

  void _drawHeart(Canvas canvas, Offset c, double size, Paint paint) {
    final p = Path();
    final s = size / 2;
    p.moveTo(c.dx, c.dy + s * 0.5);
    p.cubicTo(c.dx + s * 1.4, c.dy - s * 0.4, c.dx + s * 0.6, c.dy - s * 1.3,
        c.dx, c.dy - s * 0.4);
    p.cubicTo(c.dx - s * 0.6, c.dy - s * 1.3, c.dx - s * 1.4, c.dy - s * 0.4,
        c.dx, c.dy + s * 0.5);
    p.close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── 4. Crown (золотая корона) ───────────────────────────────────────────

class CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = _FaceFrame.fromSize(size);
    final top = f.top;
    final crownH = f.height * 0.30;
    final crownW = f.width * 0.85;
    final baseY = top.dy - crownH * 0.15;
    final tipY = baseY - crownH;

    final goldGrad = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE36B), Color(0xFFFFAB1A), Color(0xFFD18B12)],
      ).createShader(Rect.fromLTWH(
          f.center.dx - crownW / 2, tipY, crownW, crownH * 1.2));

    final path = Path();
    path.moveTo(f.center.dx - crownW / 2, baseY + crownH * 0.1);
    path.lineTo(f.center.dx - crownW * 0.40, tipY + crownH * 0.45);
    path.lineTo(f.center.dx - crownW * 0.22, tipY);
    path.lineTo(f.center.dx, tipY + crownH * 0.25);
    path.lineTo(f.center.dx + crownW * 0.22, tipY);
    path.lineTo(f.center.dx + crownW * 0.40, tipY + crownH * 0.45);
    path.lineTo(f.center.dx + crownW / 2, baseY + crownH * 0.1);
    path.close();
    canvas.drawPath(path, goldGrad);

    // 3 jewels
    final ruby = Paint()..color = const Color(0xFFFF3B6B);
    final saph = Paint()..color = const Color(0xFF5DB1FF);
    final emer = Paint()..color = const Color(0xFF2FA84F);
    canvas.drawCircle(
        Offset(f.center.dx - crownW * 0.22, baseY - crownH * 0.05),
        crownH * 0.08,
        saph);
    canvas.drawCircle(
        Offset(f.center.dx, baseY - crownH * 0.05), crownH * 0.10, ruby);
    canvas.drawCircle(
        Offset(f.center.dx + crownW * 0.22, baseY - crownH * 0.05),
        crownH * 0.08,
        emer);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── 5. Dog ears + nose + tongue ─────────────────────────────────────────

class DogPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = _FaceFrame.fromSize(size);
    final brown = Paint()..color = const Color(0xFF8A5A3B);
    final cream = Paint()..color = const Color(0xFFF7E1C2);
    final black = Paint()..color = const Color(0xFF1A1A1A);
    final pink = Paint()..color = const Color(0xFFFF8AA6);

    // Ears — hanging side flaps
    for (final side in [-1, 1]) {
      final base = Offset(
          f.center.dx + side * f.width * 0.42, f.center.dy - f.height * 0.30);
      final tip = Offset(
          base.dx + side * f.width * 0.06, base.dy + f.height * 0.32);
      final inner = Offset(
          base.dx - side * f.width * 0.04, base.dy + f.height * 0.18);
      final path = Path()
        ..moveTo(base.dx - side * f.width * 0.06, base.dy)
        ..quadraticBezierTo(tip.dx + side * f.width * 0.10, tip.dy,
            inner.dx, inner.dy)
        ..lineTo(base.dx + side * f.width * 0.08, base.dy - f.height * 0.04)
        ..close();
      canvas.drawPath(path, brown);
    }

    // Nose
    final nose = Path();
    final n = Offset(f.center.dx, f.center.dy + f.height * 0.04);
    final nW = f.width * 0.10;
    nose.moveTo(n.dx, n.dy - nW * 0.4);
    nose.cubicTo(n.dx + nW, n.dy - nW * 0.3, n.dx + nW * 0.4, n.dy + nW * 0.5,
        n.dx, n.dy + nW * 0.5);
    nose.cubicTo(n.dx - nW * 0.4, n.dy + nW * 0.5, n.dx - nW, n.dy - nW * 0.3,
        n.dx, n.dy - nW * 0.4);
    nose.close();
    canvas.drawPath(nose, black);

    // Tongue
    final t = Offset(f.center.dx, f.mouth.dy + f.height * 0.05);
    final tonguePath = Path();
    tonguePath.moveTo(t.dx - f.width * 0.06, t.dy);
    tonguePath.quadraticBezierTo(t.dx, t.dy + f.height * 0.10,
        t.dx + f.width * 0.06, t.dy);
    tonguePath.quadraticBezierTo(t.dx, t.dy - f.height * 0.01,
        t.dx - f.width * 0.06, t.dy);
    tonguePath.close();
    canvas.drawPath(tonguePath, pink);

    // Whiskers (cream)
    final wp = Paint()
      ..color = cream.color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final side in [-1, 1]) {
      for (var k = 0; k < 3; k++) {
        canvas.drawLine(
          Offset(n.dx + side * nW * 1.2, n.dy + (k - 1) * 4),
          Offset(n.dx + side * f.width * 0.22, n.dy + (k - 1) * 10),
          wp,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── 6. Halo (нимб) ──────────────────────────────────────────────────────

class HaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = _FaceFrame.fromSize(size);
    final c = Offset(f.center.dx, f.top.dy - f.height * 0.12);
    final r = f.width * 0.30;
    final glow = Paint()
      ..color = const Color(0xFFFFE36B).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final ring = Paint()
      ..color = const Color(0xFFFFD23C)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, r + 8, glow);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 2, height: r * 0.55),
      ring,
    );
    // Stars
    final starP = Paint()..color = const Color(0xFFFFE36B);
    for (var i = 0; i < 6; i++) {
      final angle = math.pi + i * math.pi / 5;
      final sx = c.dx + math.cos(angle) * r * 1.02;
      final sy = c.dy + math.sin(angle) * (r * 0.27);
      canvas.drawCircle(Offset(sx, sy), 3, starP);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── 7. Floating hearts (over face) ──────────────────────────────────────

class FloatingHeartsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = _FaceFrame.fromSize(size);
    final hearts = <Offset, double>{
      Offset(f.center.dx - f.width * 0.45, f.top.dy + 10): 22.0,
      Offset(f.center.dx + f.width * 0.45, f.top.dy + 30): 18.0,
      Offset(f.center.dx - f.width * 0.30, f.top.dy - 30): 16.0,
      Offset(f.center.dx + f.width * 0.30, f.top.dy - 40): 22.0,
      Offset(f.center.dx, f.top.dy - 50): 14.0,
    };
    final paint = Paint();
    hearts.forEach((p, s) {
      paint.color = const Color(0xFFFF3B6B);
      final path = Path();
      path.moveTo(p.dx, p.dy + s * 0.6);
      path.cubicTo(p.dx + s * 1.2, p.dy - s * 0.2, p.dx + s * 0.4,
          p.dy - s * 1.1, p.dx, p.dy - s * 0.2);
      path.cubicTo(p.dx - s * 0.4, p.dy - s * 1.1, p.dx - s * 1.2,
          p.dy - s * 0.2, p.dx, p.dy + s * 0.6);
      path.close();
      canvas.drawPath(path, paint);
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── 8. Bunny ears ───────────────────────────────────────────────────────

class BunnyEarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final f = _FaceFrame.fromSize(size);
    final white = Paint()..color = Colors.white;
    final pink = Paint()..color = const Color(0xFFFFC9D6);
    final earH = f.height * 0.55;
    final earW = f.width * 0.16;

    for (final side in [-1, 1]) {
      final cx = f.center.dx + side * f.width * 0.20;
      final cy = f.top.dy - earH * 0.45;
      final outerRect = Rect.fromCenter(
          center: Offset(cx, cy), width: earW, height: earH);
      canvas.drawOval(outerRect, white);
      final innerRect = Rect.fromCenter(
          center: Offset(cx, cy + earH * 0.05),
          width: earW * 0.55,
          height: earH * 0.78);
      canvas.drawOval(innerRect, pink);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Catalog ─────────────────────────────────────────────────────────────

class MaskCatalog {
  MaskCatalog._();

  static final List<MaskDescriptor> all = [
    MaskDescriptor(
      id: 'cat',
      label: 'Котик',
      previewIcon: Icons.pets,
      painter: () => CatEarsPainter(),
    ),
    MaskDescriptor(
      id: 'sunglasses',
      label: 'Очки',
      previewIcon: Icons.wb_sunny,
      painter: () => SunglassesPainter(),
    ),
    MaskDescriptor(
      id: 'heart_glasses',
      label: 'Сердечки',
      previewIcon: Icons.favorite,
      painter: () => HeartGlassesPainter(),
    ),
    MaskDescriptor(
      id: 'crown',
      label: 'Корона',
      previewIcon: Icons.emoji_events,
      painter: () => CrownPainter(),
    ),
    MaskDescriptor(
      id: 'dog',
      label: 'Пёс',
      previewIcon: Icons.pets,
      painter: () => DogPainter(),
    ),
    MaskDescriptor(
      id: 'halo',
      label: 'Ангел',
      previewIcon: Icons.auto_awesome,
      painter: () => HaloPainter(),
    ),
    MaskDescriptor(
      id: 'hearts',
      label: 'Любовь',
      previewIcon: Icons.favorite_border,
      painter: () => FloatingHeartsPainter(),
    ),
    MaskDescriptor(
      id: 'bunny',
      label: 'Зайка',
      previewIcon: Icons.cruelty_free,
      painter: () => BunnyEarsPainter(),
    ),
  ];

  static MaskDescriptor? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }
}
