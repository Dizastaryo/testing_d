import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/audio_category.dart';
import '../../core/models/audio_track.dart';

/// Дизайн-язык Аудиотеки.
///
/// Из семьи Библиотеки (тёплая бумага, Playfair + Inter, коралл), но несущий
/// мотив другой: **честная волна** вместо книжных корешков. Волна рисуется из
/// настоящих `waveform_data` (100 пиков), а не из декоративной гребёнки; там,
/// где данных нет, честно показываем тонкую полосу, а не выдуманные пики.

// ─── Режим прослушивания ────────────────────────────────────────────────────

/// 9 категорий → 4 режима. Это главное решение дизайна: у мема на 3 секунды и
/// у подкаста на 2 часа разные сценарии, поэтому у них разный пульт и разная
/// карточка — при общем плеере и общей очереди.
enum ListenMode {
  /// Музыка · Инструментал · Другое — волна, шаффл, повтор, скорость.
  song,

  /// Подкасты · Образование · Новости — ±30 сек, скорость на виду.
  talk,

  /// Аудиокниги · Медитация — продолжить с места, таймер сна, минимум хрома.
  book,

  /// Мемы — мгновенный старт и петля, «Взять в видео». Без экрана-простыни.
  moment,
}

ListenMode modeOfCategory(String category) {
  switch (category) {
    case 'podcasts':
    case 'education':
    case 'news':
      return ListenMode.talk;
    case 'audiobooks':
    case 'meditation':
      return ListenMode.book;
    case 'memes':
      return ListenMode.moment;
    default:
      return ListenMode.song;
  }
}

ListenMode modeOf(AudioTrack t) => modeOfCategory(t.category);

extension ListenModeX on ListenMode {
  /// Цвет режима — он же цвет ведущей категории. Плеер и карточка красятся им,
  /// поэтому по одному взгляду ясно, что именно ты слушаешь.
  Color get color => switch (this) {
        ListenMode.song => SeeUColors.accent,
        ListenMode.talk => const Color(0xFF7B5EA7),
        ListenMode.book => const Color(0xFF4A90D9),
        ListenMode.moment => const Color(0xFFFF8C42),
      };

  /// Тон для мягких плашек под цвет режима.
  Color soft(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? color.withValues(alpha: 0.18)
      : Color.alphaBlend(color.withValues(alpha: 0.12), Colors.white);

  IconData get icon => switch (this) {
        ListenMode.song => PhosphorIconsFill.musicNotes,
        ListenMode.talk => PhosphorIconsFill.microphone,
        ListenMode.book => PhosphorIconsFill.bookOpen,
        ListenMode.moment => PhosphorIconsFill.smiley,
      };

  String get label => switch (this) {
        ListenMode.song => 'Песня',
        ListenMode.talk => 'Разговор',
        ListenMode.book => 'Книга',
        ListenMode.moment => 'Момент',
      };

  /// Можно ли «продолжить с места». Трёхсекундный мем продолжать нечего,
  /// а песню — незачем.
  bool get resumable => this == ListenMode.talk || this == ListenMode.book;

  /// Шаг перемотки для разговора и книги.
  int get skipSeconds => this == ListenMode.book ? 15 : 30;
}

// ─── Цвета аудиотеки ────────────────────────────────────────────────────────

class AudioColors {
  AudioColors._();

  /// Кикер над заголовком («АУДИОТЕКА»).
  static const Color kickerLight = Color(0xFFB8462E);
  static const Color kickerDark = Color(0xFFFF7A5C);

  /// Бумажный «остаток» волны — то, что ещё не сыграно.
  static const Color waveRestLight = Color(0xFFE6DECF);

  /// Статусы модерации.
  static const Color pending = Color(0xFFC97A00);
  static const Color pendingBg = Color(0xFFFFF3E0);
  static const Color approved = Color(0xFF1E7A38);
  static const Color approvedBg = Color(0xFFE7F5EC);
  static const Color rejected = Color(0xFFC62828);
  static const Color rejectedBg = Color(0xFFFDEAEA);
  static const Color rejectedBorder = Color(0xFFF4C7C4);

