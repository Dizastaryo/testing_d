import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/audio/audio_player_service.dart';
import '../core/design/design.dart';
import '../core/models/audio_track.dart';
import '../features/music/audio_design.dart';

/// Мини-плеер над нижним меню. Виден, когда есть активный трек, иначе —
/// `SizedBox.shrink()`. Тап — раскрытие в полноэкранный плеер.
///
/// Стиль: плотная карточка с коралловым оттенком (обложка слева, название и
/// артист в центре, play/pause и закрытие справа, тонкая полоса прогресса
/// снизу). Не стекло: панель под ним непрозрачная, контент туда не заезжает —
/// размывать нечего.
class SeeUMiniPlayer extends ConsumerWidget {
  const SeeUMiniPlayer({super.key, this.onTap});

  final VoidCallback? onTap;

  /// MUSIC-5: long-press → speed-picker. just_audio поддерживает setSpeed
  /// без EQ-аппаратной обработки. True EQ (band gain control) требует
  /// just_audio_effects (Android-only experimental) или native bridge —
  /// отдельная подзадача MUSIC-5.1.
  void _showSpeedSheet(BuildContext context, WidgetRef ref) {
    final current = ref.read(miniPlayerProvider).speed;
    showSeeUBottomSheet<void>(
      context: context,
      builder: (sheetCtx) {
        final c = sheetCtx.seeuColors;
        Widget option(String label, double speed) {
          final selected = (current - speed).abs() < 0.05;
          return ListTile(
            leading: Icon(PhosphorIcons.gauge(),
                color: selected ? SeeUColors.accent : c.ink2),
            title: Text(label,
                style: TextStyle(
                  color: selected ? SeeUColors.accent : c.ink,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                )),
            trailing: selected
                ? Icon(PhosphorIcons.check(), color: SeeUColors.accent)
                : null,
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              await ref.read(miniPlayerProvider.notifier).setSpeed(speed);
            },
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    Icon(PhosphorIcons.gauge(), color: SeeUColors.accent),
                    const SizedBox(width: 8),
                    Text('Скорость воспроизведения',
                        style: SeeUTypography.title),
                  ],
                ),
              ),
              option('0.75×', 0.75),
              option('1×', 1.0),
              option('1.25×', 1.25),
              option('1.5×', 1.5),
              option('2×', 2.0),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Здесь следим только за треком: состояние проигрывания и прогресс живут
    // в отдельных листовых виджетах, чтобы карточка не перерисовывалась на
    // каждый тик позиции.
    final track = ref.watch(miniPlayerProvider.select((s) => s.track));
    if (track == null) return const SizedBox.shrink();

    final c = context.seeuColors;

    // Эталон «Аудиотека F»: белый бар во всю ширину, линия сверху,
    // прогресс 2px СВЕРХУ, кавер 44 r10 с эквалайзером, play 40 чёрный.
    // Жесты: тап/свайп вверх — полный плеер; свайп вниз — свернуть.
    return GestureDetector(
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          onTap?.call(); // свайп вверх → полный плеер
        } else if (v > 200) {
          ref.read(miniPlayerProvider.notifier).close(); // вниз → свернуть
        }
      },
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line, width: 1)),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: 0.30),
              blurRadius: 24,
              spreadRadius: -12,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: () => _showSpeedSheet(context, ref),
            child: Stack(
              children: [
                // Контент: cover, title, controls
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      _Cover(track: track),
                      const SizedBox(width: 11),
                      Expanded(child: _TitleArtist(track: track)),
                      const _PlayPauseBtn(),
                      _ContextAction(track: track),
                    ],
                  ),
                ),
                // Тонкая progress-полоска СВЕРХУ (эталон F).
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _MiniProgressBar(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Один контекстный элемент — и только там, где он честно нужен.
///
/// Мини-плеер виден во всём SeeU, поэтому дисциплина жёсткая: он не пульт.
/// У разговора вместо «закрыть» полезнее «+30 секунд» (промотать рекламу или
/// затянутое место, не открывая плеер), у мема — «повторить». В остальном —
/// закрытие.
class _ContextAction extends ConsumerWidget {
  const _ContextAction({required this.track});
  final AudioTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = modeOf(track);

    switch (mode) {
      case ListenMode.talk:
        return Tappable.scaled(
          onTap: () {
            HapticFeedback.lightImpact();
            final pos = ref.read(miniPlayerProvider).position;
            ref
                .read(miniPlayerProvider.notifier)
                .seek(pos + Duration(seconds: mode.skipSeconds));
          },
          child: SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(PhosphorIcons.arrowClockwise(),
                    size: 20, color: mode.color),
                Text(
                  '${mode.skipSeconds}',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    color: mode.color,
                  ),
                ),
              ],
            ),
          ),
        );

      case ListenMode.moment:
        return Tappable.scaled(
          onTap: () {
            HapticFeedback.lightImpact();
            final notifier = ref.read(miniPlayerProvider.notifier);
            notifier.seek(Duration.zero);
            // Мем — одиночная очередь: доиграв, он в состоянии completed
            // (playing == false), и один seek(0) звук не возобновляет. Если
            // не играет — досылаем toggle, чтобы «повтор» реально зазвучал.
            if (!ref.read(miniPlayerProvider).playing) {
              notifier.toggle();
            }
          },
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(PhosphorIconsFill.repeat, size: 19, color: mode.color),
          ),
        );

      case ListenMode.song:
      case ListenMode.book:
        return Tappable.scaled(
          onTap: () => ref.read(miniPlayerProvider.notifier).close(),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: Icon(
                PhosphorIcons.x(),
                size: 18,
                color: SeeUColors.textSecondary,
              ),
            ),
          ),
        );
    }
  }
}

