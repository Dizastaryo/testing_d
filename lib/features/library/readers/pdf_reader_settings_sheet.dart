import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import 'pdf_reader_settings.dart';

class PdfReaderSettingsSheet extends ConsumerWidget {
  /// Текущая и общая страницы + переход — секция «Перейти к странице».
  /// Если ридер их не передал, секция не показывается.
  final int currentPage;
  final int totalPages;
  final ValueChanged<int>? onGoToPage;

  const PdfReaderSettingsSheet({
    super.key,
    this.currentPage = 0,
    this.totalPages = 0,
    this.onGoToPage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(pdfReaderSettingsProvider);
    final notifier = ref.read(pdfReaderSettingsProvider.notifier);
    final c = context.seeuColors;

    return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(context).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(PhosphorIconsRegular.gear,
                      size: 19, color: SeeUColors.accent),
                ),
                const SizedBox(width: 10),
                Text(
                  'Настройки PDF',
                  style: SeeUTypography.displayS.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Почему тут нет шрифта и кегля — у PDF вёрстка зашита в файл.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: SeeUColors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: SeeUColors.amber.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.info,
                      size: 16, color: SeeUColors.amber),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Фиксированный формат — шрифт и кегль изменить нельзя',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: c.isDark
                            ? SeeUColors.amber
                            : const Color(0xFFC99A3F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (onGoToPage != null && totalPages > 0) ...[
              _GoToPageRow(
                current: currentPage,
                total: totalPages,
                onGo: onGoToPage!,
              ),
              const SizedBox(height: 16),
            ],

            // ── Quick presets ────────────────────────────────────────────
            Row(
              children: [
                _PresetChip(
                  label: 'Дневной',
                  icon: PhosphorIconsRegular.sun,
                  active: settings.themeMode == PdfThemeMode.light &&
                      !settings.isHorizontal &&
                      settings.pageFling,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.applyPreset(PdfReaderSettings.day);
                  },
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: 'Ночной',
                  icon: PhosphorIconsRegular.moon,
                  active: settings.isNightMode && !settings.isHorizontal,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.applyPreset(PdfReaderSettings.night);
                  },
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: 'Книга',
                  icon: PhosphorIconsRegular.bookOpen,
                  active: settings.isHorizontal && settings.pageFling,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.applyPreset(PdfReaderSettings.flipBook);
                  },
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: 'Лента',
                  icon: PhosphorIconsRegular.arrowsDownUp,
                  active: !settings.pageFling && !settings.autoSpacing,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.applyPreset(PdfReaderSettings.continuous);
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Theme ───────────────────────────────────────────────────
            _SectionLabel(label: 'Тема', c: c),
            const SizedBox(height: 8),
            Row(
              children: [
                _ThemeChip(
                  label: 'Светлая',
                  bgColor: Colors.white,
                  textColor: Colors.black87,
                  selected: settings.themeMode == PdfThemeMode.light,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setTheme(PdfThemeMode.light);
                  },
                ),
                const SizedBox(width: 8),
                _ThemeChip(
                  label: 'Тёмная',
                  bgColor: const Color(0xFF1A1A1A),
                  textColor: const Color(0xFFE0E0E0),
                  selected: settings.themeMode == PdfThemeMode.dark,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setTheme(PdfThemeMode.dark);
                  },
                ),
                const SizedBox(width: 8),
                _ThemeChip(
                  label: 'AMOLED',
                  bgColor: Colors.black,
                  textColor: Colors.white,
                  selected: settings.themeMode == PdfThemeMode.amoled,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setTheme(PdfThemeMode.amoled);
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Scroll direction ────────────────────────────────────────
            _SectionLabel(label: 'Направление листания', c: c),
            const SizedBox(height: 8),
            Row(
              children: [
                _OptionChip(
                  icon: PhosphorIconsRegular.arrowsDownUp,
                  label: 'Вертикально',
                  selected:
                      settings.scrollDirection == PdfScrollDirection.vertical,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setScrollDirection(PdfScrollDirection.vertical);
                  },
                ),
                const SizedBox(width: 10),
                _OptionChip(
                  icon: PhosphorIconsRegular.arrowsLeftRight,
                  label: 'Горизонтально',
                  selected:
                      settings.scrollDirection == PdfScrollDirection.horizontal,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setScrollDirection(PdfScrollDirection.horizontal);
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Toggle switches ─────────────────────────────────────────
            _SectionLabel(label: 'Поведение', c: c),
            const SizedBox(height: 8),

            _ToggleRow(
              icon: PhosphorIconsRegular.arrowFatLineRight,
              label: 'Привязка к страницам',
              subtitle: 'Щелчок при пролистывании',
              value: settings.pageFling,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                notifier.setPageFling(v);
              },
            ),
            const SizedBox(height: 4),
            _ToggleRow(
              icon: PhosphorIconsRegular.splitVertical,
              label: 'Отступы между страниц',
              subtitle: 'Визуальное разделение',
              value: settings.autoSpacing,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                notifier.setAutoSpacing(v);
              },
            ),
            const SizedBox(height: 4),
            _ToggleRow(
              icon: PhosphorIconsRegular.circleHalf,
              label: 'Ночной режим · инверсия',
              subtitle: 'Инвертирует цвета страницы',
              value: settings.nightInvert,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                notifier.setNightInvert(v);
              },
            ),
            const SizedBox(height: 4),
            _ToggleRow(
              icon: PhosphorIconsRegular.sunHorizon,
              label: 'Не гаснуть экрану',
              subtitle: 'Пока открыт ридер',
              value: settings.keepAwake,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                notifier.setKeepAwake(v);
              },
            ),
            const SizedBox(height: 20),

            // ── Background color ────────────────────────────────────────
            _SectionLabel(label: 'Фон вокруг страниц', c: c),
            const SizedBox(height: 8),
            Row(
              children: [
                _BgChip(
                  label: 'Авто',
                  color: settings.isNightMode
                      ? const Color(0xFF121212)
                      : const Color(0xFFF0F0F0),
                  // Диагональная бело/тёмная заливка — «подстроится сам».
                  diagonal: true,
                  selected: settings.background == PdfBackground.auto,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setBackground(PdfBackground.auto);
                  },
                ),
                const SizedBox(width: 8),
                _BgChip(
                  label: 'Белый',
                  color: const Color(0xFFF5F5F5),
                  selected: settings.background == PdfBackground.white,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setBackground(PdfBackground.white);
                  },
                ),
                const SizedBox(width: 8),
                _BgChip(
                  label: 'Тёмный',
                  color: const Color(0xFF1A1A1A),
                  selected: settings.background == PdfBackground.dark,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setBackground(PdfBackground.dark);
                  },
                ),
                const SizedBox(width: 8),
                _BgChip(
                  label: 'Чёрный',
                  color: Colors.black,
                  selected: settings.background == PdfBackground.black,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setBackground(PdfBackground.black);
                  },
                ),
              ],
            ),
          ],
        ),
    );
  }
}

