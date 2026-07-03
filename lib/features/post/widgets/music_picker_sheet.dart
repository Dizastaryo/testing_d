import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/utils/format.dart';

/// Re-export AudioTrack so callers can use it directly.
export '../../../core/providers/user_provider.dart' show AudioTrack;

class MusicPickerSheet extends ConsumerStatefulWidget {
  final ValueChanged<AudioTrack> onSelect;
  const MusicPickerSheet({super.key, required this.onSelect});

  @override
  ConsumerState<MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends ConsumerState<MusicPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<AudioTrack>? _filtered;
  final _player = AudioPlayer();
  String? _playingId;
  bool _isLoadingAudio = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── Playback ────────────────────────────────────────────────────────────

  Future<void> _togglePlay(AudioTrack track) async {
    HapticFeedback.selectionClick();
    if (_playingId == track.id) {
      // Stop currently playing
      await _player.stop();
      if (!mounted) return;
      setState(() { _playingId = null; _isLoadingAudio = false; });
      return;
    }

    setState(() { _playingId = track.id; _isLoadingAudio = true; });

    try {
      await _player.stop();
      final url = track.audioUrl;
      if (url.isEmpty) {
        setState(() { _playingId = null; _isLoadingAudio = false; });
        return;
      }
      await _player.setUrl(url);
      await _player.play();
      if (mounted) setState(() => _isLoadingAudio = false);
      // Auto-clear when done
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() { _playingId = null; _isLoadingAudio = false; });
        }
      });
    } catch (e) {
      debugPrint('MusicPickerSheet playback error: $e');
      if (mounted) setState(() { _playingId = null; _isLoadingAudio = false; });
    }
  }

  void _select(AudioTrack track) {
    _player.stop();
    widget.onSelect(track);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final tracksAsync = ref.watch(audioTracksProvider);

    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
      // #53: taller sheet for comfortable browsing.
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.85),
        border: Border(
          top: BorderSide(
            color: SeeUColors.accent.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Column(children: [
        // Handle
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: c.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header with close (#54)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 14),
          child: Row(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('МУЗЫКА',
                    style: SeeUTypography.kicker
                        .copyWith(color: SeeUColors.accent)),
                const SizedBox(height: 4),
                Text('Выберите трек',
                    style: SeeUTypography.displayS.copyWith(color: c.ink)),
              ],
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(PhosphorIcons.x(), size: 16, color: c.ink2),
              ),
            ),
          ]),
        ),

        // Hairline under the editorial header
        Container(height: 1, color: c.line),
        const SizedBox(height: 12),

        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(SeeURadii.pill),
            ),
            child: Row(children: [
              Icon(PhosphorIcons.magnifyingGlass(), size: 16, color: c.ink3),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: SeeUTypography.body.copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Найти трек...',
                    hintStyle: SeeUTypography.body.copyWith(
                        fontSize: 13, color: c.ink3),
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  onChanged: (q) {
                    final tracks = tracksAsync.valueOrNull ?? [];
                    if (q.trim().isEmpty) {
                      setState(() => _filtered = null);
                    } else {
                      final lq = q.toLowerCase();
                      setState(() {
                        _filtered = tracks.where((t) =>
                            t.title.toLowerCase().contains(lq) ||
                            t.artist.toLowerCase().contains(lq)).toList();
                      });
                    }
                  },
                ),
              ),
              if (_searchCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() => _filtered = null);
                  },
                  child: Icon(PhosphorIcons.x(), size: 16, color: c.ink3),
                ),
            ]),
          ),
        ),

        const SizedBox(height: 8),

        // Track list
        Expanded(
          child: tracksAsync.when(
            loading: () => ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: 8,
              itemBuilder: (_, __) => _SkeletonTile(c: c),
            ),
            error: (_, __) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsRegular.cloudWarning, size: 40, color: c.ink3),
                  const SizedBox(height: 12),
                  Text('Не удалось загрузить музыку',
                      style: SeeUTypography.body.copyWith(color: c.ink2)),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => ref.invalidate(audioTracksProvider),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.accentSoft,
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                      ),
                      child: const Text('Повторить',
                          style: TextStyle(
                              color: SeeUColors.accent,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            data: (allTracks) {
              final tracks = _filtered ?? allTracks;
              if (tracks.isEmpty) {
                return Center(
                  child: Text(
                    _searchCtrl.text.isEmpty ? 'Нет треков' : 'Ничего не найдено',
                    style: SeeUTypography.body.copyWith(color: c.ink3),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: tracks.length,
                itemBuilder: (_, i) => _TrackTile(
                  track: tracks[i],
                  isPlaying: _playingId == tracks[i].id,
                  isLoading: _isLoadingAudio && _playingId == tracks[i].id,
                  player: _player,
                  onPlay: () => _togglePlay(tracks[i]),
                  onSelect: () => _select(tracks[i]),
                  c: c,
                ),
              );
            },
          ),
        ),
      ]),
        ),
      ),
    );
  }
}

