import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import 'widgets/file_cover_widget.dart';

/// Дизайн-язык «Читальни»: тёплая бумага, серифные заголовки с итальянскими
/// акцентами, книжные корешки вместо плоских плиток, обложки с бликом.
///
/// Единый слой для всех экранов библиотеки: фон-бумага, верхние панели
/// (главная — с «Выйти», подстраница — со стрелкой «Назад»), корешок книги,
/// секционный заголовок.

// ─── Цвета библиотеки ───────────────────────────────────────────────────────

class LibColors {
  LibColors._();

  /// Кикер над заголовком («БИБЛИОТЕКА») — тёплый кирпичный на светлой теме,
  /// светлый коралл на тёмной.
  static const Color kickerLight = Color(0xFFB8462E);
  static const Color kickerDark = Color(0xFFFF7A5C);

  /// Плашки/сегменты на бумаге.
  static const Color chipLight = Color(0xFFF1EBE1);

  /// Плашка кнопки «Назад» — чуть светлее чипов (по дизайну #F4EFE8).
  static const Color backChipLight = Color(0xFFF4EFE8);

  /// Бейдж «Рекомендации» на Обзоре — фиолетовый из дизайна.
  static const Color recommendation = Color(0xFF9B37C9);

  /// Линейки: обводка карточек и тонкие разделители секций.
  static const Color lineLight = Color(0xFFEDE6DB);
  static const Color hairlineLight = Color(0xFFE6DECF);

  /// Гарнир на стат-карточках (приглушённый на тёплом фоне).
  static const Color mutedWarm = Color(0xFFB0A896);

  /// Тёплый градиент hero «продолжить чтение».
  static const List<Color> heroLight = [
    Color(0xFF2C211A),
    Color(0xFF43331F),
    Color(0xFF5D4530),
  ];
  static const List<Color> heroDark = [Color(0xFF3A2C20), Color(0xFF241A12)];

  /// Тёплый акцент на hero (италик-подпись).
  static const Color heroItalic = Color(0xFFFFB694);
  static const Color goalItalic = Color(0xFFFFB08C);

  static Color kicker(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? kickerDark : kickerLight;

  static Color chip(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? SeeUColors.darkSurface2
          : chipLight;

  static Color line(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? SeeUColors.darkLine
          : lineLight;

  static Color hairline(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? SeeUColors.darkLine
          : hairlineLight;

  /// Корешок категории — цвет из бэкенда (FileCategory.color), градиент к тени.
  static List<Color> spineOf(Color base) => [
        base,
        Color.lerp(base, Colors.black, 0.36)!,
      ];
}

// ─── Бумага: зерно + виньетка ───────────────────────────────────────────────

/// Тёплая бумага с зерном (горизонтальные линии 1px через 3px) и виньеткой.
/// Оборачивает контент библиотеки — фон живой, а не плоская заливка.
class PaperBackground extends StatelessWidget {
  final Widget child;

  const PaperBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      color: c.bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PaperGrainPainter(
                  dark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Зерно бумаги + (опц.) виньетка. Публичный — переиспользуется ридерами
/// поверх страницы (сепия/тёмная задают свой [grainColor] с низкой альфой).
class PaperGrainPainter extends CustomPainter {
  final bool dark;

  /// Цвет линий зерна. null = дефолт по [dark].
  final Color? grainColor;

  /// Рисовать ли виньетку по краям (на странице ридера — нет).
  final bool vignette;

  const PaperGrainPainter({
    required this.dark,
    this.grainColor,
    this.vignette = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Зерно: repeating-linear-gradient(0deg, rgba(...) 0 1px, transparent 1px 3px)
    final grain = Paint()
      ..color = grainColor ??
          (dark
              ? const Color(0xFFFFDCB4).withValues(alpha: 0.012)
              : const Color(0xFF785A3C).withValues(alpha: 0.016))
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grain);
    }

    if (!vignette) return;

    // Виньетка: inset 0 0 120px — мягкое затемнение по краям.
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        radius: 0.9,
        colors: [
          Colors.transparent,
          dark
              ? Colors.black.withValues(alpha: 0.5)
              : const Color(0xFF5A4632).withValues(alpha: 0.05),
        ],
        stops: const [0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignettePaint);
  }

  @override
  bool shouldRepaint(PaperGrainPainter old) =>
      old.dark != dark ||
      old.grainColor != grainColor ||
      old.vignette != vignette;
}

// ─── Верх главных вкладок (паттерн B) ───────────────────────────────────────

/// Шапка главной вкладки библиотеки: кикер «БИБЛИОТЕКА», крупный серифный
/// заголовок и «Выйти» справа — быстрый возврат в «Сервисы».
class LibMainBar extends StatelessWidget {
  final String title;

  /// Дополнительное действие слева от «Выйти» (обычно поиск).
  final Widget? action;

  const LibMainBar({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'БИБЛИОТЕКА',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: LibColors.kicker(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeeUTypography.displayS.copyWith(
                    fontSize: 40,
                    height: 0.92,
                    letterSpacing: -1.6,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (action != null) ...[action!, const SizedBox(width: 8)],
          const LibExitButton(),
        ],
      ),
    );
  }
}

/// «Выйти» — всегда справа сверху на всех 4 главных вкладках библиотеки.
class LibExitButton extends StatelessWidget {
  const LibExitButton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? SeeUColors.darkInk : SeeUColors.textPrimary;
    final fg = dark ? SeeUColors.textPrimary : c.bg;

    return Tappable.scaled(
      onTap: () {
        HapticFeedback.lightImpact();
        context.go('/services');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: SeeUColors.textPrimary.withValues(alpha: 0.5),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                    spreadRadius: -6,
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.signOut, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              'Выйти',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Квадратная кнопка в шапке (поиск и т.п.) — 40px, мягкая плашка.
class LibSquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const LibSquareButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: LibColors.chip(context),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: LibColors.line(context)),
        ),
        child: Icon(icon, size: 18, color: c.ink2),
      ),
    );
  }
}

// ─── Верх подстраниц (паттерн C) ────────────────────────────────────────────

/// Единая стрелка «Назад» на всех вложенных экранах библиотеки — 44px квадрат.
class LibBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  final double size;

  const LibBackButton({super.key, this.onTap, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tappable.scaled(
      onTap: onTap ?? () => context.pop(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // По дизайну плашка «Назад» — #F4EFE8 (светлее чипов #F1EBE1).
          color: dark ? SeeUColors.darkSurface2 : LibColors.backChipLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: LibColors.line(context)),
        ),
        child: Icon(PhosphorIcons.arrowLeft(), size: 20, color: c.ink),
      ),
    );
  }
}

