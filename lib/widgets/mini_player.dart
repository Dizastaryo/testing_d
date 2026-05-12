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

  /// MUSIC-5: long-press → speed-picker. just_audio поддерживает setSpeed
  /// без EQ-аппаратной обработки. True EQ (band gain control) требует
  /// just_audio_effects (Android-only experimental) или native bridge —
  /// отдельная подзадача MUSIC-5.1.
  void _showSpeedSheet(BuildContext context, WidgetRef ref) {
    final service = ref.read(audioPlayerServiceProvider);
    final current = service.raw.speed;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final c = context.seeuColors;
        Widget option(String label, double speed) {
          final selected = (current - speed).abs() < 0.05;
          return ListTile(
            leading: Icon(Icons.speed,
                color: selected ? SeeUColors.accent : c.ink2),
            title: Text(label,
                style: TextStyle(
                  color: selected ? SeeUColors.accent : c.ink,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                )),
            trailing: selected
                ? const Icon(Icons.check, color: SeeUColors.accent)
                : null,
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              await service.raw.setSpeed(speed);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.speed, color: SeeUColors.accent),
                    const SizedBox(width: 8),
                    Text('Скорость воспроизведения',
                        style: SeeUTypography.title),
                  ],
                ),
              ),
              option('0.75×', 0.75),
              option('1×', 1.0),
              option('1.25×', 1.25),
              option('1.5×', 1.5),
              option('2×', 2.0),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

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
                onLongPress: () => _showSpeedSheet(context, ref),
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

class _TitleArtist extends ConsumerWidget {
  const _TitleArtist({required this.track});
  final AudioTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    // MUSIC-2: если у трека есть lyrics — показываем текущую строку вместо
    // artist в subtitle (italic, accent для эффекта sing-along).
    final state = ref.watch(miniPlayerProvider);
    final lines = track.lyricsLrc.isNotEmpty
        ? parseLrc(track.lyricsLrc)
        : const <LyricLine>[];
    final cur = lines.isEmpty
        ? null
        : currentLyricAt(lines, state.position.inMilliseconds);
    final hasLyric = cur != null && cur.text.isNotEmpty && state.playing;
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
          hasLyric ? cur.text : track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SeeUTypography.caption.copyWith(
            color: hasLyric ? SeeUColors.accent : c.ink2,
            fontSize: 12,
            fontStyle: hasLyric ? FontStyle.italic : FontStyle.normal,
            fontWeight: hasLyric ? FontWeight.w600 : FontWeight.normal,
          ),
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
