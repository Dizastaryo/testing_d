import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/sticker_provider.dart';

/// Экран ручной доработки фона стикера.
///
/// Показывает изображение с удалённым фоном (прозрачность = шахматка).
/// Пользователь рисует пальцем — выбранная кисть стирает пиксели (erase)
/// или восстанавливает их (restore). На выходе — URL загруженного PNG.
class StickerTouchupScreen extends ConsumerStatefulWidget {
  /// Абсолютный URL фонового изображения (PNG с прозрачностью).
  final String imageUrl;

  const StickerTouchupScreen({super.key, required this.imageUrl});

  @override
  ConsumerState<StickerTouchupScreen> createState() =>
      _StickerTouchupScreenState();
}

enum _BrushMode { erase, restore }

class _StickerTouchupScreenState extends ConsumerState<StickerTouchupScreen> {
  ui.Image? _uiImage;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  _BrushMode _mode = _BrushMode.erase;
  double _brushSize = 24.0;

  // Strokes in IMAGE pixel coordinates.
  final List<List<Offset>> _eraseStrokes = [];
  final List<List<Offset>> _restoreStrokes = [];
  // Chronological order for proper undo support.
  final List<_BrushMode> _strokeOrder = [];
  // Current in-progress stroke
  List<Offset>? _currentStroke;
  _BrushMode? _currentStrokeMode;