/// Кавер 44 r10 с эквалайзер-оверлеем (3 полоски), когда трек играет —
/// эталон «Аудиотека F».
class _Cover extends ConsumerWidget {
  const _Cover({required this.track});
  final AudioTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final playing = ref.watch(miniPlayerProvider.select((s) => s.playing));
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          fit: StackFit.expand,
          children: [
            track.coverUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: track.coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: c.surface2),
                    errorWidget: (_, __, ___) =>
                        Container(color: c.surface2),
                  )
                : Container(
                    color: c.surface2,
                    child:
                        Icon(PhosphorIcons.musicNotes(), color: c.ink3),
                  ),
            if (playing)
              Container(
                color: const Color(0xFF140C08).withValues(alpha: 0.35),
                alignment: Alignment.bottomCenter,
                padding: const EdgeInsets.only(bottom: 7),
                child: NowPlayingBars(color: Colors.white, height: 9),
              ),
          ],
        ),
      ),
    );
  }
}

class _TitleArtist extends ConsumerWidget {
  const _TitleArtist({required this.track});
  final AudioTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    // MUSIC-2: если у трека есть lyrics — показываем текущую строку вместо
    // artist в subtitle (italic, accent для эффекта sing-along).
    final positionMs = ref.watch(
        miniPlayerProvider.select((s) => s.position.inMilliseconds));
    final playing = ref.watch(miniPlayerProvider.select((s) => s.playing));
    final lines = parseLrcCached(track.id, track.lyricsLrc);
    final cur = lines.isEmpty ? null : currentLyricAt(lines, positionMs);
    final hasLyric = cur != null && cur.text.isNotEmpty && playing;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SeeUTypography.subtitle.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: 2),
        Text(
          hasLyric ? cur.text : track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SeeUTypography.caption.copyWith(
            color: hasLyric ? SeeUColors.accent : c.ink2,
            fontSize: 12,
            fontStyle: hasLyric ? FontStyle.italic : FontStyle.normal,
            fontWeight: hasLyric ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

/// Bottom progress bar — isolated leaf so the per-tick position updates don't
/// rebuild the blurred glass card above it.
class _MiniProgressBar extends ConsumerWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(miniPlayerProvider.select((s) {
      final d = s.duration;
      if (d == null || d.inMilliseconds <= 0) return 0.0;
      return (s.position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
    }));
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: SeeUColors.accent.withValues(alpha: 0.15),
        valueColor: const AlwaysStoppedAnimation(SeeUColors.accent),
      ),
    );
  }
}

class _PlayPauseBtn extends ConsumerWidget {
  const _PlayPauseBtn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(miniPlayerProvider.select((s) => s.playing));
    final c = context.seeuColors;
    // §F: play/pause — чёрный круг 40 (в тёмной теме — светлый).
    return GestureDetector(
      onTap: () => ref.read(miniPlayerProvider.notifier).toggle(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.ink,
        ),
        child: Center(
          child: Icon(
            playing
                ? PhosphorIcons.pause(PhosphorIconsStyle.fill)
                : PhosphorIcons.play(PhosphorIconsStyle.fill),
            color: c.bg,
            size: 19,
          ),
        ),
      ),
    );
  }
}

/// Persistent mini-player bar for Scaffold.bottomNavigationBar on screens
/// that live outside the main ShellRoute (no bottom nav).
/// Returns SizedBox.shrink() when no track is active.
class SeeUMiniPlayerBar extends ConsumerWidget {
  const SeeUMiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(miniPlayerProvider.select((s) => s.track));
    if (track == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0, 6, 0, MediaQuery.of(context).padding.bottom + 6,
      ),
      child: SeeUMiniPlayer(
        onTap: () => context.push('/music/player'),
      ),
    );
  }
}
