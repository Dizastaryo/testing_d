import 'dart:convert';

import 'package:flutter/material.dart';

/// Шаблоны оформления карточки — точные значения из дизайна (Claude Design).
/// Общий источник для студии («Моя карточка»), ленты сканера и аудитории:
/// карточка человека рядом рисуется ровно тем оформлением, что он выбрал.
///
/// Каждый шаблон = фон (сплошной или градиент) + акцент (кольцо фото, подчёрк,
/// иконки) + мягкий radial-overlay + цветная тень + фон под фото.
class CardTemplate {
  final String id;
  final String label;

  /// Фон карточки: 1 цвет — сплошной, 2 — линейный градиент.
  final List<Color> bg;
  final Alignment bgBegin;
  final Alignment bgEnd;

  /// Акцент: кольцо вокруг фото, подчёркивание под ником, мета-иконки.
  final Color accent;

  /// Фон внутри круга фото (пока фото не загрузилось).
  final Color photoInner;

  /// Цвет тени карточки (в дизайне тень тонирована под фон).
  final Color shadow;

  /// Мягкое radial-свечение поверх фона (у «Нуара» его нет).
  final RadialGradient? overlay;

  /// true — тёмный текст (светлый шаблон «Бумага»).
  final bool darkText;

  const CardTemplate({
    required this.id,
    required this.label,
    required this.bg,
    required this.accent,
    required this.photoInner,
    required this.shadow,
    this.overlay,
    this.bgBegin = Alignment.topLeft,
    this.bgEnd = Alignment.bottomRight,
    this.darkText = false,
  });

  /// Цвет текста поверх карточки.
  Color get onColor => darkText ? const Color(0xFF161310) : Colors.white;

  /// Цвет вторичного текста (цитата) — в дизайне 84% прозрачности.
  Color get onColorSoft => onColor.withValues(alpha: 0.84);

  /// Декорация фона карточки (без overlay — он рисуется отдельным слоем).
  BoxDecoration decoration({double radius = 26}) => BoxDecoration(
        color: bg.length == 1 ? bg.first : null,
        gradient: bg.length > 1
            ? LinearGradient(colors: bg, begin: bgBegin, end: bgEnd)
            : null,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: shadow,
            blurRadius: 34,
            spreadRadius: -16,
            offset: const Offset(0, 16),
          ),
        ],
      );
}

/// 5 шаблонов. Значения — 1:1 из дизайна.
const List<CardTemplate> cardTemplates = [
  // Минимал — тёмно-графитовый + коралловое свечение из верхнего правого угла.
  CardTemplate(
    id: 'plain',
    label: 'Минимал',
    bg: [Color(0xFF111318)],
    accent: Color(0xFFFF5A3C),
    photoInner: Color(0xFF1B1E24),
    shadow: Color(0x99111318), // rgba(17,19,24,.6)
    overlay: RadialGradient(
      center: Alignment(1.0, -1.2), // 100% -10%
      radius: 1.25,
      colors: [Color(0x4DFF5A3C), Color(0x00FF5A3C)], // .30 → 0
      stops: [0.0, 0.55],
    ),
  ),
  // Закат — фиолетовый градиент + тёплое свечение снизу слева.
  CardTemplate(
    id: 'sunset',
    label: 'Закат',
    bg: [Color(0xFF3A1C71), Color(0xFF5A2A8F)],
    bgBegin: Alignment.topLeft,
    bgEnd: Alignment.bottomRight,
    accent: Color(0xFFFFAF7B),
    photoInner: Color(0xFF4A2580),
    shadow: Color(0x993A1C71), // rgba(58,28,113,.6)
    overlay: RadialGradient(
      center: Alignment(-1.0, 1.4), // 0% 120%
      radius: 1.3,
      colors: [Color(0x6BFFAF7B), Color(0x00FFAF7B)], // .42 → 0
      stops: [0.0, 0.55],
    ),
  ),
  // Мята — глубокий изумруд + мятное свечение сверху справа.
  CardTemplate(
    id: 'mint',
    label: 'Мята',
    bg: [Color(0xFF0F3D3E)],
    accent: Color(0xFF7BE0AD),
    photoInner: Color(0xFF15514F),
    shadow: Color(0x8C0F3D3E), // rgba(15,61,62,.55)
    overlay: RadialGradient(
      center: Alignment(1.0, -1.0), // 100% 0
      radius: 1.15,
      colors: [Color(0x477BE0AD), Color(0x007BE0AD)], // .28 → 0
      stops: [0.0, 0.50],
    ),
  ),
  // Нуар — почти чёрный, без свечения (в дизайне overlay отсутствует).
  CardTemplate(
    id: 'noir',
    label: 'Нуар',
    bg: [Color(0xFF0B0B0D)],
    accent: Color(0xFFE5E5E5),
    photoInner: Color(0xFF1A1A1C),
    shadow: Color(0xB3000000), // rgba(0,0,0,.7)
  ),
  // Бумага — единственный светлый шаблон, тёмный текст.
  CardTemplate(
    id: 'paper',
    label: 'Бумага',
    bg: [Color(0xFFF5F1E8)],
    accent: Color(0xFFFF5A3C),
    photoInner: Color(0xFFEFE9E0),
    shadow: Color(0x1F161310), // rgba(22,19,16,.12)
    darkText: true,
    overlay: RadialGradient(
      center: Alignment(1.0, -1.2),
      radius: 1.25,
      colors: [Color(0x24FF5A3C), Color(0x00FF5A3C)],
      stops: [0.0, 0.55],
    ),
  ),
];

/// Разбирает JSON-строку `style` карточки в шаблон. Невалидная/пустая → дефолт.
CardTemplate templateFromStyle(String style) {
  if (style.isNotEmpty) {
    try {
      final id = (jsonDecode(style) as Map)['template']?.toString();
      final match = cardTemplates.where((t) => t.id == id);
      if (match.isNotEmpty) return match.first;
    } catch (_) {/* невалидный JSON — дефолт */}
  }
  return cardTemplates.first;
}

/// Кодирует выбранный шаблон обратно в поле `style`.
String styleFromTemplate(CardTemplate t) => jsonEncode({'template': t.id});
