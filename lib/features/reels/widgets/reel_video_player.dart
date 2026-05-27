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

class _ReelVideoPlayerState extends State<ReelVideoPlayer> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _hasError = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: const {'Connection': 'keep-alive'},
    );
    _ctrl!
      ..setLooping(true)
      ..setVolume(1.0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        if (widget.isActive && !_paused) _ctrl!.play();
      }).catchError((_) {
        if (mounted) setState(() => _hasError = true);
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
    _ctrl?.dispose();
    super.dispose();
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
                  color: Colors.white24, strokeWidth: 2),
              ),
            if (_hasError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.arrowClockwise,
                        color: Colors.white38, size: 48),
                    const SizedBox(height: 8),
                    Text('Нажмите для повтора',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ],
                ),
              ),
            // Pause icon overlay
            if (_paused && _initialized)
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(PhosphorIconsRegular.play,
                      color: Colors.white, size: 44),
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
