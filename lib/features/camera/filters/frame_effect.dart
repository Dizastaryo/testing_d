import 'dart:math' as math;

import 'package:flutter/material.dart';

// ─── Sealed class ──────────────────────────────────────────────────────────

/// Рамочный эффект — рисуется поверх фото, перекрывая его края.
/// В отличие от [OverlayEffect], покрывает границы изображения, имитируя
/// физическую рамку (белый борт, полосы плёнки и т.д.).
sealed class FrameEffect {
  const FrameEffect();

  /// Рисует рамку на [canvas] при bake финального фото.
  void bake(Canvas canvas, Size size);
}

class PolaroidFrame extends FrameEffect {
  final String? caption;
  const PolaroidFrame({this.caption});

  @override
  void bake(Canvas canvas, Size size) =>
      _PolaroidPainter(caption).paint(canvas, size);
}

class FilmStripFrame extends FrameEffect {
  final String filmLabel; // «KODAK 400TX», «FUJI 200» и т.д.
  final int frameNumber;
  const FilmStripFrame({
    this.filmLabel = 'KODAK 400TX',
    this.frameNumber = 23,
  });

  @override
  void bake(Canvas canvas, Size size) =>
      _FilmStripPainter(filmLabel, frameNumber).paint(canvas, size);
}

class DisposableCameraFrame extends FrameEffect {
  const DisposableCameraFrame();

  @override
  void bake(Canvas canvas, Size size) =>
      _DisposablePainter().paint(canvas, size);
}

class ScrapbookFrame extends FrameEffect {
  const ScrapbookFrame();

  @override
  void bake(Canvas canvas, Size size) =>
      _ScrapbookPainter().paint(canvas, size);
}

class TapeEffect extends FrameEffect {
  const TapeEffect();

  @override
  void bake(Canvas canvas, Size size) =>
      _TapePainter().paint(canvas, size);
}

// ─── FrameOverlay widget ───────────────────────────────────────────────────

/// Оборачивает camera preview, рисует рамку поверх через [CustomPaint].
class FrameOverlay extends StatelessWidget {
  final FrameEffect effect;

  const FrameOverlay({super.key, required this.effect});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FramePainter(effect));
  }
}

class _FramePainter extends CustomPainter {
  final FrameEffect effect;
  const _FramePainter(this.effect);

  @override
  void paint(Canvas canvas, Size size) => effect.bake(canvas, size);

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.effect != effect;
}

// ─── Polaroid painter ──────────────────────────────────────────────────────

class _PolaroidPainter extends CustomPainter {
  final String? caption;
  _PolaroidPainter(this.caption);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final side = w * 0.045; // боковые/верхняя рамка
    final bot = w * 0.145; // нижняя рамка — толще (поляроид)

    final white = Paint()..color = Colors.white;

    // Белые рамки, перекрывающие края фото
    canvas.drawRect(Rect.fromLTWH(0, 0, w, side), white); // top
    canvas.drawRect(Rect.fromLTWH(0, 0, side, h), white); // left
    canvas.drawRect(Rect.fromLTWH(w - side, 0, side, h), white); // right
    canvas.drawRect(Rect.fromLTWH(0, h - bot, w, bot), white); // bottom

    // Лёгкая внутренняя тень на краях фото-области
    _innerShadow(canvas, Rect.fromLTWH(side, side, w - side * 2, h - side - bot));

    // Подпись внизу (если есть)
    if (caption != null && caption!.isNotEmpty) {
      _drawCaption(canvas, w, h, bot, caption!);
    }
  }

  void _innerShadow(Canvas canvas, Rect photo) {
    const a = 0.22;
    const sw = 14.0; // shadow width px

    // Тень нависает на фото со стороны рамки
    final top = Rect.fromLTWH(photo.left, photo.top, photo.width, sw);
    canvas.drawRect(top,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: a), Colors.transparent],
          ).createShader(top));

    final left = Rect.fromLTWH(photo.left, photo.top, sw, photo.height);
    canvas.drawRect(left,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.black.withValues(alpha: a), Colors.transparent],
          ).createShader(left));

    final right = Rect.fromLTWH(
        photo.right - sw, photo.top, sw, photo.height);
    canvas.drawRect(right,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [Colors.black.withValues(alpha: a), Colors.transparent],
          ).createShader(right));

    final bottom =
        Rect.fromLTWH(photo.left, photo.bottom - sw, photo.width, sw);
    canvas.drawRect(bottom,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: a), Colors.transparent],
          ).createShader(bottom));
  }

  void _drawCaption(Canvas canvas, double w, double h, double bot, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF555555),
          fontSize: 13,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w * 0.85);
    // Центрируем в нижней белой области
    tp.paint(
      canvas,
      Offset((w - tp.width) / 2, h - bot * 0.62),
    );
  }

  @override
  bool shouldRepaint(covariant _PolaroidPainter old) =>
      old.caption != caption;
}

