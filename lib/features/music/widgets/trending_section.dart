import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/audio/audio_player_service.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';

class TrendingSection extends ConsumerWidget {
  final List<AudioTrack> tracks;
  const TrendingSection({super.key, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = tracks.take(10).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SeeUSectionHeader(
            kicker: 'ЧАРТ',
            title: 'Тренды',
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          ),
          ...top.asMap().entries.map(
                (e) => _TrendingTile(
                  track: e.value,
                  rank: e.key + 1,
                  queue: tracks,
                ),
              ),
        ],
      ),
    );
  }
}

class _TrendingTile extends ConsumerWidget {
  final AudioTrack track;
  final int rank;
  final List<AudioTrack> queue;

  const _TrendingTile({
    required this.track,
    required this.rank,
    required this.queue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;
    final isPlaying = isCurrent && player.playing;

    return InkWell(
      onTap: () {
        final idx = queue.indexWhere((t) => t.id == track.id);
        ref.read(miniPlayerProvider.notifier).playWithQueue(
              track: track,
              queue: queue,
              index: idx >= 0 ? idx : 0,
              source: 'trending',
            );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: rank <= 3 ? 16 : 13,
                  fontWeight:
                      rank <= 3 ? FontWeight.w800 : FontWeight.w500,
                  color: rank == 1
                      ? SeeUColors.medalGold
                      : rank == 2
                          ? SeeUColors.medalSilver
                          : rank == 3
                              ? SeeUColors.medalBronze
                              : c.ink3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: track.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      )
                    : Container(
                        color: c.surface2,
                        child: Icon(PhosphorIcons.musicNote(),
                            color: c.ink3, size: 18),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.displayArtist,
                          style: TextStyle(fontSize: 12, color: c.ink2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (track.playsCount > 0) ...[
                        Text('  ·  ',
                            style: TextStyle(color: c.ink3, fontSize: 12)),
                        Icon(PhosphorIcons.play(), size: 10, color: c.ink3),
                        const SizedBox(width: 2),
                        Text(
                          _fmt(track.playsCount),
                          style: TextStyle(
                            fontSize: 11,
                            color: c.ink3,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              color: isCurrent ? SeeUColors.accent : c.ink2,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}