  static Color kicker(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? kickerDark : kickerLight;

  static Color waveRest(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.16)
          : waveRestLight;
}

// ─── Честная волна ──────────────────────────────────────────────────────────

/// Осциллограмма из настоящих пиков трека. Сыгранная часть — цветом режима,
/// остаток — бумажный. Если пиков нет (старые треки), рисуется тонкая полоса
/// прогресса: врать гребёнкой нельзя.
class TrackWaveform extends StatefulWidget {
  final List<double>? peaks;

  /// 0..1 — сколько сыграно.
  final double progress;

  final Color color;
  final double height;

  /// Тап/перетаскивание по волне — перемотка. null — волна декоративная.
  final ValueChanged<double>? onSeek;

  /// Показывать бегунок на границе сыгранного (полный плеер).
  final bool showHandle;

  /// Длительность трека — для плашки времени над ползунком во время драга.
  /// Без неё плашка не рисуется: врать «0:00» нельзя.
  final Duration? total;

  const TrackWaveform({
    super.key,
    required this.peaks,
    required this.progress,
    required this.color,
    this.height = 60,
    this.onSeek,
    this.showHandle = false,
    this.total,
  });

  @override
  State<TrackWaveform> createState() => _TrackWaveformState();
}

class _TrackWaveformState extends State<TrackWaveform> {
  /// Пока палец на волне, позиция берётся из драга, а не из плеера: сик
  /// доезжает с задержкой, и без этого ползунок дёргался бы назад.
  bool _dragging = false;
  double _dragFraction = 0;

  bool get _hasPeaks => widget.peaks != null && widget.peaks!.length > 4;

  double get _progress =>
      (_dragging ? _dragFraction : widget.progress).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final rest = AudioColors.waveRest(context);

    Widget body = _hasPeaks
        ? CustomPaint(
            size: Size.infinite,
            painter: _WavePainter(
              peaks: widget.peaks!,
              progress: _progress,
              played: widget.color,
              rest: rest,
            ),
          )
        : _FlatBar(progress: _progress, color: widget.color, rest: rest);

    if (widget.showHandle && _hasPeaks) {
      final bg = context.seeuColors.bg;
      final wave = body;
      body = LayoutBuilder(
        builder: (_, box) {
          final x = box.maxWidth * _progress;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: wave),
              // Тонкая линия позиции — сквозь всю высоту волны.
              Positioned(
                left: x - 1,
                top: -6,
                bottom: -6,
                child: Container(width: 2, color: widget.color),
              ),
              // Ползунок: кружок с бордером цвета фона — читается поверх
              // пиков и не сливается с сыгранной частью.
              Positioned(
                left: (x - 8).clamp(0.0, math.max(0.0, box.maxWidth - 16)),
                top: (widget.height - 16) / 2,
                child: IgnorePointer(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                      border: Border.all(color: bg, width: 3),
                    ),
                  ),
                ),
              ),
              // Плашка времени — только пока палец тянет волну.
              if (_dragging && widget.total != null)
                Positioned(
                  left: (x - 32).clamp(-12.0, math.max(0.0, box.maxWidth - 52)),
                  top: (widget.height - 16) / 2 - 28,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 64,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161310),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _clock(Duration(
                              milliseconds:
                                  ((widget.total!.inMilliseconds) * _progress)
                                      .round(),
                            )),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    if (widget.onSeek == null) {
      return SizedBox(height: widget.height, child: body);
    }

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (_, box) {
          double fractionAt(Offset local) => box.maxWidth <= 0
              ? 0.0
              : (local.dx / box.maxWidth).clamp(0.0, 1.0);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => widget.onSeek!(fractionAt(d.localPosition)),
            onHorizontalDragStart: (d) => setState(() {
              _dragging = true;
              _dragFraction = fractionAt(d.localPosition);
            }),
            onHorizontalDragUpdate: (d) {
              final f = fractionAt(d.localPosition);
              setState(() => _dragFraction = f);
              widget.onSeek!(f);
            },
            onHorizontalDragEnd: (_) {
              widget.onSeek!(_dragFraction);
              setState(() => _dragging = false);
            },
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            child: body,
          );
        },
      ),
    );
  }

  static String _clock(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }
}

