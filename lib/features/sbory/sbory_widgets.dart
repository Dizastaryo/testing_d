import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/design/design.dart';

/// Overlapping avatar stack — shared between sbory screens.
class SboryAvatarStack extends StatelessWidget {
  final List<String> names;
  final List<String> avatarUrls;
  final double size;
  final Color? ringColor;

  const SboryAvatarStack({
    super.key,
    required this.names,
    this.avatarUrls = const [],
    this.size = 28,
    this.ringColor,
  });

  static const _max = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final shown = names.take(_max).toList();
    final overflow = names.length > _max ? names.length - _max : 0;
    final ring = ringColor ?? c.surface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < shown.length; i++)
          Transform.translate(
            offset: Offset(i == 0 ? 0 : -size * 0.3 * i, 0),
            child: _avatar(shown[i], i < avatarUrls.length ? avatarUrls[i] : '', ring),
          ),
        if (overflow > 0)
          Transform.translate(
            offset: Offset(-size * 0.3 * shown.length, 0),
            child: Container(
              width: size, height: size,
              decoration: BoxDecoration(
                color: c.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 2),
              ),
              child: Center(
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                    fontSize: size * 0.36,
                    fontWeight: FontWeight.w600,
                    color: c.ink2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _avatar(String name, String avatarUrl, Color ring) {
    final seed = (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[seed];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final resolvedUrl = avatarUrl.isEmpty
        ? null
        : avatarUrl.startsWith('http')
            ? avatarUrl
            : AppConfig.apiOrigin + avatarUrl;

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: resolvedUrl == null ? LinearGradient(colors: pal) : null,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 2),
      ),
      child: ClipOval(
        child: resolvedUrl != null
            ? CachedNetworkImage(
                imageUrl: resolvedUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallback(initial, pal),
              )
            : _fallback(initial, pal),
      ),
    );
  }

  Widget _fallback(String initial, List<Color> pal) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: pal)),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.42,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sbory Date Filter Sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Результат выбора дат — диапазон и метка пресета (если применён).
class SboryDateResult {
  final DateTimeRange? range;
  final String? presetLabel;
  const SboryDateResult({this.range, this.presetLabel});
}

/// Кастомный bottom-sheet выбора дат для фильтра сборов.
/// Возвращает [SboryDateResult] через Navigator.pop.
class SboryDateFilterSheet extends StatefulWidget {
  final DateTimeRange? initialRange;
  const SboryDateFilterSheet({super.key, this.initialRange});

  @override
  State<SboryDateFilterSheet> createState() => _SboryDateFilterSheetState();
}

