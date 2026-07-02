import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ─── Sealed class ──────────────────────────────────────────────────────────

/// Overlay-эффект поверх camera preview. В отличие от [FilterState] (color
/// matrix), это canvas-слой с геометрией — царапины, пылинки, засветки плёнки.
/// Bake-метод позволяет запечь эффект в финальное фото.
sealed class OverlayEffect {
  const OverlayEffect();

  /// Рисует эффект прямо на [canvas] при bake финального фото.
  /// [animValue] фиксирован на 0.6 — средняя точка анимации.
  void bake(Canvas canvas, Size size);
}

class DustScratchesEffect extends OverlayEffect {
  final double intensity; // 0..1

  const DustScratchesEffect({this.intensity = 0.5});

  @override
  void bake(Canvas canvas, Size size) =>
      _DustScratchesPainter(intensity, 7).paint(canvas, size);
}

class LightLeakEffect extends OverlayEffect {
  final LightLeakStyle style;
  final double intensity; // 0..1

  const LightLeakEffect({
    this.style = LightLeakStyle.topOrange,
    this.intensity = 0.65,
  });

  @override
  void bake(Canvas canvas, Size size) =>
      _LightLeakPainter(style, intensity, 0.6).paint(canvas, size);
}

enum LightLeakStyle {
  topOrange, // тёплый оранжево-жёлтый из левого верхнего угла
  topCool,   // холодный синий из правого верхнего угла
  bottomWarm, // розово-фиолетовый снизу по центру
}

/// VHS-эффект: scanlines + noise band + chromatic aberration + HUD (● REC).
class VHSEffect extends OverlayEffect {
  final double intensity; // 0..1

  const VHSEffect({this.intensity = 0.70});

  @override
  void bake(Canvas canvas, Size size) => _VHSPainter(
        intensity: intensity,
        bandY: 0.40,
        recVisible: true,
        noiseSeed: 42,
      ).paint(canvas, size);
}

/// Текстура бумаги — плотное фиброволокно + горизонтальные следы пресса.
/// Статичный эффект (фиксированный seed), не анимируется.
class PaperTextureEffect extends OverlayEffect {
  final double intensity; // 0..1

  const PaperTextureEffect({this.intensity = 0.45});

  @override
  void bake(Canvas canvas, Size size) =>
      _PaperTexturePainter(intensity).paint(canvas, size);
}

// ─── EffectOverlay widget ──────────────────────────────────────────────────

/// Рендерит [OverlayEffect] поверх camera preview.
/// Каждый тип эффекта управляет своей анимацией внутри.
class EffectOverlay extends StatefulWidget {
  final OverlayEffect effect;

  const EffectOverlay({super.key, required this.effect});

  @override
  State<EffectOverlay> createState() => _EffectOverlayState();
}

class _EffectOverlayState extends State<EffectOverlay>
    with TickerProviderStateMixin {
  // Dust: медленный seed-ticker (~3 fps) — царапины и пыль "дрожат"
  Ticker? _dustTicker;
  int _dustSeed = 0;
  Duration _lastDust = Duration.zero;
  static const _kDustInterval = Duration(milliseconds: 300);

  // Light leak: плавная пульсация opacity
  late AnimationController _leakCtrl;
  late Animation<double> _leakAnim;

  @override
  void initState() {
    super.initState();
    _leakCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _leakAnim = Tween<double>(begin: 0.30, end: 1.0).animate(
      CurvedAnimation(parent: _leakCtrl, curve: Curves.easeInOut),
    );
    _syncEffect(null);
  }

  @override
  void didUpdateWidget(EffectOverlay old) {
    super.didUpdateWidget(old);
    if (old.effect.runtimeType != widget.effect.runtimeType) {
      _syncEffect(old.effect);
    }
  }

  void _syncEffect(OverlayEffect? old) {
    _dustTicker?.stop();
    _dustTicker?.dispose();
    _dustTicker = null;
    _leakCtrl.stop();

    switch (widget.effect) {
      case DustScratchesEffect():
        _dustTicker = createTicker((elapsed) {
          if (elapsed - _lastDust >= _kDustInterval) {
            _lastDust = elapsed;
            setState(() => _dustSeed++);
          }
        })
          ..start();
      case LightLeakEffect():
        _leakCtrl.repeat(reverse: true);
      case VHSEffect():
        break; // _VHSOverlay управляет своими анимациями самостоятельно
      case PaperTextureEffect():
        break; // статичный эффект, анимация не нужна
    }
  }

  @override
  void dispose() {
    _dustTicker?.stop();
    _dustTicker?.dispose();
    _leakCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.effect) {
      DustScratchesEffect(intensity: final i) => RepaintBoundary(
          child: CustomPaint(
            painter: _DustScratchesPainter(i, _dustSeed),
          ),
        ),
      LightLeakEffect(style: final s, intensity: final i) => AnimatedBuilder(
          animation: _leakAnim,
          builder: (_, __) => CustomPaint(
            painter: _LightLeakPainter(s, i, _leakAnim.value),
          ),
        ),
      VHSEffect(intensity: final i) => _VHSOverlay(intensity: i),
      PaperTextureEffect(intensity: final i) => CustomPaint(
          painter: _PaperTexturePainter(i),
        ),
    };
  }
}

