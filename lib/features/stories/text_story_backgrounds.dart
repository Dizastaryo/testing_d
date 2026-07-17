import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// Фоновые пресеты для text-сторис. Создание text-сторис из приложения убрано,
/// но вьюер должен уметь отрисовать уже существующие (ещё не истёкшие) — `id`
/// хранится в БД как `bg_color`. Если градиента нет — рендерим solid color.
class TextStoryBackground {
  final String id;
  final Gradient? gradient;
  final Color? color;
  final Color textColor;
  const TextStoryBackground({
    required this.id,
    this.gradient,
    this.color,
    this.textColor = Colors.white,
  });
}

const kTextStoryBackgrounds = <TextStoryBackground>[
  TextStoryBackground(
    id: 'sunset',
    gradient: LinearGradient(
      colors: [Color(0xFFFF7E5F), Color(0xFFFEB47B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'ocean',
    gradient: LinearGradient(
      colors: [Color(0xFF2193b0), Color(0xFF6dd5ed)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'forest',
    gradient: LinearGradient(
      colors: [Color(0xFF134E5E), Color(0xFF71B280)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'orange',
    gradient: LinearGradient(
      colors: [SeeUColors.accent, Color(0xFFFFB088)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'midnight',
    gradient: LinearGradient(
      colors: [Color(0xFF232526), Color(0xFF414345)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'mono',
    color: Color(0xFF111111),
  ),
  TextStoryBackground(
    id: 'paper',
    color: Color(0xFFFBF6E9),
    textColor: Color(0xFF111111),
  ),
];

/// Возвращает preset по id, fallback на 'sunset'. Используется во вьюере сторис.
TextStoryBackground textStoryBackgroundFor(String id) {
  for (final bg in kTextStoryBackgrounds) {
    if (bg.id == id) return bg;
  }
  return kTextStoryBackgrounds.first;
}
