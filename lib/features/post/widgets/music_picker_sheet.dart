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

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Handle
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: c.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(children: [
            Text('Выберите музыку',
                style: SeeUTypography.subtitle.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),

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
            loading: () => const Center(
                child: CircularProgressIndicator(color: SeeUColors.accent)),
            error: (_, __) => Center(
                child: Text('Ошибка загрузки',
                    style: SeeUTypography.body.copyWith(color: c.ink3))),
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
          color: isPlaying
              ? SeeUColors.accent.withValues(alpha: 0.08)
              : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(
            color: isPlaying
                ? SeeUColors.accent.withValues(alpha: 0.35)
                : Colors.transparent,
            width: 1,
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
                color: isPlaying
                    ? SeeUColors.accent
                    : SeeUColors.accent.withValues(alpha: 0.12),
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
