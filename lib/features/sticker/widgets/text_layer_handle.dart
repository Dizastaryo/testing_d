import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/design.dart';
import '../models/text_layer.dart';
import '../providers/sticker_editor_provider.dart';

/// Виджет одного текстового слоя на холсте.
///
/// Поддерживает: drag, pinch-to-zoom, rotation (через [GestureDetector.onScale*]),
/// tap для перехода в режим редактирования.
class TextLayerHandle extends ConsumerStatefulWidget {
  final TextLayer layer;
  final Size canvasSize;
  final bool isActive;
  final void Function(TextLayer layer)? onEditText;

  const TextLayerHandle({
    super.key,
    required this.layer,
    required this.canvasSize,
    required this.isActive,
    this.onEditText,
  });

  @override
  ConsumerState<TextLayerHandle> createState() => _TextLayerHandleState();
}

class _TextLayerHandleState extends ConsumerState<TextLayerHandle> {
  // Значения предыдущего фрейма жеста (для вычисления дельт).
  double _lastScale = 1.0;
  double _lastRotation = 0.0;

  // Суммарное смещение за жест — для определения «это был тап».
  double _totalDrift = 0.0;

  void _onScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
    _lastRotation = 0.0;
    _totalDrift = 0.0;

    // При начале жеста делаем слой активным.
    ref.read(stickerEditorProvider.notifier).setActive(widget.layer.id);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _totalDrift += details.focalPointDelta.distance;

    final scaleFactor = details.scale / _lastScale;
    final rotationDelta = details.rotation - _lastRotation;

    ref.read(stickerEditorProvider.notifier).updateLayerTransform(
      widget.layer.id,
      positionDelta: Offset(
        details.focalPointDelta.dx / widget.canvasSize.width,
        details.focalPointDelta.dy / widget.canvasSize.height,
      ),
      scaleFactor: scaleFactor,
      rotationDelta: rotationDelta,
    );

    _lastScale = details.scale;
    _lastRotation = details.rotation;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final isTap = _totalDrift < 8.0 &&
        (_lastScale - 1.0).abs() < 0.05 &&
        _lastRotation.abs() < 0.05;

    if (isTap) {
      // Тап → открываем редактирование текста.
      widget.onEditText?.call(widget.layer);
    } else {
      // Реальный жест трансформации — фиксируем в историю.
      ref.read(stickerEditorProvider.notifier).commitGesture();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final cx = layer.position.dx * widget.canvasSize.width;
    final cy = layer.position.dy * widget.canvasSize.height;

    return Positioned(
      left: cx,
      top: cy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Transform.rotate(
            angle: layer.rotation,
            child: Transform.scale(
              scale: layer.scale,
              child: Opacity(
                opacity: layer.opacity.clamp(0.0, 1.0),
                child: _TextContent(
                  layer: layer,
                  isActive: widget.isActive,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Рендер текста ────────────────────────────────────────────────

class _TextContent extends StatelessWidget {
  final TextLayer layer;
  final bool isActive;

  const _TextContent({required this.layer, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: isActive
          ? BoxDecoration(
              border: Border.all(color: SeeUColors.accent, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Обводка (отдельный Text с stroke Paint).
          if (layer.hasStroke)
            Text(
              layer.text,
              textAlign: layer.alignment,
              style: _buildStyle(layer).copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = layer.strokeWidth * 2
                  ..strokeJoin = StrokeJoin.round
                  ..color = layer.strokeColor,
                // shadows не применяем к обводке
                shadows: null,
              ),
            ),

          // Основной текст с заливкой.
          Text(
            layer.text,
            textAlign: layer.alignment,
            style: _buildStyle(layer),
          ),
        ],
      ),
    );
  }

  TextStyle _buildStyle(TextLayer layer) {
    final base = TextStyle(
      fontSize: layer.fontSize,
      color: layer.color,
      fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
      fontWeight: layer.bold ? FontWeight.w900 : FontWeight.w400,
      decoration: layer.underline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: layer.color,
      shadows: layer.hasShadow
          ? [
              Shadow(
                color: layer.shadowColor,
                offset: layer.shadowOffset,
                blurRadius: layer.shadowBlur,
              ),
            ]
          : null,
    );

    // Empty fontFamily = emoji layer — use system default so emoji glyphs render.
    // Wrapping with GoogleFonts overrides fontFamily and breaks emoji fallback.
    return switch (layer.fontFamily) {
      ''           => base,
      'Pacifico'   => GoogleFonts.pacifico(textStyle: base),
      'Bebas Neue' => GoogleFonts.bebasNeue(textStyle: base),
      'Oswald'     => GoogleFonts.oswald(textStyle: base),
      'Caveat'     => GoogleFonts.caveat(textStyle: base),
      'Montserrat' => GoogleFonts.montserrat(textStyle: base),
      _            => GoogleFonts.roboto(textStyle: base),
    };
  }
}