class _WavePainter extends CustomPainter {
  final List<double> peaks;
  final double progress;
  final Color played;
  final Color rest;

  const _WavePainter({
    required this.peaks,
    required this.progress,
    required this.played,
    required this.rest,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || peaks.isEmpty) return;

    // Не рисуем 100 палок на 40 пикселях: прореживаем под реальную ширину.
    const barW = 3.0;
    const gap = 2.0;
    final fit = ((size.width + gap) / (barW + gap)).floor();
    final count = math.max(1, math.min(peaks.length, fit));
    final step = peaks.length / count;

    final w = (size.width - gap * (count - 1)) / count;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      // Берём максимум из окна — иначе прореживание съедает пики и волна
      // становится вялой.
      var v = 0.0;
      final from = (i * step).floor();
      final to = math.min(peaks.length, ((i + 1) * step).ceil());
      for (var j = from; j < to; j++) {
        v = math.max(v, peaks[j]);
      }
      v = v.clamp(0.06, 1.0);

      final h = math.max(2.0, v * size.height);
      final x = i * (w + gap);
      final y = (size.height - h) / 2;

      paint.color = (i / count) < progress ? played : rest;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.played != played ||
      old.rest != rest ||
      !identical(old.peaks, peaks);
}

/// Данных о волне нет — честная тонкая полоса вместо выдуманных пиков.
class _FlatBar extends StatelessWidget {
  final double progress;
  final Color color;
  final Color rest;