  // Canvas render size (set in LayoutBuilder)
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _uiImage?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final completer = Completer<ui.Image>();
      final stream = NetworkImage(widget.imageUrl).resolve(
        const ImageConfiguration(),
      );
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (e, st) {
          completer.completeError(e, st);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final image = await completer.future;

      if (mounted) {
        setState(() {
          _uiImage = image;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ── Gesture handling ─────────────────────────────────────────────

  Offset _toImageCoords(Offset local) {
    if (_uiImage == null || _canvasSize == Size.zero) return Offset.zero;
    final imgW = _uiImage!.width.toDouble();
    final imgH = _uiImage!.height.toDouble();
    // BoxFit.contain scale
    final scale = math.min(
      _canvasSize.width / imgW,
      _canvasSize.height / imgH,
    );
    final renderedW = imgW * scale;
    final renderedH = imgH * scale;
    final ox = (_canvasSize.width - renderedW) / 2;
    final oy = (_canvasSize.height - renderedH) / 2;
    return Offset(
      ((local.dx - ox) / scale).clamp(0.0, imgW),
      ((local.dy - oy) / scale).clamp(0.0, imgH),
    );
  }

  void _onPanStart(DragStartDetails d) {
    _currentStroke = [_toImageCoords(d.localPosition)];
    _currentStrokeMode = _mode;
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_currentStroke == null) return;
    _currentStroke!.add(_toImageCoords(d.localPosition));
    setState(() {});
  }

  void _onPanEnd(DragEndDetails _) {
    if (_currentStroke == null) return;
    final mode = _currentStrokeMode!;
    final points = List<Offset>.from(_currentStroke!);
    if (mode == _BrushMode.erase) {
      _eraseStrokes.add(points);
    } else {
      _restoreStrokes.add(points);
    }
    _strokeOrder.add(mode);
    _currentStroke = null;
    _currentStrokeMode = null;
    setState(() {});
  }

  // ── Undo ─────────────────────────────────────────────────────────

  void _undo() {
    if (_strokeOrder.isEmpty) return;
    setState(() {
      final lastMode = _strokeOrder.removeLast();
      if (lastMode == _BrushMode.erase) {
        _eraseStrokes.removeLast();
      } else {
        _restoreStrokes.removeLast();
      }
    });
  }

  bool get _canUndo => _strokeOrder.isNotEmpty;

  // ── Export & save ─────────────────────────────────────────────────

  Future<void> _save() async {
    if (_uiImage == null) return;
    setState(() => _saving = true);
    try {
      final imgW = _uiImage!.width;
      final imgH = _uiImage!.height;
      final rect = Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble());

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, rect);

      // saveLayer is required so BlendMode.clear correctly erases image pixels.
      canvas.saveLayer(rect, Paint());

      canvas.drawImage(_uiImage!, Offset.zero, Paint());

      // Erase strokes: punch transparent holes.
      if (_eraseStrokes.isNotEmpty) {
        final erasePaint = Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.fill;
        for (final stroke in _eraseStrokes) {
          for (final p in stroke) {
            canvas.drawCircle(p, _brushSize / 2, erasePaint);
          }
        }
      }

      canvas.restore(); // flatten: image with erased areas is now on canvas

      // Restore strokes: draw original pixels back in clipped region.
      if (_restoreStrokes.isNotEmpty) {
        final clipPath = Path();
        for (final stroke in _restoreStrokes) {
          if (stroke.isEmpty) continue;
          for (final p in stroke) {
            clipPath.addOval(Rect.fromCircle(center: p, radius: _brushSize / 2));
          }
        }
        canvas.save();
        canvas.clipPath(clipPath);
        canvas.drawImage(_uiImage!, Offset.zero, Paint());
        canvas.restore();
      }

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(imgW, imgH);
      final byteData =
          await finalImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Не удалось экспортировать');

      final pngBytes = byteData.buffer.asUint8List();
      final url =
          await ref.read(stickerListProvider.notifier).uploadMedia(pngBytes);

      if (mounted) Navigator.of(context).pop(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(c),
            // Canvas
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: SeeUColors.accent))
                  : _loadError != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsRegular.warningCircle,
                                  color: Colors.red, size: 40),
                              const SizedBox(height: 8),
                              Text('Ошибка загрузки',
                                  style: TextStyle(color: c.ink3)),
                              TextButton(
                                onPressed: _loadImage,
                                child: const Text('Повторить',
                                    style:
                                        TextStyle(color: SeeUColors.accent)),
                              ),
                            ],
                          ),
                        )
                      : LayoutBuilder(builder: (ctx, constraints) {
                          _canvasSize = Size(
                              constraints.maxWidth, constraints.maxHeight);
                          return GestureDetector(
                            onPanStart: _onPanStart,
                            onPanUpdate: _onPanUpdate,
                            onPanEnd: _onPanEnd,
                            child: CustomPaint(
                              size: _canvasSize,
                              painter: _TouchupPainter(
                                image: _uiImage!,
                                eraseStrokes: _eraseStrokes,
                                restoreStrokes: _restoreStrokes,
                                currentStroke: _currentStroke,
                                currentStrokeMode: _currentStrokeMode,
                                brushSize: _brushSize,
                              ),
                            ),
                          );
                        }),
            ),
            _buildToolbar(c),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _saving ? null : () => Navigator.of(context).pop(),
            child: const Icon(PhosphorIconsRegular.x,
                size: 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Text(
            'Подправить',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _canUndo && !_saving ? _undo : null,
            child: Icon(
              PhosphorIconsRegular.arrowCounterClockwise,
              size: 22,
              color: _canUndo && !_saving
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 20),
          _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: SeeUColors.accent, strokeWidth: 2))
              : GestureDetector(
                  onTap: _save,
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      borderRadius: BorderRadius.circular(SeeURadii.pill),
                    ),
                    child: const Center(
                      child: Text('Готово',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildToolbar(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode toggle
          Row(
            children: [
              Expanded(
                child: _ModeBtn(
                  icon: PhosphorIconsRegular.eraser,
                  label: 'Стереть',
                  active: _mode == _BrushMode.erase,
                  onTap: () => setState(() => _mode = _BrushMode.erase),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeBtn(
                  icon: PhosphorIconsRegular.pencil,
                  label: 'Восстановить',
                  active: _mode == _BrushMode.restore,
                  onTap: () => setState(() => _mode = _BrushMode.restore),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Brush size slider
          Row(
            children: [
              const Icon(PhosphorIconsRegular.dotOutline,
                  size: 14, color: Colors.white54),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: SeeUColors.accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: SeeUColors.accent.withValues(alpha: 0.2),
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _brushSize,
                    min: 8,
                    max: 80,
                    onChanged: (v) => setState(() => _brushSize = v),
                  ),
                ),
              ),
              const Icon(PhosphorIconsRegular.circle,
                  size: 22, color: Colors.white54),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Mode button ───────────────────────────────────────────────────

class _ModeBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 40,
        decoration: BoxDecoration(
          color: active
              ? SeeUColors.accent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(SeeURadii.small),
          border: Border.all(
            color: active
                ? SeeUColors.accent
                : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: active ? SeeUColors.accent : Colors.white60),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? SeeUColors.accent : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────

class _TouchupPainter extends CustomPainter {
  final ui.Image image;
  final List<List<Offset>> eraseStrokes;
  final List<List<Offset>> restoreStrokes;
  final List<Offset>? currentStroke;
  final _BrushMode? currentStrokeMode;
  final double brushSize;

  const _TouchupPainter({
    required this.image,
    required this.eraseStrokes,
    required this.restoreStrokes,
    required this.currentStroke,
    required this.currentStrokeMode,
    required this.brushSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final scale = math.min(size.width / imgW, size.height / imgH);
    final renderedW = imgW * scale;
    final renderedH = imgH * scale;
    final ox = (size.width - renderedW) / 2;
    final oy = (size.height - renderedH) / 2;

    // 1. Checkerboard background (indicates transparency).
    _drawCheckerboard(canvas, Rect.fromLTWH(ox, oy, renderedW, renderedH));

    // 2. Draw image + erasures in a saveLayer so BlendMode.clear works.
    canvas.save();
    canvas.translate(ox, oy);
    canvas.scale(scale);

    canvas.saveLayer(
        Rect.fromLTWH(0, 0, imgW, imgH), Paint());

    // Draw the original image.
    canvas.drawImage(image, Offset.zero, Paint());

    // Erase committed strokes.
    _applyStrokes(canvas, eraseStrokes, BlendMode.clear);

    // Current stroke (live preview).
    if (currentStroke != null &&
        currentStrokeMode == _BrushMode.erase) {
      _applyStroke(canvas, currentStroke!, BlendMode.clear);
    }

    canvas.restore(); // saveLayer

    // Restore strokes: draw original pixels back in clipped region.
    _applyRestoreStrokes(canvas, restoreStrokes);
    if (currentStroke != null &&
        currentStrokeMode == _BrushMode.restore) {
      _applyRestoreStroke(canvas, currentStroke!);
    }

    canvas.restore(); // translate+scale
  }

  void _applyStrokes(
      Canvas canvas, List<List<Offset>> strokes, BlendMode mode) {
    for (final stroke in strokes) {
      _applyStroke(canvas, stroke, mode);
    }
  }

  void _applyStroke(Canvas canvas, List<Offset> stroke, BlendMode mode) {
    if (stroke.isEmpty) return;
    final paint = Paint()
      ..blendMode = mode
      ..style = PaintingStyle.fill;

    // Draw filled circles along the path for smooth coverage.
    for (final p in stroke) {
      canvas.drawCircle(p, brushSize / 2, paint);
    }
  }

  void _applyRestoreStrokes(
      Canvas canvas, List<List<Offset>> strokes) {
    for (final stroke in strokes) {
      _applyRestoreStroke(canvas, stroke);
    }
  }

  void _applyRestoreStroke(Canvas canvas, List<Offset> stroke) {
    if (stroke.isEmpty) return;
    // Build clip path from circles around stroke points.
    final clipPath = Path();
    for (final p in stroke) {
      clipPath.addOval(
          Rect.fromCircle(center: p, radius: brushSize / 2));
    }
    canvas.save();
    canvas.clipPath(clipPath);
    canvas.drawImage(image, Offset.zero, Paint());
    canvas.restore();
  }

  void _drawCheckerboard(Canvas canvas, Rect rect) {
    const cellSize = 10.0;
    final paint1 = Paint()..color = const Color(0xFFCCCCCC);
    final paint2 = Paint()..color = const Color(0xFFFFFFFF);
    final cols = (rect.width / cellSize).ceil();
    final rows = (rect.height / cellSize).ceil();
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final isLight = (row + col) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left + col * cellSize,
            rect.top + row * cellSize,
            cellSize,
            cellSize,
          ),
          isLight ? paint1 : paint2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TouchupPainter old) => true;
}