/// Шапка подстраницы: стрелка «Назад» + (опц.) кикер и серифный заголовок +
/// (опц.) действие справа.
class LibBackBar extends StatelessWidget {
  final String? kicker;
  final String? title;
  final Widget? action;
  final VoidCallback? onBack;

  const LibBackBar({
    super.key,
    this.kicker,
    this.title,
    this.action,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Row(
        children: [
          LibBackButton(onTap: onBack),
          if (title != null) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (kicker != null)
                    Text(
                      kicker!,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: c.ink3,
                      ),
                    ),
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.displayS.copyWith(
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            const Spacer(),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ],
      ),
    );
  }
}

// ─── Секционный заголовок ───────────────────────────────────────────────────

/// «Категории ————— →» — серифный заголовок, тонкая линейка на всю ширину и
/// действие справа.
class LibSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const LibSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final row = Row(
      children: [
        Text(
          title,
          style: SeeUTypography.displayS.copyWith(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: c.ink,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: LibColors.hairline(context))),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
    if (onTap == null) return row;
    return Tappable(onTap: onTap, child: row);
  }
}

/// «Все» справа от секционного заголовка.
class LibSectionAction extends StatelessWidget {
  final String label;
  const LibSectionAction(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: LibColors.kicker(context),
        ),
      );
}

// ─── Корешок книги ──────────────────────────────────────────────────────────

/// Обложка-корешок: асимметричный радиус (слева — сгиб, справа — обрез),
/// световой блик по корешку слева, тень обреза справа и мягкая падающая тень.
/// Внутри — настоящая обложка файла (или сгенерированная по формату).
class BookSpine extends StatelessWidget {
  final FileItem file;
  final double width;
  final double height;

  /// Процент прочтения (0..1) — если задан, снизу появляется бейдж «45%».
  final double? progress;

  /// Радиус обреза (правый край). Левый край всегда вдвое меньше — сгиб.
  final double radius;

