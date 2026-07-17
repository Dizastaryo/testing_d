import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';
import '../../widgets/report_sheet.dart';
import 'audio_design.dart';
import 'lyrics_screen.dart';
import 'queue_sheet.dart';
import 'sleep_timer.dart';

/// Полноэкранный плеер.
///
/// Каркас общий — обложка сверху, транспорт снизу, — но **пульт меняется по
/// режиму**: у песни на виду шаффл, повтор и волна-перемотка; у разговора и
/// книги ±30/±15 секунд стали крупными боковыми кнопками, скорость вынесена
/// на линию, шаффл убран, добавлен таймер сна. Второй ряд действий уходит под
/// линию — чтобы не получилась свалка иконок.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final track = player.track;

    if (track == null) {
      // Трек кончился, пока плеер был открыт, — не держим пустой экран.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.pop();
      });
      return const SizedBox.shrink();
    }

    final mode = modeOf(track);

    return Scaffold(
      backgroundColor: c.bg,
      body: Container(
        // Верх окрашен цветом режима — сразу видно, что именно ты слушаешь.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(mode.color.withValues(alpha: 0.14), c.bg),
              c.bg,
            ],
            stops: const [0.0, 0.42],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              children: [
                _TopBar(track: track, mode: mode),
                const Spacer(flex: 2),
                _Cover(track: track, mode: mode),
                const SizedBox(height: 24),
                _TitleRow(track: track, mode: mode),
                const Spacer(flex: 2),
                _Scrubber(track: track, mode: mode),
                const SizedBox(height: 16),
                _Transport(track: track, mode: mode),
                const SizedBox(height: 22),
                _SecondaryRow(track: track, mode: mode),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Шапка ──────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  final AudioTrack track;
  final ListenMode mode;

  const _TopBar({required this.track, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    return Row(
      children: [
        Tappable(
          onTap: () => context.pop(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(PhosphorIcons.caretDown(), size: 24, color: c.ink2),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                mode == ListenMode.talk ? 'ПОДКАСТ' : 'ИГРАЕТ ИЗ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: c.ink3,
                ),
              ),
              const SizedBox(height: 2),
              Consumer(
                builder: (_, ref, __) {
                  final src = ref.watch(miniPlayerProvider).queueSource;
                  return Text(
                    _sourceLabel(src, track),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Tappable(
          // Раньше «три точки» ОТКРЫВАЛИ страницу трека (/music/track/:id) —
          // почти такую же полноэкранную страницу, что путало («открылась та же
          // страница, другие кнопки»). Теперь это нормальное меню; страница
          // трека доступна из него явным пунктом «Подробнее о треке».
          onTap: () => _moreSheet(context, ref),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(PhosphorIcons.dotsThree(), size: 22, color: c.ink2),
          ),
        ),
      ],
    );
  }

  static String _sourceLabel(String src, AudioTrack track) => switch (src) {
        'daily_mix' => 'Твой день',
        'playlist' => 'Плейлист',
        'saved' => 'Сохранённое',
        'recent' => 'Недавнее',
        'trending' => 'Набирают',
        'search' => 'Поиск',
        'category' => 'Категория',
        'continue' => 'Продолжить',
        _ => track.artist.isNotEmpty ? track.artist : 'Аудиотека',
      };

  /// Меню «ещё» (три точки). Не открывает дубль-страницу трека, а даёт
  /// действия; страница трека доступна отдельным явным пунктом.
  void _moreSheet(BuildContext context, WidgetRef ref) {
    showSeeUBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(PhosphorIcons.info(), color: c.ink2),
                title: const Text('Подробнее о треке'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/music/track/${track.id}');
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.link(), color: c.ink2),
                title: const Text('Скопировать ссылку'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(
                      ClipboardData(text: 'seeu://track/${track.id}'));
                  showSeeUSnackBar(context, 'Ссылка скопирована');
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.flag(), color: SeeUColors.like),
                title: const Text('Пожаловаться'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showReportSheet(
                    context: context,
                    ref: ref,
                    targetType: 'track',
                    targetId: track.id,
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}

// ─── Обложка ────────────────────────────────────────────────────────────────

class _Cover extends StatelessWidget {
  final AudioTrack track;
  final ListenMode mode;

  const _Cover({required this.track, required this.mode});

  @override
  Widget build(BuildContext context) {
    // У разговора обложка меньше: там важнее текст и пульт, а не картинка.
    final size = mode == ListenMode.talk ? 236.0 : 300.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: mode.color.withValues(alpha: 0.55),
            blurRadius: 60,
            offset: const Offset(0, 30),
            spreadRadius: -22,
          ),
        ],
      ),
      child: Stack(
        children: [
          TrackCover(track: track, size: size, radius: 24),
          // Косой световой блик — обложка не выглядит наклейкой.
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.30),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.44],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Название + лайк ────────────────────────────────────────────────────────

class _TitleRow extends ConsumerStatefulWidget {
  final AudioTrack track;
  final ListenMode mode;

  const _TitleRow({required this.track, required this.mode});

  @override
  ConsumerState<_TitleRow> createState() => _TitleRowState();
}

class _TitleRowState extends ConsumerState<_TitleRow> {
  late bool _liked = widget.track.isLikedByMe;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _TitleRow old) {
    super.didUpdateWidget(old);
    // _TitleRow строится без key, так что при автопереходе/скипе State
    // переиспользуется — а _liked seed'ился один раз и показывал состояние
    // прошлого трека. Пересеваем при смене трека.
    if (old.track.id != widget.track.id) {
      _liked = widget.track.isLikedByMe;
      _busy = false;
    }
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _liked = !_liked;
    });
    HapticFeedback.lightImpact();
    try {
      final api = ref.read(apiClientProvider);
      if (_liked) {
        await api.post(ApiEndpoints.audioTrackLike(widget.track.id));
      } else {
        await api.delete(ApiEndpoints.audioTrackLike(widget.track.id));
      }
      // Плеер держит свою копию трека — её тоже надо поправить, иначе сердце
      // «отскочит» назад при следующей перерисовке.
      ref.read(miniPlayerProvider.notifier).setCurrentLiked(_liked);
    } catch (_) {
      if (mounted) setState(() => _liked = !_liked);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final t = widget.track;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeeUTypography.displayS.copyWith(
                  fontSize: widget.mode == ListenMode.talk ? 22 : 26,
                  height: 1.05,
                  color: c.ink,
                ),
              ),
              if (t.artist.isNotEmpty) ...[
                const SizedBox(height: 3),
                // Автор — строка, а не сущность: тап ведёт в поиск по имени.
                Tappable(
                  onTap: () => context.push(
                      '/music/search?q=${Uri.encodeComponent(t.artist)}'),
                  child: Text(
                    t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.ink2),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Tappable.scaled(
          onTap: _toggleLike,
          child: Icon(
            _liked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
            size: 30,
            color: _liked ? SeeUColors.like : c.ink3,
          ),
        ),
      ],
    );
  }
}

// ─── Перемотка по волне ─────────────────────────────────────────────────────

class _Scrubber extends ConsumerWidget {
  final AudioTrack track;
  final ListenMode mode;

  const _Scrubber({required this.track, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final total = player.duration ?? Duration(seconds: track.durationSeconds);
    final pos = player.position;
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Column(
      children: [
        TrackWaveform(
          peaks: track.waveformData,
          progress: progress,
          color: mode.color,
          height: mode == ListenMode.talk ? 64 : 110,
          showHandle: true,
          // Длительность — для плашки времени над ползунком во время драга.
          total: total,
          onSeek: (f) {
            HapticFeedback.selectionClick();
            ref.read(miniPlayerProvider.notifier).seek(
                  Duration(
                      milliseconds: (total.inMilliseconds * f).round()),
                );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _clock(pos),
              style: TextStyle(fontSize: 11, color: c.ink3),
            ),
            Text(
              '-${_clock(total - pos)}',
              style: TextStyle(fontSize: 11, color: c.ink3),
            ),
          ],
        ),
      ],
    );
  }

  static String _clock(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

// ─── Транспорт ──────────────────────────────────────────────────────────────

class _Transport extends ConsumerWidget {
  final AudioTrack track;
  final ListenMode mode;

  const _Transport({required this.track, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final notifier = ref.read(miniPlayerProvider.notifier);
    // У разговора и книги вместо шаффла/повтора — крупная перемотка на ±N сек.
    final skipping = mode.resumable;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (skipping)
          _SkipButton(
            seconds: mode.skipSeconds,
            forward: false,
            onTap: () => notifier.seek(
                player.position - Duration(seconds: mode.skipSeconds)),
          )
        else
          Tappable.scaled(
            onTap: () {
              HapticFeedback.selectionClick();
              notifier.toggleShuffle();
            },
            child: Icon(
              PhosphorIcons.shuffle(),
              size: 22,
              color: player.shuffle ? mode.color : c.ink2,
            ),
          ),

        // ⏮ активна всегда, когда есть трек: previous() сам решает — при >3с
        // перезапустить текущий, иначе шагнуть назад / встать на 0. Раньше на
        // первом треке кнопка была серой и перезапуск был недостижим.
        Tappable.scaled(
          onTap: notifier.previous,
          child: Icon(
            PhosphorIconsFill.skipBack,
            size: skipping ? 26 : 30,
            color: c.ink,
          ),
        ),

        Tappable.scaled(
          onTap: () {
            HapticFeedback.lightImpact();
            notifier.toggle();
          },
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mode.color,
              boxShadow: [
                BoxShadow(
                  color: mode.color.withValues(alpha: 0.7),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Icon(
              player.playing ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              size: 34,
              color: Colors.white,
            ),
          ),
        ),

        Tappable.scaled(
          onTap: player.hasNext ? notifier.next : null,
          child: Icon(
            PhosphorIconsFill.skipForward,
            size: skipping ? 26 : 30,
            color: player.hasNext ? c.ink : c.ink4,
          ),
        ),

        if (skipping)
          _SkipButton(
            seconds: mode.skipSeconds,
            forward: true,
            onTap: () => notifier.seek(
                player.position + Duration(seconds: mode.skipSeconds)),
          )
        else
          Tappable.scaled(
            onTap: () {
              HapticFeedback.selectionClick();
              notifier.cycleRepeat();
            },
            child: Icon(
              player.repeat == PlayerRepeatMode.one
                  ? PhosphorIcons.repeatOnce()
                  : PhosphorIcons.repeat(),
              size: 22,
              color:
                  player.repeat == PlayerRepeatMode.off ? c.ink2 : mode.color,
            ),
          ),
      ],
    );
  }
}

class _SkipButton extends StatelessWidget {
  final int seconds;
  final bool forward;
  final VoidCallback onTap;

  const _SkipButton({
    required this.seconds,
    required this.forward,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              forward
                  ? PhosphorIcons.arrowClockwise()
                  : PhosphorIcons.arrowCounterClockwise(),
              size: 30,
              color: c.ink2,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '$seconds',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: c.ink3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Второй ряд ─────────────────────────────────────────────────────────────

class _SecondaryRow extends ConsumerWidget {
  final AudioTrack track;
  final ListenMode mode;

  const _SecondaryRow({required this.track, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    // Закладка берётся из копии трека в плеере: setCurrentSaved обновляет её,
    // и иконка не «отскакивает» при следующей перерисовке.
    final saved = player.track?.id == track.id
        ? (player.track?.isSavedByMe ?? track.isSavedByMe)
        : track.isSavedByMe;

    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Скорость: у разговора она на виду пилюлей, у песни — просто цифра.
          if (mode.resumable)
            Tappable.scaled(
              onTap: () => _speedSheet(context, ref),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
                decoration: BoxDecoration(
                  color: mode.soft(context),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: mode.color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _speedLabel(player.speed),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: mode.color,
                  ),
                ),
              ),
            )
          else
            _action(
              context,
              label: 'скорость',
              child: Text(
                _speedLabel(player.speed),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.ink2,
                ),
              ),
              onTap: () => _speedSheet(context, ref),
            ),

          // Таймер сна — для книги и медитации. Экран гаснет, звук выключится сам.
          if (mode == ListenMode.book)
            _action(
              context,
              label: 'таймер',
              icon: PhosphorIcons.moon(),
              active: ref.watch(sleepTimerProvider) != null,
              onTap: () => showSleepTimerSheet(context),
            ),

          // Текст песни — только если он есть. Пустая кнопка хуже отсутствующей.
          if (track.lyricsLrc.isNotEmpty)
            _action(
              context,
              label: 'текст',
              icon: PhosphorIcons.textAlignLeft(),
              onTap: () => showLyricsScreen(context),
            ),

          _action(
            context,
            label: 'очередь',
            icon: PhosphorIcons.listBullets(),
            onTap: () => showQueueSheet(context),
          ),

          // §E: «сохранить» — на нижней линии обоих режимов (песня/разговор).
          _action(
            context,
            label: 'сохранить',
            icon: saved
                ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                : PhosphorIcons.bookmarkSimple(),
            active: saved,
            onTap: () async {
              HapticFeedback.lightImpact();
              try {
                final api = ref.read(apiClientProvider);
                if (!saved) {
                  await api.post(ApiEndpoints.audioTrackSave(track.id));
                } else {
                  await api.delete(ApiEndpoints.audioTrackSave(track.id));
                }
                ref.read(miniPlayerProvider.notifier).setCurrentSaved(!saved);
              } catch (_) {/* best-effort */}
            },
          ),

          _action(
            context,
            label: 'поделиться',
            icon: PhosphorIcons.shareNetwork(),
            onTap: () => Share.share(
              '${track.title}${track.artist.isNotEmpty ? ' — ${track.artist}' : ''}'
              '\n\nseeu://track/${track.id}',
              subject: track.title,
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required String label,
    IconData? icon,
    Widget? child,
    bool active = false,
    required VoidCallback onTap,
  }) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            child: child ??
                Icon(
                  icon,
                  size: 22,
                  color: active ? mode.color : c.ink2,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: active ? mode.color : c.ink3,
            ),
          ),
        ],
      ),
    );
  }

  static String _speedLabel(double s) {
    final v = s.toStringAsFixed(2);
    if (v.endsWith('00')) return '${s.toInt()}×';
    if (v.endsWith('0')) return '${v.substring(0, v.length - 1)}×';
    return '$v×';
  }

  void _speedSheet(BuildContext context, WidgetRef ref) {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final current = ref.read(miniPlayerProvider).speed;

    showSeeUBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                child: Text(
                  'Скорость',
                  style: SeeUTypography.displayS
                      .copyWith(fontSize: 22, color: c.ink),
                ),
              ),
              for (final s in speeds)
                ListTile(
                  leading: Icon(
                    (current - s).abs() < 0.05
                        ? PhosphorIconsFill.checkCircle
                        : PhosphorIcons.circle(),
                    color:
                        (current - s).abs() < 0.05 ? mode.color : c.ink4,
                  ),
                  title: Text(
                    _speedLabel(s),
                    style: TextStyle(
                      fontWeight: (current - s).abs() < 0.05
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: c.ink,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ref.read(miniPlayerProvider.notifier).setSpeed(s);
                  },
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}
