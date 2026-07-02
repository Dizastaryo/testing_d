import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';

/// MUSIC-2: synced LRC lyrics. Auto-scrolls + highlights the active line based
/// on playback position; tap a line to seek there. Opened from the full-screen
/// player via [Navigator.push].
class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  @override
  Widget build(BuildContext context) {
    // Watch only the track — NOT position — so the blurred backdrop and header
    // don't repaint on every position tick. The synced highlight + auto-scroll
    // lives in [_LyricsBody], a leaf that watches position alone.
    final track = ref.watch(miniPlayerProvider.select((s) => s.track));
    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Blurred cover backdrop — consistent with the full-screen player.
          Positioned.fill(
            child: track.coverUrl.isNotEmpty
                ? ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                    child: CachedNetworkImage(
                      imageUrl: track.coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        decoration:
                            const BoxDecoration(gradient: SeeUGradients.heroOrange),
                      ),
                    ),
                  )
                : Container(
                    decoration:
                        const BoxDecoration(gradient: SeeUGradients.heroOrange),
                  ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.88),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _header(context, track),
                Expanded(child: _LyricsBody(track: track)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AudioTrack track) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Назад',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(PhosphorIcons.caretDown(), color: Colors.white),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  track.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

}

/// Synced lyrics list — leaf that watches only the playback position (in ms) and
/// the track id, so the highlight + auto-scroll update without rebuilding the
/// blurred backdrop/header in the parent. Owns the scroll controller and the
/// per-line GlobalKeys (cleared when the track changes).
class _LyricsBody extends ConsumerStatefulWidget {
  const _LyricsBody({required this.track});

  final AudioTrack track;

  @override
  ConsumerState<_LyricsBody> createState() => _LyricsBodyState();
}

class _LyricsBodyState extends ConsumerState<_LyricsBody> {
  final _scrollController = ScrollController();
  final _itemKeys = <int, GlobalKey>{};
  int _activeIndex = -1;
  List<LyricLine> _lines = const [];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LyricsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Track changed → the old GlobalKeys point at lines that no longer exist;
    // clear them (and reset the active line) so we don't reuse stale keys.
    if (oldWidget.track.id != widget.track.id) {
      _itemKeys.clear();
      _activeIndex = -1;
    }
  }

  int _indexFor(int positionMs) {
    var idx = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].timeMs <= positionMs) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _scrollToActive() {
    final key = _itemKeys[_activeIndex];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.42, // keep the active line a little above centre
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    _lines = parseLrcCached(track.id, track.lyricsLrc);

    // Recompute active line and auto-scroll when position changes.
    final posMs =
        ref.watch(miniPlayerProvider.select((s) => s.position.inMilliseconds));
    final newIndex = _indexFor(posMs);
    if (newIndex != _activeIndex) {
      _activeIndex = newIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActive();
      });
    }

    return _lines.isEmpty ? _emptyState() : _lyricsList();
  }

  Widget _lyricsList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 120),
      itemCount: _lines.length,
      itemBuilder: (context, i) {
        final key = _itemKeys.putIfAbsent(i, () => GlobalKey());
        final active = i == _activeIndex;
        final past = i < _activeIndex;
        final color = active
            ? Colors.white
            : past
                ? Colors.white38
                : Colors.white60;
        return Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              ref
                  .read(miniPlayerProvider.notifier)
                  .seek(Duration(milliseconds: _lines[i].timeMs));
            },
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                color: color,
                fontSize: active ? 24 : 19,
                height: 1.25,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
              child: Text(_lines[i].text),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.microphoneStage(),
              size: 56, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'Для этого трека пока нет текста',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Синхронизированные слова появятся,\nкогда автор их добавит',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Push the lyrics screen with a smooth bottom-up transition.
Future<void> showLyricsScreen(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => const LyricsScreen(),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
  );
}
