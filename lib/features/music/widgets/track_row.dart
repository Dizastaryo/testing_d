import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/audio/audio_player_service.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';
import '../audio_design.dart';
import '../moment_sheet.dart';

/// Строка трека — базовый кирпич всех списков Аудиотеки.
///
/// Тап запускает трек с очередью того списка, из которого его открыли: играть
/// один трек в вакууме — не то, чего человек ждёт от ленты. Мем открывается
/// шторкой (режим «Момент»), а не экраном-простынёй.
class TrackRow extends ConsumerWidget {
  final AudioTrack track;

  /// Очередь, в которую попадёт плеер при тапе. Обычно — весь список секции.
  final List<AudioTrack> queue;
  final int index;
  final String source;

  /// Что показать справа: лайк, закладку, время или ничего.
  final TrackRowTrailing trailing;

  /// Открывать карточку вместо запуска (например, в выдаче поиска мы всё-таки
  /// играем, а вот в «Моих загрузках» — открываем).
  final VoidCallback? onTap;

  /// Список зовёт это после того, как пользователь лайкнул/сохранил трейлингом
  /// (например, вкладка «Сохранённое» инвалидирует свой провайдер, чтобы
  /// снятый трек исчез из списка).
  final VoidCallback? onChanged;

  const TrackRow({
    super.key,
    required this.track,
    this.queue = const [],
    this.index = 0,
    this.source = 'feed',
    this.trailing = TrackRowTrailing.like,
    this.onTap,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;
    final mode = modeOf(track);

    return Tappable.scaled(
      onTap: onTap ?? () => _play(context, ref),
      onLongPress: () => context.push('/music/track/${track.id}'),
      child: Row(
        children: [
          TrackCover(
            track: track,
            size: 48,
            playing: isCurrent && player.playing,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? mode.color : c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _trailing(context, ref, c),
        ],
      ),
    );
  }

  String get _subtitle {
    final parts = <String>[
      if (track.artist.isNotEmpty) track.artist,
      if (track.durationSeconds > 0) formatDuration(track.durationSeconds),
    ];
    return parts.isEmpty ? track.formatLabel : parts.join(' · ');
  }

  Widget _trailing(BuildContext context, WidgetRef ref, SeeUThemeColors c) {
    switch (trailing) {
      case TrackRowTrailing.like:
        // Сердце/закладка раньше были декоративными — тап уходил в строку и
        // запускал трек вместо лайка, а из «Сохранённого» трек нельзя было
        // снять вообще. Теперь трейлинг интерактивный и оптимистичный.
        return _TrailingToggle(track: track, isLike: true, onChanged: onChanged);
      case TrackRowTrailing.saved:
        return _TrailingToggle(
            track: track, isLike: false, onChanged: onChanged);
      case TrackRowTrailing.play:
        return Icon(
          PhosphorIconsFill.playCircle,
          size: 26,
          color: SeeUColors.accent,
        );
      case TrackRowTrailing.time:
        final t = track.playedAt;
        return Text(
          t == null
              ? ''
              : '${t.hour.toString().padLeft(2, '0')}:'
                  '${t.minute.toString().padLeft(2, '0')}',
          style: TextStyle(fontSize: 11.5, color: c.ink4),
        );
      case TrackRowTrailing.none:
        return const SizedBox.shrink();
    }
  }

  void _play(BuildContext context, WidgetRef ref) {
    // Мему не нужен экран-простыня: он открывается шторкой и сразу играет.
    if (modeOf(track) == ListenMode.moment) {
      showMomentSheet(context, track);
      return;
    }
    final q = queue.isEmpty ? [track] : queue;
    ref.read(miniPlayerProvider.notifier).playWithQueue(
          track: track,
          queue: q,
          index: queue.isEmpty ? 0 : index,
          source: source,
        );
  }
}

/// Интерактивный трейлинг «лайк/сохранить» с оптимистичным состоянием.
/// [isLike] true → лайк, false → сохранение. Синхронизирует плеерную копию,
/// если это текущий трек, и зовёт [onChanged] (список может обновиться).
class _TrailingToggle extends ConsumerStatefulWidget {
  final AudioTrack track;
  final bool isLike;
  final VoidCallback? onChanged;
  const _TrailingToggle({
    required this.track,
    required this.isLike,
    this.onChanged,
  });

  @override
  ConsumerState<_TrailingToggle> createState() => _TrailingToggleState();
}

class _TrailingToggleState extends ConsumerState<_TrailingToggle> {
  late bool _active = _initial;
  bool _busy = false;

  bool get _initial =>
      widget.isLike ? widget.track.isLikedByMe : widget.track.isSavedByMe;

  @override
  void didUpdateWidget(covariant _TrailingToggle old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) _active = _initial;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _active = !_active;
    });
    HapticFeedback.lightImpact();
    final api = ref.read(apiClientProvider);
    final ep = widget.isLike
        ? ApiEndpoints.audioTrackLike(widget.track.id)
        : ApiEndpoints.audioTrackSave(widget.track.id);
    try {
      if (_active) {
        await api.post(ep);
      } else {
        await api.delete(ep);
      }
      // Держим плеерную копию в синхроне, если это играющий трек.
      final cur = ref.read(miniPlayerProvider).track;
      if (cur?.id == widget.track.id) {
        if (widget.isLike) {
          ref.read(miniPlayerProvider.notifier).setCurrentLiked(_active);
        } else {
          ref.read(miniPlayerProvider.notifier).setCurrentSaved(_active);
        }
      }
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) setState(() => _active = !_active);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final IconData icon;
    final Color color;
    if (widget.isLike) {
      icon = _active ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart;
      color = _active ? SeeUColors.like : c.ink4;
    } else {
      icon = _active
          ? PhosphorIconsFill.bookmarkSimple
          : PhosphorIconsRegular.bookmarkSimple;
      color = _active ? SeeUColors.accent : c.ink4;
    }
    return Tappable.scaled(
      onTap: _busy ? null : _toggle,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 21, color: color),
      ),
    );
  }
}

enum TrackRowTrailing { like, saved, play, time, none }

extension on AudioTrack {
  String get formatLabel =>
      extension.isNotEmpty ? extension.toUpperCase() : 'АУДИО';
}