  const _FlatBar({
    required this.progress,
    required this.color,
    required this.rest,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: rest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: -4,
            bottom: -4,
            child: LayoutBuilder(
              builder: (_, box) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: box.maxWidth * progress - 6,
                    top: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Эквалайзер «сейчас играет» ─────────────────────────────────────────────

/// Три пляшущие палки — метка «этот трек звучит прямо сейчас».
class NowPlayingBars extends StatefulWidget {
  final Color color;
  final double height;

  const NowPlayingBars({super.key, required this.color, this.height = 12});

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            // Сдвиг фазы, чтобы палки не прыгали синхронно.
            final phase = (_c.value + i * 0.3) % 1.0;
            final k = 0.28 + 0.72 * (1 - (phase * 2 - 1).abs());
            return Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 2),
              child: Container(
                width: 2.5,
                height: widget.height * k,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─── Обложка трека ──────────────────────────────────────────────────────────

/// Обложка: настоящая картинка, а если её нет — плашка цветом категории с её
/// иконкой. Никаких серых квадратов.
class TrackCover extends StatelessWidget {
  final AudioTrack track;
  final double size;

  /// Высота, если обложка не квадратная (карточка трека — широкая, H230).
  final double? height;
  final double radius;

  /// Показать поверх обложки метку «играет сейчас».
  final bool playing;

  const TrackCover({
    super.key,
    required this.track,
    this.size = 48,
    this.height,
    this.radius = 11,
    this.playing = false,
  });

  /// Меньшая сторона — от неё считаются иконка-заглушка и эквалайзер,
  /// чтобы на широкой обложке они не разрастались.
  double get _side => math.min(size, height ?? size);

  @override
  Widget build(BuildContext context) {
    final cat = findCategory(track.category);
    final color = cat?.color ?? SeeUColors.accent;
    final mode = modeOf(track);

    return SizedBox(
      width: size,
      height: height ?? size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (track.coverUrl.isNotEmpty)
              Image.network(
                track.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(color, mode),
              )
            else
              _fallback(color, mode),
            if (playing)
              Container(
                color: const Color(0xFF140C08).withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: NowPlayingBars(
                  color: Colors.white,
                  height: _side * 0.22,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(Color color, ListenMode mode) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.38)!],
          ),
        ),
        child: Icon(
          mode.icon,
          size: _side * 0.42,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      );
}

// ─── Шапки ──────────────────────────────────────────────────────────────────

/// Шапка главной вкладки: кикер «АУДИОТЕКА», серифный заголовок и «Выйти».
class AudioMainBar extends StatelessWidget {
  final String title;
  final Widget? action;

  const AudioMainBar({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'АУДИОТЕКА',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: AudioColors.kicker(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeeUTypography.displayS.copyWith(
                    fontSize: 38,
                    height: 0.95,
                    letterSpacing: -1.4,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (action != null) ...[action!, const SizedBox(width: 8)],
          const AudioExitButton(),
        ],
      ),
    );
  }
}

/// «Выйти» — возврат в «Сервисы» и к обычному меню приложения.
class AudioExitButton extends StatelessWidget {
  const AudioExitButton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? SeeUColors.darkInk : SeeUColors.textPrimary;
    final fg = dark ? SeeUColors.textPrimary : c.bg;

    return Tappable.scaled(
      onTap: () => exitToServices(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.signOut, size: 13, color: fg),
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

/// Квадратная кнопка подстраницы («Назад», «Поделиться», «⋯») — 44px.
class AudioSquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const AudioSquareButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
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
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Icon(icon, size: 20, color: c.ink),
      ),
    );
  }
}

// ─── Скелетоны ──────────────────────────────────────────────────────────────

/// Скелетон списка треков: квадрат обложки 48 r11 + две полоски текста.
/// Повторяет вёрстку строк Аудиотеки и мерцает штатным шиммером — вместо
/// спиннера, который ничего не обещает.
class AudioListSkeleton extends StatelessWidget {
  final int rows;
  final EdgeInsetsGeometry padding;

  /// Необязательная шапка над строками (рисуется тем же шиммером) — для
  /// экранов, где над списком есть герой (плейлист, карточка).
  final Widget? header;

  const AudioListSkeleton({
    super.key,
    this.rows = 8,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        children: [
          if (header != null) ...[header!, const SizedBox(height: 20)],
          for (var i = 0; i < rows; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 15),
              child: Row(
                children: [
                  ShimmerBox(width: 48, height: 48, radius: 11),
                  SizedBox(width: 12),
                  Expanded(child: AudioSkeletonBars()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Две полоски «название + подпись» — кирпич для скелетонов Аудиотеки.
class AudioSkeletonBars extends StatelessWidget {
  const AudioSkeletonBars({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShimmerBox(width: 160, height: 13, radius: 4),
        SizedBox(height: 7),
        ShimmerBox(width: 96, height: 11, radius: 4),
      ],
    );
  }
}

// ─── Пунктирный бордер ──────────────────────────────────────────────────────

/// Настоящий dashed-бордер со скруглением («Новый плейлист», «Создать») —
/// из коробки Flutter умеет только сплошной.
class DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  const DashedRRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 1.5,
    this.dash = 6,
    this.gap = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}

// ─── Мелочи ─────────────────────────────────────────────────────────────────

/// «2:58» / «1 ч 42 м» — длинное и короткое читаются по-разному.
String formatDuration(int seconds) {
  if (seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return m == 0 ? '$h ч' : '$h ч $m м';
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// «осталось 22 мин» — для недослушанного.
String formatRemaining(int seconds) {
  if (seconds <= 0) return 'почти дослушано';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return 'осталось $h ч ${m > 0 ? '$m мин' : ''}'.trim();
  if (m < 1) return 'осталось меньше минуты';
  return 'осталось $m мин';
}

/// «48,2 тыс» — счётчики не должны рвать строку.
String formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0).replaceAll('.', ',')} тыс';
  }
  return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} млн';
}

/// Выход из сервиса: возврат в «Сервисы» — вместе с ним возвращается и обычное
/// нижнее меню приложения.
void exitToServices(BuildContext context) {
  HapticFeedback.lightImpact();
  context.go('/services');
}
