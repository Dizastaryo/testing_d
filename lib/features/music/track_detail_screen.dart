import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/audio_provider.dart';
import '../../widgets/audio_waveform.dart'; // Phase 9

// ── Providers ────────────────────────────────────────────────────────────────

final _trackDetailProvider =
    FutureProvider.autoDispose.family<AudioTrack, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final r = await api.get(ApiEndpoints.audioTrackById(id));
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  return AudioTrack.fromJson(data as Map<String, dynamic>);
});

// ── Screen ───────────────────────────────────────────────────────────────────

class TrackDetailScreen extends ConsumerWidget {
  final String trackId;
  const TrackDetailScreen({super.key, required this.trackId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackAsync = ref.watch(_trackDetailProvider(trackId));

    return Scaffold(
      body: trackAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SeeUErrorState(
          title: 'Не удалось загрузить трек',
          onRetry: () => ref.invalidate(_trackDetailProvider(trackId)),
        ),
        data: (track) => _TrackDetailBody(track: track),
      ),
    );
  }
}

class _TrackDetailBody extends ConsumerStatefulWidget {
  final AudioTrack track;
  const _TrackDetailBody({required this.track});

  @override
  ConsumerState<_TrackDetailBody> createState() => _TrackDetailBodyState();
}

class _TrackDetailBodyState extends ConsumerState<_TrackDetailBody> {
  late AudioTrack _track;
  bool _likeInFlight = false;
  bool _saveInFlight = false;

  @override
  void initState() {
    super.initState();
    _track = widget.track;
  }

  void _togglePlay() {
    ref.read(miniPlayerProvider.notifier).play(_track);
  }