  const BookSpine({
    super.key,
    required this.file,
    required this.width,
    required this.height,
    this.progress,
    this.radius = 11,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.only(
      topLeft: Radius.circular(radius * 0.45),
      bottomLeft: Radius.circular(radius * 0.45),
      topRight: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 26,
            offset: const Offset(0, 16),
            spreadRadius: -12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FileCoverWidget(file: file, width: width, height: height, borderRadius: 0),
            // Блик корешка слева + тень обреза справа (inset-градиенты).
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.30),
                      Colors.white.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.38),
                    ],
                    stops: const [0.0, 0.13, 0.72, 1.0],
                  ),
                ),
              ),
            ),
            // Тонкая линия сгиба.
            Positioned(
              left: width * 0.045,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1.5,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ),
            if (progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(progress!.clamp(0.0, 1.0) * 100).round()}%',
                    style: SeeUTypography.displayS.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Палитра обложек ────────────────────────────────────────────────────────

/// Градиент обложки по формату — та же палитра, что рисует сгенерированную
/// обложку. Используется как фон hero на карточке книги, чтобы шапка была
/// продолжением обложки, а не случайным цветом.
const _coverGradients = <String, List<Color>>{
  'pdf': [Color(0xFFE53935), Color(0xFF8B1A1A)],
  'epub': [SeeUColors.accent, Color(0xFFBF360C)],
  'fb2': [Color(0xFF8E24AA), Color(0xFF4A148C)],
  'docx': [SeeUColors.info, Color(0xFF0D47A1)],
  'pptx': [Color(0xFF43A047), Color(0xFF1B5E20)],
  'txt': [Color(0xFF546E7A), Color(0xFF263238)],
  'rtf': [Color(0xFF6D4C41), Color(0xFF3E2723)],
  'md': [Color(0xFF00ACC1), Color(0xFF004D57)],
  'odt': [Color(0xFF039BE5), Color(0xFF01579B)],
  'odp': [Color(0xFFFB8C00), Color(0xFFBF360C)],
};

List<Color> coverGradientOf(FileItem file) =>
    _coverGradients[file.fileExtension] ??
    const [Color(0xFF607D8B), Color(0xFF37474F)];

// ─── Стекло читалки ─────────────────────────────────────────────────────────

/// Матовая панель читалки (верх/низ) — реальный backdrop-blur под полупрозрачным
/// фоном страницы, с тонкой линией по краю.
class ReaderGlass extends StatelessWidget {
  final Widget child;
  final Color tint;
  final Color line;
  final bool top;

  const ReaderGlass({
    super.key,
    required this.child,
    required this.tint,
    required this.line,
    this.top = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            border: top
                ? Border(bottom: BorderSide(color: line, width: 0.5))
                : Border(top: BorderSide(color: line, width: 0.5)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─── Полоса прогресса ───────────────────────────────────────────────────────

/// Тонкая коралловая полоса прогресса на мягкой подложке.
class LibProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? track;
  final Gradient? gradient;

  const LibProgressBar({
    super.key,
    required this.value,
    this.height = 5,
    this.track,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: track ?? LibColors.chip(context),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              gradient: gradient ??
                  const LinearGradient(
                    colors: [SeeUColors.accent, SeeUColors.accentSecondary],
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Оценка времени чтения ──────────────────────────────────────────────────

/// «осталось ~5 ч 20 мин» — из числа непрочитанных страниц (≈1.6 мин/стр).
String remainingReadingTime(int pagesLeft) {
  if (pagesLeft <= 0) return 'почти дочитано';
  final minutes = (pagesLeft * 1.6).round();
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return 'осталось ~$m мин';
  if (m == 0) return 'осталось ~$h ч';
  return 'осталось ~$h ч $m мин';
}

/// «~16 ч.» — полная оценка чтения книги по числу страниц.
String totalReadingTime(int pages) {
  if (pages <= 0) return '';
  final h = (pages * 1.6 / 60).round();
  return h <= 0 ? '<1 ч.' : '~$h ч.';
}

// ─── Пунктирная рамка ───────────────────────────────────────────────────────

/// Скруглённый прямоугольник пунктиром — области «Обложка» / «Выбрать файл»
/// в шторке загрузки и плитка «Новая коллекция».
class LibDashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  const LibDashedBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = 12,
    this.strokeWidth = 1.5,
    this.dash = 5,
    this.gap = 4,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRectPainter(
        color: color,
        radius: radius,
        strokeWidth: strokeWidth,
        dash: dash,
        gap: gap,
      ),
      child: child,
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  const _DashedRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    // Режем контур на штрихи dash/gap вдоль всей длины.
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}
