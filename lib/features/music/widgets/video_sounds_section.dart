import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/audio/audio_player_service.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';

class VideoSoundsSection extends ConsumerWidget {
  final List<AudioTrack> tracks;
  const VideoSoundsSection({super.key, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SeeUSectionHeader(
            kicker: 'ДЛЯ REELS',
            title: 'Звуки для видео',
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          ),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _VideoSoundCard(
                track: tracks[i],
                queue: tracks,
                index: i,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoSoundCard extends ConsumerWidget {
  final AudioTrack track;
  final List<AudioTrack> queue;
  final int index;

  const _VideoSoundCard({
    required this.track,
    required this.queue,
    required this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;

    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: isCurrent
            ? Border.all(color: SeeUColors.accent, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () =>
                    ref.read(miniPlayerProvider.notifier).playWithQueue(
                          track: track,
                          queue: queue,
                          index: index,
                          source: 'video_sounds',
                        ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: track.coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: track.coverUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Container(color: c.surface2),
                          )
                        : Container(
                            color: SeeUColors.accent.withValues(alpha: 0.15),
                            child: Icon(PhosphorIcons.videoCamera(),
                                size: 18, color: SeeUColors.accent),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? SeeUColors.accent : c.ink,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
