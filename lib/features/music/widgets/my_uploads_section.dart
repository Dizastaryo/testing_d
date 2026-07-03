import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/audio/audio_player_service.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';
import '../../../core/providers/audio_provider.dart';
import '../../../core/services/logger.dart';

/// Tracks uploaded by the current user (with moderation status). Renders
/// nothing while the list is empty, and — per the P1 fix — a compact inline
/// retry instead of silently disappearing when the fetch fails.
class MyUploadsSection extends ConsumerWidget {
  const MyUploadsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(myTracksProvider);

    if (async.hasError && !async.hasValue) {
      appLog.error('myTracksProvider failed', async.error);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SeeUSectionHeader(
              kicker: 'ЗАГРУЗКИ',
              title: 'Мои треки',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Не удалось загрузить ваши треки',
                    style: SeeUTypography.caption.copyWith(color: c.ink3),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: SeeUColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => ref.invalidate(myTracksProvider),
                  child: const Text('Повторить', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final list = async.value ?? const <AudioTrack>[];
    if (list.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SeeUSectionHeader(
            kicker: 'ЗАГРУЗКИ',
            title: 'Мои треки',
            padding: EdgeInsets.zero,
            action: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: SeeUColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => context.push('/music/mine'),
              child: const Text('Все →', style: TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 8),
          ...list.map((t) => _MyTrackTile(track: t)),
        ],
      ),
    );
  }
}

class _MyTrackTile extends ConsumerWidget {
  final AudioTrack track;
  const _MyTrackTile({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final (label, color) = switch (track.status) {
      'pending' => ('На модерации', SeeUColors.warning),
      'rejected' => ('Отклонён', SeeUColors.error),
      _ => ('Опубликован', SeeUColors.success),
    };
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;
    final isPlaying = isCurrent && player.playing;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          if (isCurrent) {
            ref.read(miniPlayerProvider.notifier).toggle();
          } else {
            ref.read(miniPlayerProvider.notifier).playWithQueue(
                track: track, queue: [track], index: 0, source: 'my_tracks');
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
                          color: c.surface2,
                          child: Icon(PhosphorIcons.musicNotesSimple(),
                              color: c.ink3, size: 18),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.ink2)),
                    if (track.status == 'rejected' &&
                        track.rejectionReason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(track.rejectionReason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                color: SeeUColors.error,
                                fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
              Icon(
                isPlaying
                    ? PhosphorIconsFill.pauseCircle
                    : PhosphorIconsFill.playCircle,
                color: isCurrent ? SeeUColors.accent : c.ink3,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