class _SboryDateFilterSheetState extends State<SboryDateFilterSheet> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _viewMonth;
  String? _activePreset;

  static const _monthNames = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];
  static const _shortMonths = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  static const _presets = [
    (id: 'today',     label: 'Сегодня'),
    (id: 'tomorrow',  label: 'Завтра'),
    (id: 'week',      label: 'Эта неделя'),
    (id: 'next_week', label: 'Сл. неделя'),
    (id: 'month',     label: 'Этот месяц'),
  ];

  static DateTimeRange _presetRange(String id) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (id) {
      case 'today':
        return DateTimeRange(start: today, end: today);
      case 'tomorrow':
        final t = today.add(const Duration(days: 1));
        return DateTimeRange(start: t, end: t);
      case 'week':
        final mon = today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(start: mon, end: mon.add(const Duration(days: 6)));
      case 'next_week':
        final mon = today
            .subtract(Duration(days: today.weekday - 1))
            .add(const Duration(days: 7));
        return DateTimeRange(start: mon, end: mon.add(const Duration(days: 6)));
      case 'month':
        final first = DateTime(today.year, today.month, 1);
        final last  = DateTime(today.year, today.month + 1, 0);
        return DateTimeRange(start: first, end: last);
      default:
        return DateTimeRange(start: today, end: today);
    }
  }

  @override
  void initState() {
    super.initState();
    final ir = widget.initialRange;
    if (ir != null) {
      _start      = ir.start;
      _end        = ir.end;
      _viewMonth  = DateTime(ir.start.year, ir.start.month);
    } else {
      final now   = DateTime.now();
      _viewMonth  = DateTime(now.year, now.month);
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _onDayTap(DateTime raw) {
    final day = DateTime(raw.year, raw.month, raw.day);
    HapticFeedback.selectionClick();
    setState(() {
      _activePreset = null;
      if (_start == null || (_start != null && _end != null)) {
        // Начать новый выбор
        _start = day;
        _end   = null;
      } else {
        // Второй тап — установить конец
        if (day.isBefore(_start!)) {
          _end   = _start;
          _start = day;
        } else {
          _end = day; // включает один день (start == end)
        }
      }
    });
  }

  void _applyPreset(String id) {
    HapticFeedback.selectionClick();
    final range = _presetRange(id);
    setState(() {
      _activePreset = id;
      _start        = range.start;
      _end          = range.end;
      _viewMonth    = DateTime(range.start.year, range.start.month);
    });
  }

  void _prevMonth() {
    final prev  = DateTime(_viewMonth.year, _viewMonth.month - 1);
    final limit = DateTime(DateTime.now().year, DateTime.now().month - 1);
    if (!prev.isBefore(limit)) setState(() => _viewMonth = prev);
  }

  void _nextMonth() {
    final next  = DateTime(_viewMonth.year, _viewMonth.month + 1);
    final limit = DateTime(DateTime.now().year, DateTime.now().month + 13);
    if (!next.isAfter(limit)) setState(() => _viewMonth = next);
  }

  String _fmtSelected() {
    if (_start == null) return 'Выберите дату';
    final s  = _start!;
    final e  = _end;
    final sm = _shortMonths[s.month - 1];
    if (e == null || _sameDay(s, e)) return '${s.day} $sm';
    if (s.month == e.month && s.year == e.year) return '${s.day}–${e.day} $sm';
    return '${s.day} $sm – ${e.day} ${_shortMonths[e.month - 1]}';
  }

  void _apply() {
    HapticFeedback.mediumImpact();
    if (_start == null) return;
    final end   = _end ?? _start!;
    final range = DateTimeRange(start: _start!, end: end);
    final label = _activePreset != null
        ? _presets.firstWhere((p) => p.id == _activePreset).label
        : null;
    Navigator.pop(context, SboryDateResult(range: range, presetLabel: label));
  }

  void _clear() {
    HapticFeedback.lightImpact();
    Navigator.pop(context, const SboryDateResult());
  }

  @override
  Widget build(BuildContext context) {
    final c       = context.seeuColors;
    final hasDate = _start != null;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SeeURadii.sheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ──────────────────────────────────────────
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(SeeURadii.small),
                    ),
                    child: Icon(PhosphorIcons.calendarBlank(),
                        size: 20, color: SeeUColors.accent),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Фильтр по дате',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
            // ── Быстрый выбор ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presets.map((p) {
                  final active = _activePreset == p.id;
                  return GestureDetector(
                    onTap: () => _applyPreset(p.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: active ? SeeUColors.accent : c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                        border: Border.all(
                          color: active ? SeeUColors.accent : c.line,
                          width: 0.5,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: SeeUColors.accent
                                      .withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        p.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? Colors.white : c.ink2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Divider(height: 1, color: c.line),
            // ── Навигация по месяцу ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  _NavBtn(icon: PhosphorIcons.caretLeft(),  onTap: _prevMonth, c: c),
                  Expanded(
                    child: Text(
                      '${_monthNames[_viewMonth.month - 1]} ${_viewMonth.year}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                  _NavBtn(icon: PhosphorIcons.caretRight(), onTap: _nextMonth, c: c),
                ],
              ),
            ),
            // ── Заголовки дней недели ────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: _weekdays.map((d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.ink3,
                      ),
                    ),
                  ),
                )).toList(),
              ),
            ),
            // ── Сетка дней ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _CalendarGrid(
                viewMonth: _viewMonth,
                start: _start,
                end: _end,
                onDayTap: _onDayTap,
              ),
            ),
            Divider(height: 1, color: c.line),
            // ── Кнопки ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  // Сбросить
                  Expanded(
                    child: GestureDetector(
                      onTap: _clear,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                          border: Border.all(color: c.line, width: 0.5),
                        ),
                        child: Center(
                          child: Text(
                            'Сбросить',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.ink2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Применить
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: hasDate ? _apply : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: hasDate ? SeeUGradients.heroOrange : null,
                          color: !hasDate ? c.line : null,
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                          boxShadow: hasDate
                              ? [
                                  BoxShadow(
                                    color: SeeUColors.accent
                                        .withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasDate) ...[
                                const Icon(PhosphorIconsBold.check,
                                    size: 15, color: Colors.white),
                                const SizedBox(width: 7),
                              ],
                              Text(
                                _fmtSelected(),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: hasDate ? Colors.white : c.ink3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ── Navigation arrow button ────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final SeeUThemeColors c;
  const _NavBtn({required this.icon, required this.onTap, required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: Icon(icon, size: 16, color: c.ink2)),
      ),
    );
  }
}

// ── Calendar grid ──────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime viewMonth;
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime) onDayTap;

  const _CalendarGrid({
    required this.viewMonth,
    this.start,
    this.end,
    required this.onDayTap,
  });

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isStart(DateTime d) => start != null && _sameDay(d, start!);
  bool _isEnd(DateTime d)   => end   != null && _sameDay(d, end!);
  bool _isToday(DateTime d) => _sameDay(d, DateTime.now());

  bool _inRange(DateTime d) {
    if (start == null || end == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    return day.isAfter(start!) && day.isBefore(end!);
  }

  @override
  Widget build(BuildContext context) {
    final c           = context.seeuColors;
    final firstDay    = DateTime(viewMonth.year, viewMonth.month, 1);
    final daysInMonth = DateTime(viewMonth.year, viewMonth.month + 1, 0).day;
    final leading     = firstDay.weekday - 1; // Пн=0
    final rowCount    = ((leading + daysInMonth) / 7).ceil();

    return Column(
      children: List.generate(rowCount, (row) {
        return Row(
          children: List.generate(7, (col) {
            final idx = row * 7 + col;
            if (idx < leading || idx >= leading + daysInMonth) {
              return const Expanded(child: SizedBox(height: 44));
            }
            final day = DateTime(viewMonth.year, viewMonth.month, idx - leading + 1);
            return Expanded(
              child: _DayCell(
                date:     day,
                isStart:  _isStart(day),
                isEnd:    _isEnd(day),
                inRange:  _inRange(day),
                isToday:  _isToday(day),
                onTap:    () => onDayTap(day),
                c:        c,
              ),
            );
          }),
        );
      }),
    );
  }
}

// ── Day cell ───────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final DateTime date;
  final bool isStart;
  final bool isEnd;
  final bool inRange;
  final bool isToday;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _DayCell({
    required this.date,
    required this.isStart,
    required this.isEnd,
    required this.inRange,
    required this.isToday,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected  = isStart || isEnd;
    final isSingleDay = isStart && isEnd;
    // Полоса: левая половина показывается перед концом диапазона,
    // правая — после начала. При одном дне обе скрыты.
    final hasLeft  = (inRange || isEnd)   && !isSingleDay;
    final hasRight = (inRange || isStart) && !isSingleDay;
    final strip    = SeeUColors.accent.withValues(alpha: 0.13);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Полоса диапазона
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(child: Container(color: hasLeft  ? strip : null)),
                  Expanded(child: Container(color: hasRight ? strip : null)),
                ],
              ),
            ),
            // Кружок выделения (начало / конец)
            if (isSelected)
              Container(
                width: 38, height: 38,
                decoration: const BoxDecoration(
                  gradient: SeeUGradients.heroOrange,
                  shape: BoxShape.circle,
                ),
              ),
            // Точка «сегодня» (только если не выбран)
            if (isToday && !isSelected)
              Positioned(
                bottom: 5,
                child: Container(
                  width: 4, height: 4,
                  decoration: const BoxDecoration(
                    color: SeeUColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            // Число
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected
                    ? Colors.white
                    : (inRange || isToday)
                        ? SeeUColors.accent
                        : c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