// ─── Film Strip painter ────────────────────────────────────────────────────

class _FilmStripPainter extends CustomPainter {
  final String filmLabel;
  final int frameNumber;
  _FilmStripPainter(this.filmLabel, this.frameNumber);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bandH = h * 0.095; // высота верхней/нижней полосы
    final sideW = w * 0.018; // боковые полоски

    const filmDark = Color(0xFF1A1A1A);
    const filmMid = Color(0xFF2A2A2A);
    final darkPaint = Paint()..color = filmDark;
    final midPaint = Paint()..color = filmMid;

    // Тёмные полосы сверху и снизу
    canvas.drawRect(Rect.fromLTWH(0, 0, w, bandH), darkPaint);
    canvas.drawRect(Rect.fromLTWH(0, h - bandH, w, bandH), darkPaint);

    // Тонкие боковые полоски (даёт ощущение плёнки)
    canvas.drawRect(Rect.fromLTWH(0, bandH, sideW, h - bandH * 2), midPaint);
    canvas.drawRect(
        Rect.fromLTWH(w - sideW, bandH, sideW, h - bandH * 2), midPaint);

    // Перфорации (прямоугольники с закруглёнными углами)
    _drawPerforations(canvas, w, bandH, top: true);
    _drawPerforations(canvas, w, bandH, top: false, bottomY: h - bandH);

    // Текст в нижней полосе
    _drawFilmLabel(canvas, w, h, bandH, filmLabel, frameNumber);
  }

  void _drawPerforations(
    Canvas canvas,
    double w,
    double bandH, {
    required bool top,
    double bottomY = 0,
  }) {
    const perfCount = 8;
    final perfW = w * 0.048;
    final perfH = bandH * 0.52;
    final spacing = w / perfCount;
    final y = top
        ? (bandH - perfH) / 2
        : bottomY + (bandH - perfH) / 2;
    final perfPaint = Paint()..color = const Color(0xFF3D3D3D);
    final holePaint = Paint()..color = const Color(0xFF0D0D0D);

    for (var i = 0; i < perfCount; i++) {
      final x = spacing * i + (spacing - perfW) / 2;
      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, perfW, perfH),
        const Radius.circular(2),
      );
      canvas.drawRRect(rr, perfPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 1.5, y + 1.5, perfW - 3, perfH - 3),
          const Radius.circular(1.5),
        ),
        holePaint,
      );
    }
  }

  void _drawFilmLabel(
    Canvas canvas,
    double w,
    double h,
    double bandH,
    String label,
    int frameNum,
  ) {
    final y = h - bandH * 0.68;
    const style = TextStyle(
      color: Color(0xFFCC8800),
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
    );

    // Название плёнки слева
    (TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
    )..layout())
        .paint(canvas, Offset(w * 0.04, y));

    // Номер кадра справа
    final numTp = TextPainter(
      text: TextSpan(text: '↑$frameNum', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    numTp.paint(canvas, Offset(w - numTp.width - w * 0.04, y));
  }

  @override
  bool shouldRepaint(covariant _FilmStripPainter old) =>
      old.filmLabel != filmLabel || old.frameNumber != frameNumber;
}

// ─── Disposable Camera painter ─────────────────────────────────────────────

