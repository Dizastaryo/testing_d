import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';
import 'audio_design.dart';

/// Режим «Момент» — мем. Трёхсекундному звуку не нужен экран-простыня: он
/// открывается шторкой поверх текущего места, сразу играет и предлагает ровно
/// два действия — повторить и взять в видео. Ни лайка-подвала, ни техданных:
/// за три секунды всё уже слышно.
Future<void> showMomentSheet(BuildContext context, AudioTrack track) {
  return showSeeUBottomSheet<void>(
    context: context,
    builder: (_) => _MomentSheet(track: track),
  );
}

class _MomentSheet extends ConsumerStatefulWidget {
  final AudioTrack track;
  const _MomentSheet({required this.track});

  @override
  ConsumerState<_MomentSheet> createState() => _MomentSheetState();
}

class _MomentSheetState extends ConsumerState<_MomentSheet> {
  @override
  void initState() {
    super.initState();
    // Шторка открылась — звук уже пошёл. Ждать тапа по «play» здесь незачем.
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  void _play() {
    ref.read(miniPlayerProvider.notifier).playWithQueue(
          track: widget.track,
          queue: [widget.track],
          index: 0,
          source: 'moment',
        );
  }

  void _repeat() {
    HapticFeedback.lightImpact();
    ref.read(miniPlayerProvider.notifier).seek(Duration.zero);
    _play();
  }

  void _useInVideo() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    // Мост в ленту SeeU: камера открывается с уже выбранным звуком.
    context.push('/post/create', extra: widget.track);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final t = widget.track;
    const mode = ListenMode.moment;

    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == t.id;
    final progress = isCurrent && (player.duration?.inMilliseconds ?? 0) > 0
        ? player.position.inMilliseconds / player.duration!.inMilliseconds
        : 0.0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TrackCover(track: t, size: 56, radius: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (t.subcategory.isNotEmpty) t.subcategory,
                          formatDuration(t.durationSeconds),
                        ].where((e) => e.isNotEmpty).join(' · '),
                        style: TextStyle(fontSize: 12, color: c.ink3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Петля вместо полосы прогресса: у мема нет «середины», к которой
            // хочется перемотать.
            TrackWaveform(
              peaks: t.waveformData,
              progress: progress,
              color: mode.color,
              height: 56,
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Tappable.scaled(
                    onTap: _repeat,
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIconsFill.repeat,
                              size: 17, color: c.ink2),
                          const SizedBox(width: 7),
                          Text(
                            'Повтор',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.ink2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 14,
                  child: Tappable.scaled(
                    onTap: _useInVideo,
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: mode.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIconsFill.videoCamera,
                              size: 17, color: Colors.white),
                          SizedBox(width: 7),
                          Text(
                            'Взять в видео',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