// ── Skeleton tile (loading placeholder, #55) ──────────────────────────────────

class _SkeletonTile extends StatefulWidget {
  final SeeUThemeColors c;
  const _SkeletonTile({required this.c});

  @override
  State<_SkeletonTile> createState() => _SkeletonTileState();
}

class _SkeletonTileState extends State<_SkeletonTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1.0).animate(_ac),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: widget.c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.c.line,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 140, height: 11, color: widget.c.line),
                  const SizedBox(height: 7),
                  Container(width: 90, height: 9, color: widget.c.line),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Track tile ───────────────────────────────────────────────────────────────

class _TrackTile extends StatelessWidget {
  final AudioTrack track;
  final bool isPlaying;
  final bool isLoading;
  final AudioPlayer player;
  final VoidCallback onPlay;
  final VoidCallback onSelect;
  final SeeUThemeColors c;

  const _TrackTile({
    required this.track,
    required this.isPlaying,
    required this.isLoading,
    required this.player,
    required this.onPlay,
    required this.onSelect,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          // #59: clearer playing state — stronger tint + accent border.
          color: isPlaying ? c.accentSoft : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(
            color: isPlaying ? SeeUColors.accent : Colors.transparent,
            width: isPlaying ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          // Cover
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 46,
              height: 46,
              child: track.coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: track.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _CoverPlaceholder(c: c),
                      errorWidget: (_, __, ___) => _CoverPlaceholder(c: c),
                    )
                  : _CoverPlaceholder(c: c),
            ),
          ),
          const SizedBox(width: 10),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: SeeUTypography.subtitle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isPlaying ? SeeUColors.accent : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${track.artist}  ·  ${formatDuration(Duration(seconds: track.durationSeconds))}',
                  style: SeeUTypography.caption.copyWith(
                      color: c.ink3, fontSize: 12),
                ),
                // Waveform when playing
                if (isPlaying && !isLoading) ...[
                  const SizedBox(height: 4),
                  _PlayingWaveform(player: player),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Play/Stop button
          GestureDetector(
            onTap: onPlay,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isPlaying ? SeeUColors.accent : c.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        isPlaying
                            ? PhosphorIconsFill.stop
                            : PhosphorIconsFill.play,
                        color: isPlaying
                            ? Colors.white
                            : SeeUColors.accent,
                        size: 16,
                      ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Cover placeholder ────────────────────────────────────────────────────────

class _CoverPlaceholder extends StatelessWidget {
  final SeeUThemeColors c;
  const _CoverPlaceholder({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: c.line,
      child: Icon(PhosphorIcons.musicNotes(), color: c.ink3, size: 20),
    );
  }
}

// ── Playing waveform (animated bars) ────────────────────────────────────────

class _PlayingWaveform extends StatefulWidget {
  final AudioPlayer player;
  const _PlayingWaveform({required this.player});

  @override
  State<_PlayingWaveform> createState() => _PlayingWaveformState();
}

class _PlayingWaveformState extends State<_PlayingWaveform>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  static const _barCount = 5;
  static const _phases = [0.0, 0.5, 1.0, 0.25, 0.75];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_barCount, (i) => AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400 + i * 60),
    )..repeat(reverse: true));

    _anims = List.generate(_barCount, (i) => Tween<double>(
      begin: 2.0, end: 12.0,
    ).animate(CurvedAnimation(
      parent: _controllers[i],
      curve: Curves.easeInOut,
    )));

    // Offset start to create staggered effect
    for (int i = 0; i < _barCount; i++) {
      _controllers[i].forward(from: _phases[i]);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (i) {
          return AnimatedBuilder(
            animation: _anims[i],
            builder: (_, __) => Container(
              width: 2.5,
              height: _anims[i].value,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: SeeUColors.accent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Static waveform painter (for non-playing state) ──────────────────────────

class MusicWaveformPainter extends CustomPainter {
  final Color color;
  final int barCount;
  MusicWaveformPainter({required this.color, this.barCount = 60});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;
    const barW = 2.0;
    final gap = (size.width - barCount * barW) / (barCount + 1);
    for (int i = 0; i < barCount; i++) {
      final seed = (i * 7 + 3) % 13;
      final h = size.height * (0.2 + 0.6 * (seed / 13.0));
      final x = gap + i * (barW + gap) + barW / 2;
      final top = (size.height - h) / 2;
      paint.strokeWidth = barW;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant MusicWaveformPainter old) =>
      old.color != color || old.barCount != barCount;
}