// ─── Section label ──────────────────────────────────────────────────────────

/// «Перейти к странице» — поле с текущей/общей страницей и коралловой стрелкой.
class _GoToPageRow extends StatefulWidget {
  final int current;
  final int total;
  final ValueChanged<int> onGo;

  const _GoToPageRow({
    required this.current,
    required this.total,
    required this.onGo,
  });

  @override
  State<_GoToPageRow> createState() => _GoToPageRowState();
}

class _GoToPageRowState extends State<_GoToPageRow> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current > 0 ? '${widget.current}' : '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _go() {
    final page = int.tryParse(_ctrl.text.trim());
    if (page == null || page < 1 || page > widget.total) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.selectionClick();
    widget.onGo(page);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Row(
      children: [
        Icon(PhosphorIconsRegular.bookOpen, size: 16, color: c.ink3),
        const SizedBox(width: 12),
        Text('Перейти к странице',
            style: TextStyle(fontSize: 13, color: c.ink2)),
        const Spacer(),
        Container(
          width: 92,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _go(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
              Text(
                ' / ${widget.total}',
                style: TextStyle(fontSize: 13, color: c.ink3),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Tappable.scaled(
          onTap: _go,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: SeeUColors.accent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(PhosphorIconsBold.arrowRight,
                size: 14, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final SeeUThemeColors c;
  const _SectionLabel({required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: TextStyle(fontSize: 13, color: c.ink2));
  }
}

// ─── Preset chip ────────────────────────────────────────────────────────────

class _PresetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _PresetChip(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? SeeUColors.accent.withValues(alpha: 0.1)
                : context.seeuColors.surface2,
            border: Border.all(
              color: active ? SeeUColors.accent : Colors.transparent,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color:
                      active ? SeeUColors.accent : context.seeuColors.ink3),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color:
                      active ? SeeUColors.accent : context.seeuColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Theme chip ─────────────────────────────────────────────────────────────

class _ThemeChip extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeChip(
      {required this.label,
      required this.bgColor,
      required this.textColor,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(
              color: selected
                  ? SeeUColors.accent
                  : Colors.grey.withValues(alpha: 0.3),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Option chip (direction) ────────────────────────────────────────────────

class _OptionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OptionChip(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? SeeUColors.accent.withValues(alpha: 0.1)
                : context.seeuColors.surface2,
            border: Border.all(
              color: selected ? SeeUColors.accent : Colors.transparent,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color:
                      selected ? SeeUColors.accent : context.seeuColors.ink3),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      selected ? SeeUColors.accent : context.seeuColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Toggle row ─────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: c.ink)),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, color: c.ink4)),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: SeeUColors.accent,
              activeThumbColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Background chip ────────────────────────────────────────────────────────

class _BgChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// Диагональная бело/тёмная заливка — чип «Авто» (фон подстраивается сам).
  final bool diagonal;

  const _BgChip(
      {required this.label,
      required this.color,
      required this.selected,
      required this.onTap,
      this.diagonal = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 48,
          decoration: BoxDecoration(
            color: diagonal ? null : color,
            border: Border.all(
              color: selected
                  ? SeeUColors.accent
                  : Colors.grey.withValues(alpha: 0.3),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: diagonal
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    const CustomPaint(painter: _DiagonalSplitPainter()),
                    Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          // Белое гало — читается и на тёмной половине.
                          shadows: [
                            Shadow(color: Colors.white, blurRadius: 4),
                            Shadow(color: Colors.white, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: color.computeLuminance() > 0.4
                        ? Colors.black87
                        : Colors.white70,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Диагональ бел/тёмн для чипа «Авто»: светлый треугольник сверху-слева,
/// тёмный снизу-справа.
class _DiagonalSplitPainter extends CustomPainter {
  const _DiagonalSplitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFFF5F5F5);
    final dark = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawRect(Offset.zero & size, light);
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, dark);
  }

  @override
  bool shouldRepaint(_DiagonalSplitPainter oldDelegate) => false;
}