  Future<void> _toggleLike() async {
    if (_likeInFlight) return;
    setState(() => _likeInFlight = true);
    final wasLiked = _track.isLikedByMe;
    // Optimistic update.
    setState(() {
      _track = _track.copyWith(
        isLikedByMe: !wasLiked,
        likesCount: _track.likesCount + (wasLiked ? -1 : 1),
      );
    });
    try {
      final api = ref.read(apiClientProvider);
      if (wasLiked) {
        await api.delete(ApiEndpoints.audioTrackLike(_track.id));
      } else {
        await api.post(ApiEndpoints.audioTrackLike(_track.id));
      }
    } catch (_) {
      // Revert on failure.
      if (mounted) {
        setState(() {
          _track = _track.copyWith(
            isLikedByMe: wasLiked,
            likesCount: _track.likesCount + (wasLiked ? 1 : -1),
          );
        });
        showSeeUSnackBar(context, 'Не удалось поставить лайк',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _likeInFlight = false);
    }
  }

  Future<void> _toggleSave() async {
    if (_saveInFlight) return;
    setState(() => _saveInFlight = true);
    final wasSaved = _track.isSavedByMe;
    setState(() => _track = _track.copyWith(isSavedByMe: !wasSaved));
    try {
      final api = ref.read(apiClientProvider);
      if (wasSaved) {
        await api.delete(ApiEndpoints.audioTrackSave(_track.id));
      } else {
        await api.post(ApiEndpoints.audioTrackSave(_track.id));
      }
      // Refresh saved tracks list.
      ref.invalidate(savedTracksProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _track = _track.copyWith(isSavedByMe: wasSaved));
        showSeeUSnackBar(context, 'Не удалось сохранить трек',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _saveInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == _track.id;
    final isPlaying = isCurrent && player.playing;

    return CustomScrollView(
      slivers: [
        // ── AppBar — стеклянный collapse ─────────────────────────────────────
        SliverAppBar(
          expandedHeight: 260,
          pinned: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: Center(
            child: SeeUGlassCircleButton(
              size: 40,
              icon: PhosphorIcon(PhosphorIcons.caretLeft(),
                  color: Colors.white, size: 20),
              onTap: () => context.pop(),
            ),
          ),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: SeeUColors.background.withValues(alpha: 0.72),
                  border: Border(
                    bottom: BorderSide(color: c.line, width: 0.5),
                  ),
                ),
                child: FlexibleSpaceBar(
                  background: _CoverHero(
                    coverUrl: _track.coverUrl,
                    isPlaying: isPlaying,
                    onPlayTap: _togglePlay,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Track info ───────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SeeUSectionHeader(
                  kicker: 'ТРЕК',
                  hairline: true,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                if (_track.isOriginalSound) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIcons.videoCamera(), size: 12, color: SeeUColors.accent),
                        const SizedBox(width: 5),
                        Text(
                          'Оригинальный звук',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: SeeUColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  _track.title,
                  style: SeeUTypography.displayM,
                ),
                const SizedBox(height: 6),
                Text(
                  _track.isOriginalSound
                      ? 'Источник: видео · ${_track.displayArtist}'
                      : _track.displayArtist,
                  style: SeeUTypography.subtitle.copyWith(color: c.ink2),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _Chip(label: _categoryLabel(_track.category)),
                    if (_track.subcategory.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _Chip(label: _track.subcategory),
                    ],
                    if (_track.durationSeconds > 0) ...[
                      const SizedBox(width: 6),
                      _Chip(label: _track.durationFormatted),
                    ],
                  ],
                ),
                // Phase 9: waveform preview
                if (_track.waveformData != null && _track.waveformData!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _WaveformSection(track: _track),
                ],
                const SizedBox(height: 8),
                // Engagement counters
                Row(
                  children: [
                    Icon(PhosphorIcons.videoCamera(), size: 14, color: c.ink3),
                    const SizedBox(width: 4),
                    Text('${_track.usesCount} видео', style: TextStyle(fontSize: 12, color: c.ink3)),
                    const SizedBox(width: 12),
                    Icon(PhosphorIcons.heart(), size: 14, color: c.ink3),
                    const SizedBox(width: 4),
                    Text('${_track.likesCount}', style: TextStyle(fontSize: 12, color: c.ink3)),
                    const SizedBox(width: 12),
                    Icon(PhosphorIcons.play(), size: 14, color: c.ink3),
                    const SizedBox(width: 4),
                    Text('${_track.playsCount}', style: TextStyle(fontSize: 12, color: c.ink3)),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ── Actions ──────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                const Spacer(),
                // Like button
                _EngagementButton(
                  icon: _track.isLikedByMe
                      ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                      : PhosphorIcons.heart(),
                  color: _track.isLikedByMe ? SeeUColors.like : null,
                  onTap: _likeInFlight ? null : _toggleLike,
                ),
                const SizedBox(width: 4),
                // Save button
                _EngagementButton(
                  icon: _track.isSavedByMe
                      ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                      : PhosphorIcons.bookmarkSimple(),
                  color: _track.isSavedByMe ? SeeUColors.accent : null,
                  onTap: _saveInFlight ? null : _toggleSave,
                ),
                const SizedBox(width: 4),
                _PlayButton(isPlaying: isPlaying, onTap: _togglePlay),
              ],
            ),
          ),
        ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  String _categoryLabel(String cat) {
    const labels = {
      'music': 'Музыка',
      'memes': 'Мемы',
      'audiobooks': 'Аудиокниги',
      'podcasts': 'Подкасты',
      'education': 'Образование',
      'meditation': 'Медитация',
      'news': 'Новости',
      'instrumental': 'Инструментал',
      'other': 'Другое',
    };
    return labels[cat] ?? cat;
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _CoverHero extends StatelessWidget {
  final String coverUrl;
  final bool isPlaying;
  final VoidCallback onPlayTap;

  const _CoverHero({
    required this.coverUrl,
    required this.isPlaying,
    required this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        coverUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _Placeholder(),
              )
            : _Placeholder(),
        // Dark gradient overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
              stops: const [0.3, 1.0],
            ),
          ),
        ),
        // Glass play/pause над обложкой
        Positioned(
          right: 16,
          bottom: 16,
          child: SeeUGlassCircleButton(
            size: 48,
            tint: SeeUColors.accent,
            icon: PhosphorIcon(
              isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              color: Colors.white,
              size: 22,
            ),
            onTap: onPlayTap,
          ),
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: SeeUColors.accent.withValues(alpha: 0.2),
      alignment: Alignment.center,
      child: Icon(
        PhosphorIcons.musicNote(PhosphorIconsStyle.fill),
        size: 72,
        color: SeeUColors.accent.withValues(alpha: 0.6),
      ),
    );
  }
}

class _EngagementButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const _EngagementButton({required this.icon, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (color ?? c.ink2).withValues(alpha: 0.08),
        ),
        child: Icon(icon, color: onTap == null ? c.ink3 : (color ?? c.ink), size: 20),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SeeUColors.accent.withValues(alpha: 0.12),
          border: Border.all(color: SeeUColors.accent, width: 1.5),
        ),
        child: Icon(
          isPlaying ? PhosphorIcons.pause(PhosphorIconsStyle.fill) : PhosphorIcons.play(PhosphorIconsStyle.fill),
          color: SeeUColors.accent,
          size: 22,
        ),
      ),
    );
  }
}

// ── Waveform + metadata section (Phase 9) ────────────────────────────────────

class _WaveformSection extends ConsumerWidget {
  final AudioTrack track;
  const _WaveformSection({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(miniPlayerProvider);
    final c = context.seeuColors;

    // Compute progress only when this track is the one playing.
    double progress = 0.0;
    if (state.track?.id == track.id) {
      final dur = state.duration ?? Duration.zero;
      final pos = state.position;
      if (dur.inMilliseconds > 0) {
        progress = pos.inMilliseconds / dur.inMilliseconds;
      }
    }

    final tech = track.technicalSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AudioWaveformPreview(
          waveform: track.waveformData,
          progress: progress,
          height: 44,
          activeColor: SeeUColors.accent,
          inactiveColor: c.ink3.withValues(alpha: 0.35),
        ),
        if (tech.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(tech, style: TextStyle(fontSize: 11, color: c.ink3)),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: c.ink2, fontWeight: FontWeight.w500)),
    );
  }
}
