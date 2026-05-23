import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'face_tracking_service.dart';
import 'mask_catalog.dart';

// ─── MediaPipe 468-mesh contour indices ──────────────────────────────────

const _faceOval = [
  10,338,297,332,284,251,389,356,454,323,361,288,
  397,365,379,378,400,377,152,148,176,149,150,136,
  172,58,132,93,234,127,162,21,54,103,67,109,10,
];

const _leftEye = [33,7,163,144,145,153,154,155,133,173,157,158,159,160,161,246,33];
const _rightEye = [263,249,390,373,374,380,381,382,362,398,384,385,386,387,388,466,263];
const _leftEyebrow = [46,53,52,65,55,70,63,105,66,107,46];
const _rightEyebrow = [276,283,282,295,285,300,293,334,296,336,276];
const _lipsOuter = [61,146,91,181,84,17,314,405,321,375,291,409,270,269,267,0,37,39,40,185,61];
const _lipsInner = [78,95,88,178,87,14,317,402,318,324,308,415,310,311,312,13,82,81,80,191,78];

/// The 9 key points we use in FaceFrame — highlighted in calibration.
const _keyPoints = <int, String>{
  33: 'L eye',
  263: 'R eye',
  2: 'noseB',
  1: 'noseT',
  10: 'fhead',
  152: 'chin',
  234: 'L face',
  454: 'R face',
  61: 'L mouth',
  291: 'R mouth',
  13: 'upLip',
  14: 'loLip',
};

/// Points to show Z values for
const _zDiagPoints = <int, String>{
  1: 'nose',
  234: 'Lface',
  454: 'Rface',
  10: 'fhead',
  152: 'chin',
};

class CalibrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final face = maskCurrentTrackedFace;
    if (face == null || face.points.length < 468) return;

    final f = FaceFrame.fromTracked(face, size);

    // Use cover-mapping consistent with FaceFrame.fromTracked
    final imageW = face.imageWidth.toDouble();
    final imageH = face.imageHeight.toDouble();
    final scale = math.max(size.width / imageW, size.height / imageH);
    final dx = (size.width - imageW * scale) / 2;
    final dy = (size.height - imageH * scale) / 2;
    Offset map(int idx) {
      final p = face.pt(idx);
      return Offset(p.dx * scale + dx, p.dy * scale + dy);
    }

    // ── 1. All 468 points — small grey dots ──
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.35);
    for (var i = 0; i < face.points.length && i < 468; i++) {
      canvas.drawCircle(map(i), 1.2, dotPaint);
    }

    // ── 2. Contours ──
    _drawContour(canvas, face, map, _faceOval, const Color(0xFF00FF88), 1.5);
    _drawContour(canvas, face, map, _leftEye, const Color(0xFF00BFFF), 1.2);
    _drawContour(canvas, face, map, _rightEye, const Color(0xFF00BFFF), 1.2);
    _drawContour(canvas, face, map, _leftEyebrow, const Color(0xFFFFD700), 1.0);
    _drawContour(canvas, face, map, _rightEyebrow, const Color(0xFFFFD700), 1.0);
    _drawContour(canvas, face, map, _lipsOuter, const Color(0xFFFF4488), 1.2);
    _drawContour(canvas, face, map, _lipsInner, const Color(0xFFFF6699), 0.8);

    // ── 3. Key points — large orange dots with labels ──
    final keyPaint = Paint()..color = const Color(0xFFFF5A3C);
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 8,
      fontFamily: 'monospace',
      background: Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    for (final entry in _keyPoints.entries) {
      final p = map(entry.key);
      canvas.drawCircle(p, 3.5, keyPaint);
      _drawLabel(canvas, '${entry.key}', p + const Offset(5, -4), textStyle);
    }

    // ── 4. Axes ──
    // Roll axis (eye line)
    final le = map(MeshIdx.leftEyeOuter);
    final re = map(MeshIdx.rightEyeOuter);
    canvas.drawLine(le, re, Paint()..color = const Color(0xFF00FF00)..strokeWidth = 1.5);

    // Vertical axis (forehead → chin)
    final fh = map(MeshIdx.forehead);
    final chin = map(MeshIdx.chin);
    canvas.drawLine(fh, chin, Paint()..color = const Color(0xFFFF00FF)..strokeWidth = 1.0);

    // Center dot
    final center = map(MeshIdx.noseTip);
    canvas.drawCircle(center, 5, Paint()..color = const Color(0xFFFFFF00).withValues(alpha: 0.6));

    // ── 5. Z diagnostics + angles — text block bottom-right ──
    _drawZDiagnostics(canvas, size, face, f);
  }

  void _drawContour(Canvas canvas, TrackedFace face, Offset Function(int) map,
      List<int> indices, Color color, double width) {
    if (indices.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    final path = Path();
    final first = map(indices[0]);
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < indices.length; i++) {
      final p = map(indices[i]);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  void _drawZDiagnostics(Canvas canvas, Size size, TrackedFace face, FaceFrame f) {
    final hasZ = face.pointsZ != null && face.pointsZ!.isNotEmpty;

    // Compute pitchRad: angle of forehead→chin line vs vertical
    final fh = face.pt(MeshIdx.forehead);
    final chin = face.pt(MeshIdx.chin);
    final pitchRad = math.atan2(chin.dx - fh.dx, chin.dy - fh.dy);

    final lines = <String>[
      'roll=${f.rollRad.toStringAsFixed(2)} '
      'yaw=${f.yawRad.toStringAsFixed(2)} '
      'pitch=${pitchRad.toStringAsFixed(2)}',
      'pts=${face.points.length} hasZ=$hasZ',
    ];

    if (hasZ) {
      final zParts = <String>[];
      for (final e in _zDiagPoints.entries) {
        zParts.add('${e.value}=${face.z(e.key).toStringAsFixed(3)}');
      }
      lines.add(zParts.join(' '));
    }

    final style = TextStyle(
      color: Colors.greenAccent,
      fontSize: 10,
      fontFamily: 'monospace',
      height: 1.4,
      background: Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    final tp = TextPainter(
      text: TextSpan(text: lines.join('\n'), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 6, size.height - tp.height - 80));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