// ─── Dust & Scratches painter ──────────────────────────────────────────────

/// Царапины (тонкие вертикальные линии) + пылинки (точки).
/// Seed меняется ~3 fps → лёгкий мерцающий эффект без тяжёлой анимации.
class _DustScratchesPainter extends CustomPainter {
  final double intensity; // 0..1
  final int seed;

  _DustScratchesPainter(this.intensity, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final w = size.width;
    final h = size.height;

    // Царапины — тонкие вертикальные/слегка наклонные линии
    final scratchCount = (intensity * 14).round().clamp(1, 25);
    for (var i = 0; i < scratchCount; i++) {
      final x = rng.nextDouble() * w;
      final startY = rng.nextDouble() * h * 0.65;
      final len = h * (0.06 + rng.nextDouble() * 0.35);
      final alpha = (intensity * (0.20 + rng.nextDouble() * 0.55)).clamp(0.0, 0.90);
      // Лёгкий наклон ±1.5px за длину царапины
      final drift = rng.nextDouble() * 3.0 - 1.5;
      canvas.drawLine(
        Offset(x, startY),
        Offset(x + drift, startY + len),
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..strokeWidth = rng.nextDouble() < 0.75 ? 0.5 : 1.0,
      );
    }

    // Пылинки — маленькие круги по всему кадру
    final dustCount = (intensity * 70).round().clamp(5, 130);
    for (var i = 0; i < dustCount; i++) {
      final x = rng.nextDouble() * w;
      final y = rng.nextDouble() * h;
      final r = 0.5 + rng.nextDouble() * 1.8;
      final alpha = (intensity * (0.12 + rng.nextDouble() * 0.55)).clamp(0.0, 0.85);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DustScratchesPainter old) =>
      old.intensity != intensity || old.seed != seed;
}

// ─── Light Leak painter ────────────────────────────────────────────────────

/// Засветка плёнки — радиальный градиент из угла/края кадра.
/// [animValue] (0.30..1.0) пульсирует через AnimationController в [EffectOverlay].
class _LightLeakPainter extends CustomPainter {
  final LightLeakStyle style;
  final double intensity;
  final double animValue;

  _LightLeakPainter(this.style, this.intensity, this.animValue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    switch (style) {
      // Тёплый оранжево-жёлтый из левого верхнего угла — как прямое солнце
      case LightLeakStyle.topOrange:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: Alignment.topLeft,
              radius: 1.05,
              colors: [
                const Color(0xFFFF6B35).withValues(alpha: intensity * animValue * 0.78),
                const Color(0xFFFFD700).withValues(alpha: intensity * animValue * 0.38),
                Colors.transparent,
              ],
              stops: const [0.0, 0.30, 0.65],
            ).createShader(rect),
        );