class _DisposablePainter extends CustomPainter {
  _DisposablePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Засветка от вспышки — тёплый блик в верхнем правом углу
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topRight,
          radius: 0.7,
          colors: [
            const Color(0xFFFFEEAA).withValues(alpha: 0.50),
            const Color(0xFFFFDD88).withValues(alpha: 0.18),
            Colors.transparent,
          ],
          stops: const [0.0, 0.22, 0.55],
        ).createShader(Offset.zero & size),
    );

    // Виньетка дешёвой оптики — сильнее по углам
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: 1.0,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.38),
          ],
          stops: const [0.55, 1.0],
        ).createShader(Offset.zero & size),
    );

    // Датамп — DD/MM/YY в правом нижнем углу (оранжевый на тёмном фоне)
    final now = DateTime.now();
    final dateStr =
        '${_p2(now.day)}/${_p2(now.month)}/${now.year % 100}';
    _drawDateStamp(canvas, w, h, dateStr);
  }

  void _drawDateStamp(Canvas canvas, double w, double h, String date) {
    const style = TextStyle(
      color: Color(0xFFFF8C00),
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      fontFamily: 'monospace',
    );
    final tp = TextPainter(
      text: TextSpan(text: date, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final pad = 10.0;
    final bgRect = Rect.fromLTWH(
      w - tp.width - pad * 3,
      h - tp.height - pad * 2.5,
      tp.width + pad * 2,
      tp.height + pad * 1.2,
    );
    canvas.drawRect(
        bgRect, Paint()..color = Colors.black.withValues(alpha: 0.55));
    tp.paint(canvas, Offset(bgRect.left + pad, bgRect.top + pad * 0.6));
  }

  String _p2(int n) => n.toString().padLeft(2, '0');

  @override
  bool shouldRepaint(covariant _DisposablePainter old) => false;
}

// ─── Scrapbook Frame painter ───────────────────────────────────────────────

class _ScrapbookPainter extends CustomPainter {
  _ScrapbookPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Кремовая рамка — как фотобумага в альбоме
    const cream = Color(0xFFFFF4E6);
    final border = w * 0.042;
    final white = Paint()..color = cream;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, border), white);
    canvas.drawRect(Rect.fromLTWH(0, 0, border, h), white);
    canvas.drawRect(Rect.fromLTWH(w - border, 0, border, h), white);
    canvas.drawRect(Rect.fromLTWH(0, h - border, w, border), white);

    // Тень — фото как будто наклеено поверх страницы
    _drawDropShadow(canvas, w, h, border);

    // Кусочки скотча по двум углам (верхний левый + нижний правый)
    _drawTapeCorner(canvas, w, h, topLeft: true);
    _drawTapeCorner(canvas, w, h, topLeft: false);
  }

  void _drawDropShadow(Canvas canvas, double w, double h, double border) {
    const sw = 12.0;
    const a = 0.20;
    // Правый край — тень
    final r = Rect.fromLTWH(w - border - sw, border, sw, h - border * 2);
    canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.transparent, Colors.black.withValues(alpha: a)],
          ).createShader(r));
    // Нижний край — тень
    final b = Rect.fromLTWH(border, h - border - sw, w - border * 2, sw);
    canvas.drawRect(
        b,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: a)],
          ).createShader(b));
  }

  void _drawTapeCorner(Canvas canvas, double w, double h,
      {required bool topLeft}) {
    final tapeW = w * 0.18;
    final tapeH = h * 0.035;
    const tapeColor = Color(0xFFFFEE99);
    const angle = math.pi / 5; // ~36°

    canvas.save();
    if (topLeft) {
      canvas.translate(w * 0.07, h * 0.07);
      canvas.rotate(-angle);
    } else {
      canvas.translate(w * 0.93, h * 0.93);
      canvas.rotate(angle);
    }
    canvas.translate(-tapeW / 2, -tapeH / 2);

    // Основной цвет скотча
    canvas.drawRect(
      Rect.fromLTWH(0, 0, tapeW, tapeH),
      Paint()..color = tapeColor.withValues(alpha: 0.72),
    );
    // Слабые горизонтальные линии — текстура скотча
    for (double ly = tapeH * 0.25; ly < tapeH; ly += tapeH * 0.5) {
      canvas.drawLine(
        Offset(0, ly),
        Offset(tapeW, ly),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.30)
          ..strokeWidth = 0.8,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScrapbookPainter old) => false;
}

// ─── Tape painter (standalone tape strips) ─────────────────────────────────

class _TapePainter extends CustomPainter {
  _TapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Горизонтальная полоска скотча сверху по центру
    _drawStrip(canvas, w * 0.5, h * 0.04, w * 0.32, h * 0.04, 0, size);

    // Диагональная полоска в нижнем левом углу
    _drawStrip(canvas, w * 0.2, h * 0.88, w * 0.25, h * 0.038,
        -math.pi / 8, size);
  }

  void _drawStrip(Canvas canvas, double cx, double cy, double tw, double th,
      double angle, Size size) {
    const tapeColor = Color(0xFFFFEE99);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-tw / 2, -th / 2);
    // Тело скотча
    canvas.drawRect(
      Rect.fromLTWH(0, 0, tw, th),
      Paint()..color = tapeColor.withValues(alpha: 0.65),
    );
    // Текстура (слабые горизонтальные штрихи)
    for (double ly = th * 0.3; ly < th; ly += th * 0.4) {
      canvas.drawLine(
        Offset(0, ly),
        Offset(tw, ly),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..strokeWidth = 0.7,
      );
    }
    // Лёгкая тень под скотчем
    canvas.drawRect(
      Rect.fromLTWH(2, th, tw - 2, 3),
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TapePainter old) => false;
}
