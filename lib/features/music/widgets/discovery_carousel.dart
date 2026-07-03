import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/audio/audio_player_service.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';

/// Horizontal carousel for a list of tracks with a section header. Reused by
/// every discovery row on the audiotheque screen (мемы, новинки, …).
class DiscoveryTrackCarousel extends ConsumerWidget {
  final String title;
  final String kicker;
  final List<AudioTrack> tracks;
  final String source;
  final VoidCallback? onSeeAll;

  const DiscoveryTrackCarousel({
    super.key,
    required this.title,
    required this.kicker,
    required this.tracks,
    required this.source,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SeeUSectionHeader(
            kicker: kicker,
            title: title,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            action: onSeeAll != null
                ? TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: SeeUColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: onSeeAll,
                    child: const Text('Все →', style: TextStyle(fontSize: 13)),
                  )
                : null,
          ),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _TrackCard(
                track: tracks[i],
                queue: tracks,
                index: i,
                source: source,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCard extends ConsumerWidget {
  final AudioTrack track;
  final List<AudioTrack> queue;
  final int index;
  final String source;

  const _TrackCard({
    required this.track,
    required this.queue,
    required this.index,
    required this.source,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;

    return GestureDetector(
      onTap: () => ref.read(miniPlayerProvider.notifier).playWithQueue(
            track: track,
            queue: queue,
            index: index,
            source: source,
          ),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: isCurrent
              ? Border.all(color: SeeUColors.accent, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
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
                        color: SeeUColors.accent.withValues(alpha: 0.15),
                        child: Icon(PhosphorIcons.musicNote(),
                            size: 18, color: SeeUColors.accent),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.ink3),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(PhosphorIcons.heart(), size: 10, color: c.ink3),
                      const SizedBox(width: 3),
                      Text('${track.likesCount}',
                          style: TextStyle(
                              fontSize: 10,
                              color: c.ink3,
                              fontFamily: 'JetBrains Mono')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
