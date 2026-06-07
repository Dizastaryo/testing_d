import 'package:flutter/material.dart';

/// Список доступных шрифтов для стикеров.
/// Все шрифты подключены через google_fonts.
const List<String> kStickerFonts = [
  'Roboto',
  'Pacifico',
  'Bebas Neue',
  'Oswald',
  'Caveat',
  'Montserrat',
];

/// Один текстовый слой на холсте стикера.
@immutable
class TextLayer {
  final String id;
  final String text;

  /// Нормализованная позиция центра слоя (0.0–1.0 по X и Y).
  final Offset position;

  /// Масштаб поверх базового [fontSize].
  final double scale;

  /// Угол поворота в радианах.
  final double rotation;

  final String fontFamily;
  final double fontSize;
  final Color color;

  /// Прозрачность слоя целиком (0.0–1.0).
  final double opacity;

  final bool bold;
  final bool italic;
  final bool underline;
  final TextAlign alignment;

  final bool hasStroke;
  final Color strokeColor;
  final double strokeWidth;

  final bool hasShadow;
  final Color shadowColor;
  final Offset shadowOffset;
  final double shadowBlur;

  const TextLayer({
    required this.id,
    required this.text,
    this.position = const Offset(0.5, 0.5),
    this.scale = 1.0,
    this.rotation = 0.0,
    this.fontFamily = 'Roboto',
    this.fontSize = 32.0,
    this.color = Colors.white,
    this.opacity = 1.0,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.alignment = TextAlign.center,
    this.hasStroke = false,
    this.strokeColor = Colors.black,
    this.strokeWidth = 2.0,
    this.hasShadow = false,
    this.shadowColor = Colors.black54,
    this.shadowOffset = const Offset(2, 2),
    this.shadowBlur = 4.0,
  });

  /// Копирует слой, заменяя только переданные поля.
  /// [id] всегда сохраняется — используй [copyWithNewId] для дублирования.
  TextLayer copyWith({
    String? text,
    Offset? position,
    double? scale,
    double? rotation,
    String? fontFamily,
    double? fontSize,
    Color? color,
    double? opacity,
    bool? bold,
    bool? italic,
    bool? underline,
    TextAlign? alignment,
    bool? hasStroke,
    Color? strokeColor,
    double? strokeWidth,
    bool? hasShadow,
    Color? shadowColor,
    Offset? shadowOffset,
    double? shadowBlur,
  }) {
    return TextLayer(
      id: id,
      text: text ?? this.text,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      alignment: alignment ?? this.alignment,
      hasStroke: hasStroke ?? this.hasStroke,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      hasShadow: hasShadow ?? this.hasShadow,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      shadowBlur: shadowBlur ?? this.shadowBlur,
    );
  }

  /// Создаёт копию с новым [id] — для операции «Дублировать слой».
  TextLayer copyWithNewId(String newId, {Offset? position}) {
    return TextLayer(
      id: newId,
      text: text,
      position: position ?? this.position,
      scale: scale,
      rotation: rotation,
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
      opacity: opacity,
      bold: bold,
      italic: italic,
      underline: underline,
      alignment: alignment,
      hasStroke: hasStroke,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      hasShadow: hasShadow,
      shadowColor: shadowColor,
      shadowOffset: shadowOffset,
      shadowBlur: shadowBlur,
    );
  }
}