      // Холодный синий/фиолетовый из правого верхнего угла
      case LightLeakStyle.topCool:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: Alignment.topRight,
              radius: 1.05,
              colors: [
                const Color(0xFF00D4FF).withValues(alpha: intensity * animValue * 0.72),
                const Color(0xFF7B61FF).withValues(alpha: intensity * animValue * 0.38),
                Colors.transparent,
              ],
              stops: const [0.0, 0.28, 0.62],
            ).createShader(rect),
        );

      // Тёплый розово-фиолетовый снизу — как засветка снизу плёнки
      case LightLeakStyle.bottomWarm:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: Alignment.bottomCenter,
              radius: 0.95,
              colors: [
                const Color(0xFFFF4088).withValues(alpha: intensity * animValue * 0.72),
                const Color(0xFFFF8C42).withValues(alpha: intensity * animValue * 0.40),
                Colors.transparent,
              ],
              stops: const [0.0, 0.32, 0.68],
            ).createShader(rect),
        );
    }
  }

  @override
  bool shouldRepaint(covariant _LightLeakPainter old) =>
      old.style != style ||
      old.intensity != intensity ||
      old.animValue != animValue;
}

// ─── VHS overlay ───────────────────────────────────────────────────────────

/// StatefulWidget с тремя анимациями: band scroll, REC blink, noise seed.
/// Управляет ими самостоятельно, не через _EffectOverlayState.
class _VHSOverlay extends StatefulWidget {
  final double intensity;

  const _VHSOverlay({required this.intensity});

  @override
  State<_VHSOverlay> createState() => _VHSOverlayState();
}

class _VHSOverlayState extends State<_VHSOverlay>
    with TickerProviderStateMixin {
  // Noise band плавно ползёт сверху вниз (6 сек → один проход)
  late AnimationController _bandCtrl;
  // REC-точка мигает каждые ~900 мс
  late AnimationController _blinkCtrl;
  // Noise band меняет seed ~8 fps
  Ticker? _noiseTicker;
  int _noiseSeed = 0;
  Duration _lastNoise = Duration.zero;
  static const _kNoiseInterval = Duration(milliseconds: 125);

  @override
  void initState() {
    super.initState();
    _bandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _noiseTicker = createTicker((elapsed) {
      if (elapsed - _lastNoise >= _kNoiseInterval) {
        _lastNoise = elapsed;
        setState(() => _noiseSeed++);
      }
    })..start();
  }

  @override
  void dispose() {
    _bandCtrl.dispose();
    _blinkCtrl.dispose();
    _noiseTicker?.stop();
    _noiseTicker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_bandCtrl, _blinkCtrl]),
      builder: (_, __) => CustomPaint(
        painter: _VHSPainter(
          intensity: widget.intensity,
          bandY: _bandCtrl.value,
          recVisible: _blinkCtrl.value < 0.5,
          noiseSeed: _noiseSeed,
        ),
      ),
    );
  }
}

class _VHSPainter extends CustomPainter {
  final double intensity;
  final double bandY; // 0..1 — позиция шумовой полосы (сверху вниз)
  final bool recVisible;
  final int noiseSeed;

