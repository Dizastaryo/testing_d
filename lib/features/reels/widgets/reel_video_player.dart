import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/design/tokens.dart';

/// Full-screen looping video player for a single reel.
/// Manages its own controller lifecycle; preloads on init, plays when [isActive].
class ReelVideoPlayer extends StatefulWidget {
  final String url;
  final bool isActive;
  final VoidCallback? onTap;

  const ReelVideoPlayer({
    super.key,
    required this.url,
    required this.isActive,
    this.onTap,
  });

  @override
  State<ReelVideoPlayer> createState() => _ReelVideoPlayerState();
}

class _ReelVideoPlayerState extends State<ReelVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _hasError = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
  }

  /// Pause on background, resume when foregrounded — only if this reel is the
  /// active page and not user-paused. Prevents reel audio playing while the app
  /// is backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized || _ctrl == null) return;
    if (state == AppLifecycleState.resumed) {
      if (widget.isActive && !_paused) _ctrl?.play();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _ctrl?.pause();
    }
  }

  void _initController() {
    final c = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: const {'Connection': 'keep-alive'},
    );
    _ctrl = c;
    c
      ..setLooping(true)
      ..setVolume(1.0)
      ..initialize().then((_) {
        // Bail if replaced mid-init (retry/dispose race) — don't drive a
        // controller that's no longer the live one.
        if (!mounted || c != _ctrl) return;
        setState(() => _initialized = true);
        if (widget.isActive && !_paused) c.play();
      }).catchError((_) {
        if (!mounted || c != _ctrl) return;
        setState(() => _hasError = true);
      });
  }

  @override
  void didUpdateWidget(ReelVideoPlayer old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      if (widget.isActive && _initialized && !_paused) {
        _ctrl?.play();
      } else {
        _ctrl?.pause();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  // Re-initialize after a load error. The old "Нажмите для повтора" UI was
  // dead: the only tap handler (_togglePause) early-returns while !_initialized,
  // which is exactly the error state. Dispose the failed controller and rebuild.
  void _retry() {
    _ctrl?.dispose();
    _ctrl = null;
    setState(() {
      _initialized = false;
      _hasError = false;
      _paused = false;
    });
    _initController();
  }

  void _togglePause() {
    if (!_initialized || _ctrl == null) return;
    setState(() => _paused = !_paused);
    _paused ? _ctrl!.pause() : _ctrl!.play();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _togglePause();
        widget.onTap?.call();
      },
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_initialized && _ctrl != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _ctrl!.value.aspectRatio,
                  child: VideoPlayer(_ctrl!),
                ),
              ),
            if (!_initialized && !_hasError)
              const Center(
                child: CircularProgressIndicator(
                  color: SeeUColors.accent, strokeWidth: 2),
              ),
            if (_hasError)
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _retry,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.arrowClockwise,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 44),
                      const SizedBox(height: SeeUSpacing.md),
                      Text(
                        'НАЖМИТЕ ДЛЯ ПОВТОРА',
                        style: SeeUTypography.kicker.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Pause icon overlay — стеклянный диск поверх видео.
            if (_paused && _initialized)
              Center(
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.14),
                            Colors.black.withValues(alpha: 0.28),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(PhosphorIconsFill.play,
                          color: Colors.white, size: 34),
                    ),
                  ),
                ),
              ),
            // Progress bar at bottom
            if (_initialized && _ctrl != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 4,
                  child: VideoProgressIndicator(
                    _ctrl!,
                    allowScrubbing: false,
                    colors: VideoProgressColors(
                      playedColor: SeeUColors.accent,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
