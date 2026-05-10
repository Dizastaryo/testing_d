import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/audio/audio_player_service.dart';
import '../core/design/design.dart';
import '../core/models/audio_track.dart';

/// Floating mini-player над bottom-nav. Виден когда есть активный трек,
/// иначе — `SizedBox.shrink()`. Тап — раскрытие в full-screen player'е через
/// существующий music screen (`/services` → music tab).
///
/// Стиль: glass-card на оранжевом tint'е с blur'ом, обложка слева, заголовок
/// + артист в центре, play/pause + close справа. Sub-pixel progress bar
/// сверху по периметру (тонкая оранжевая полоска).
class SeeUMiniPlayer extends ConsumerWidget {
  const SeeUMiniPlayer({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(miniPlayerProvider);
    final track = state.track;
    if (track == null) return const SizedBox.shrink();

    final progress = (state.duration != null && state.duration!.inMilliseconds > 0)
        ? (state.position.inMilliseconds / state.duration!.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  SeeUColors.accent.withValues(alpha: 0.16),
                  SeeUColors.accent.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: SeeUColors.accent.withValues(alpha: 0.22),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: SeeUShadows.md,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                child: Stack(
                  children: [
                    // Контент: cover, title, controls
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Row(
                        children: [
                          _Cover(track: track),
                          const SizedBox(width: 12),
                          Expanded(child: _TitleArtist(track: track)),
                          _PlayPauseBtn(playing: state.playing),
                          IconButton(
                            tooltip: 'Закрыть',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                ref.read(miniPlayerProvider.notifier).close(),
                            icon: Icon(
                              PhosphorIcons.x(),
                              size: 18,
                              color: SeeUColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Тонкая progress-полоска снизу
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        height: 2,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor:
                              SeeUColors.accent.withValues(alpha: 0.15),
                          valueColor:
                              const AlwaysStoppedAnimation(SeeUColors.accent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.track});
  final AudioTrack track;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 48,
        height: 48,
        child: track.coverUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: track.coverUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: c.surface2),
                errorWidget: (_, __, ___) => Container(color: c.surface2),
              )
            : Container(
                color: c.surface2,
                child: Icon(PhosphorIcons.musicNotes(), color: c.ink3),
              ),
      ),
    );
  }
}

class _TitleArtist extends StatelessWidget {
  const _TitleArtist({required this.track});
  final AudioTrack track;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SeeUTypography.subtitle.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 2),
        Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SeeUTypography.caption.copyWith(color: c.ink2, fontSize: 12),
        ),
      ],
    );
  }
}

class _PlayPauseBtn extends ConsumerWidget {
  const _PlayPauseBtn({required this.playing});
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => ref.read(miniPlayerProvider.notifier).toggle(),
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SeeUGradients.heroOrange,
        ),
        child: Center(
          child: Icon(
            playing
                ? PhosphorIcons.pause(PhosphorIconsStyle.fill)
                : PhosphorIcons.play(PhosphorIconsStyle.fill),
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}
