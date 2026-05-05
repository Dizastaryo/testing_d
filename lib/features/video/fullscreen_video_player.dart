import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class FullscreenVideoPlayer extends StatefulWidget {
  final String url;
  const FullscreenVideoPlayer({super.key, required this.url});

  @override
  State<FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<FullscreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _showControls = true;
  bool _seeking = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: const {'Connection': 'keep-alive'},
    );
    _controller
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
          // Auto-hide controls after 2s
          _scheduleHideControls();
        }
      }).catchError((e) {
        debugPrint('Fullscreen video error: $e');
        if (mounted) setState(() => _hasError = true);
      });
    _controller.addListener(_onVideoUpdate);
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onVideoUpdate() {
    if (mounted && !_seeking) setState(() {});
  }

  void _scheduleHideControls() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onTap() {
    if (!_initialized) return;

    if (_showControls) {
      // Toggle play/pause
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
        _scheduleHideControls();
      }
      setState(() {});
    } else {
      // Show controls
      setState(() => _showControls = true);
      _scheduleHideControls();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video
              if (_initialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                )
              else if (_hasError)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.white38, size: 48),
                      SizedBox(height: 12),
                      Text('Не удалось загрузить видео',
                          style: TextStyle(color: Colors.white38, fontSize: 14)),
                    ],
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(
                      color: Colors.white24, strokeWidth: 2.5),
                ),

              // Close button — always visible
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),

              // Seek bar at bottom — shown with controls
              if (_initialized && _showControls)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                  child: _buildSeekBar(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeekBar() {
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Time labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(position),
              style: const TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              _formatDuration(duration),
              style: const TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Slider
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChangeStart: (_) => _seeking = true,
            onChanged: (v) {
              final pos = Duration(
                milliseconds: (v * duration.inMilliseconds).round(),
              );
              _controller.seekTo(pos);
              setState(() {});
            },
            onChangeEnd: (_) {
              _seeking = false;
              _scheduleHideControls();
            },
          ),
        ),
      ],
    );
  }
}
