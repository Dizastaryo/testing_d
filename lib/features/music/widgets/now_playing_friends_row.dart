import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/audio/audio_player_service.dart';
import '../../../core/design/design.dart';

/// MUSIC-1: horizontal row друзей которые сейчас слушают музыку.
/// Появляется только когда есть активные слушатели среди подписок.
class NowPlayingFriendsRow extends ConsumerWidget {
  const NowPlayingFriendsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(nowPlayingFriendsProvider);
    if (friends.isEmpty) return const SizedBox.shrink();
    final c = context.seeuColors;
    final list = friends.values.toList()
      ..sort((a, b) => b.since.compareTo(a.since)); // newest first
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SeeUSectionHeader(
            kicker: 'ДРУЗЬЯ',
            title: 'Слушают сейчас',
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          ),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final n = list[i];
                return Container(
                  width: 140,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: SeeUColors.accent.withValues(alpha: 0.20),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: SeeUGradients.heroOrange,
                          borderRadius: BorderRadius.circular(8),
                          image: n.coverUrl.isNotEmpty
                              ? DecorationImage(
                                  image: CachedNetworkImageProvider(n.coverUrl,
                                      maxWidth: 96, maxHeight: 96),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: n.coverUrl.isEmpty
                            ? const Icon(PhosphorIconsRegular.musicNote,
                                color: Colors.white, size: 16)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              n.title.isNotEmpty ? n.title : 'Трек',
                              style: SeeUTypography.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              n.artist,
                              style: SeeUTypography.micro
                                  .copyWith(color: c.ink3, fontSize: 9),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