  const _VHSPainter({
    required this.intensity,
    required this.bandY,
    required this.recVisible,
    required this.noiseSeed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawScanlines(canvas, size);
    _drawNoiseBand(canvas, size);
    _drawChromaticAberration(canvas, size);
    _drawHUD(canvas, size);
  }

  // Горизонтальные полосы каждые 4px — имитация строчной развёртки CRT
  void _drawScanlines(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: intensity * 0.13);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  // Горизонтальная полоса цветного шума (4.5% высоты) ползёт сверху вниз
  void _drawNoiseBand(Canvas canvas, Size size) {
    final bandH = size.height * 0.045;
    final topY = bandY * (size.height + bandH) - bandH;
    if (topY > size.height || topY + bandH < 0) return;

    final rng = math.Random(noiseSeed);
    final p = Paint();
    for (double x = 0; x < size.width; x += 6) {
      final isColor = rng.nextDouble() < 0.30;
      p.color = isColor
          ? Color.fromARGB(
              (intensity * 185).toInt(),
              rng.nextInt(256),
              rng.nextInt(256),
              rng.nextInt(256),
            )
          : Colors.white.withValues(
              alpha: intensity * rng.nextDouble() * 0.90);
      canvas.drawRect(Rect.fromLTWH(x, topY, 6, bandH), p);
    }
  }

  // Красная бахрома слева, синяя справа — аналог хроматической аберрации линзы
  void _drawChromaticAberration(Canvas canvas, Size size) {
    final edgeW = size.width * 0.07;
    final a = intensity * 0.09;
    final rect = Offset.zero & size;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, edgeW, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFFFF2222).withValues(alpha: a),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - edgeW, 0, edgeW, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            const Color(0xFF2222FF).withValues(alpha: a),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  // HUD: мигающий ● REC слева + таймер справа
  void _drawHUD(Canvas canvas, Size size) {
    const txtStyle = TextStyle(
      color: Colors.white,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
    );

    if (recVisible) {
      canvas.drawCircle(
        const Offset(18, 22),
        5,
        Paint()..color = const Color(0xFFFF2222),
      );
    }
    _paint(canvas, 'REC', const Offset(28, 15), txtStyle);

    final now = DateTime.now();
    final ts =
        '${_p2(now.hour)}:${_p2(now.minute)}:${_p2(now.second)}';
    final tp = TextPainter(
      text: TextSpan(text: ts, style: txtStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 14, 15));
  }

  void _paint(Canvas canvas, String text, Offset offset, TextStyle style) {
    (TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout())
        .paint(canvas, offset);
  }

  String _p2(int n) => n.toString().padLeft(2, '0');

  @override
  bool shouldRepaint(covariant _VHSPainter old) =>
      old.intensity != intensity ||
      old.bandY != bandY ||
      old.recVisible != recVisible ||
      old.noiseSeed != noiseSeed;
}

// ─── Paper Texture painter ─────────────────────────────────────────────────

/// Текстура фотобумаги: тёплый тонкий тинт + плотное фиброволокно +
/// горизонтальные следы пресса. Фиксированный seed — бумага не движется.
class _PaperTexturePainter extends CustomPainter {
  final double intensity; // 0..1

  _PaperTexturePainter(this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7890); // фиксированный seed — статичная текстура
    final w = size.width;
    final h = size.height;

    // Тёплый базовый тинт — имитация пожелтевшей фотобумаги
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color =
            const Color(0xFFFFF8E7).withValues(alpha: intensity * 0.13),
    );

    // Фиброволокно — плотные мелкие точки в тёплых тонах
    final fiberCount = (intensity * 4000).round().clamp(600, 8000);
    final fiberPaint = Paint();
    for (var i = 0; i < fiberCount; i++) {
      final x = rng.nextDouble() * w;
      final y = rng.nextDouble() * h;
      final r = 0.2 + rng.nextDouble() * 0.55;
      final isWarm = rng.nextDouble() < 0.65;
      fiberPaint.color = (isWarm
              ? const Color(0xFFD4A76A) // тёплый песочный
              : const Color(0xFF8B7355)) // тёмно-коричневый
          .withValues(
              alpha: intensity * (0.04 + rng.nextDouble() * 0.11));
      canvas.drawCircle(Offset(x, y), r, fiberPaint);
    }

    // Горизонтальные следы пресса бумагоделательной машины — очень тонкие
    final lineCount = (intensity * 14).round().clamp(2, 22);
    final linePaint = Paint()..strokeWidth = 0.3;
    for (var i = 0; i < lineCount; i++) {
      final y = rng.nextDouble() * h;
      final startX = rng.nextDouble() * w * 0.25;
      final endX = w * (0.65 + rng.nextDouble() * 0.35);
      linePaint.color = const Color(0xFFC4A882)
          .withValues(
              alpha: intensity * (0.03 + rng.nextDouble() * 0.06));
      canvas.drawLine(Offset(startX, y), Offset(endX, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperTexturePainter old) =>
      old.intensity != intensity;
}
