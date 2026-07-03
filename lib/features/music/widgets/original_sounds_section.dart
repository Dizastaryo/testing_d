import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/audio/audio_player_service.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';

class OriginalSoundsSection extends ConsumerWidget {
  final List<AudioTrack> tracks;
  const OriginalSoundsSection({super.key, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SeeUSectionHeader(
            kicker: 'ИЗ ВИДЕО',
            title: 'Оригинальные звуки',
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _OriginalSoundTile(
              track: tracks[i],
              ref: ref,
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginalSoundTile extends StatelessWidget {
  final AudioTrack track;
  final WidgetRef ref;
  const _OriginalSoundTile({required this.track, required this.ref});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;

    return GestureDetector(
      onTap: () => context.push('/music/track/${track.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent
              ? SeeUColors.accent.withValues(alpha: 0.08)
              : c.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCurrent
                ? SeeUColors.accent.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeeUColors.accent.withValues(alpha: 0.15),
              ),
              child: Icon(
                PhosphorIconsRegular.videoCamera,
                size: 16,
                color: SeeUColors.accent,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (track.usesCount > 0)
              Text(
                '${track.usesCount} видео',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  color: c.ink3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
