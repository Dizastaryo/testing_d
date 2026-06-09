import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/design.dart';

// ---------------------------------------------------------------------------
// Regular video attachment bubble (from file picker / gallery)
// ---------------------------------------------------------------------------

class VideoBubble extends StatelessWidget {
  final String videoUrl;
  final bool isMine;
  final String sentTimeLabel;
  final bool isRead;
  final bool isDelivered;

  const VideoBubble({
    super.key,
    required this.videoUrl,
    required this.isMine,
    required this.sentTimeLabel,
    required this.isRead,
    required this.isDelivered,
  });

  void _openPlayer(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VideoPlayerScreen(url: AppConfig.absUrl(videoUrl)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPlayer(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 220,
          height: 140,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Dark gradient background (video placeholder)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E3050), Color(0xFF0D1A35)],
                  ),
                ),
              ),

              // Subtle film strip texture lines
              Positioned.fill(
                child: CustomPaint(painter: _FilmGrainPainter()),
              ),

              // Play button
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    PhosphorIconsFill.play,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),

              // Top-left: "Видео" badge
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsFill.videoCamera,
                        size: 11,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Видео',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom-right: time + receipt
              Positioned(
                bottom: 7,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sentTimeLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 3),
                      Icon(
                        (isRead || isDelivered)
                            ? PhosphorIconsBold.checks
                            : PhosphorIconsRegular.check,
                        size: 12,
                        color: isRead ? Colors.white : Colors.white54,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Round video note bubble (from in-chat round camera)
// ---------------------------------------------------------------------------

class VideoNoteBubble extends StatefulWidget {
  final String videoUrl;
  final bool isMine;
  final String sentTimeLabel;
  final bool isRead;
  final bool isDelivered;

  const VideoNoteBubble({
    super.key,
    required this.videoUrl,
    required this.isMine,
    required this.sentTimeLabel,
    required this.isRead,
    required this.isDelivered,
  });

  @override
  State<VideoNoteBubble> createState() => _VideoNoteBubbleState();
}

class _VideoNoteBubbleState extends State<VideoNoteBubble> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl?.removeListener(_onUpdate);
    _ctrl?.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    final playing = _ctrl!.value.isPlaying;
    if (playing != _playing) setState(() => _playing = playing);
  }

  Future<void> _togglePlay() async {
    HapticFeedback.lightImpact();

    if (_ctrl == null) {
      // First tap: initialize + play
      setState(() => _loading = true);
      final url = AppConfig.absUrl(widget.videoUrl);
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      _ctrl = ctrl;
      ctrl.addListener(_onUpdate);
      try {
        await ctrl.initialize();
      } catch (_) {
        if (mounted) setState(() => _loading = false);
        ctrl.dispose();
        _ctrl = null;
        return;
      }
      if (!mounted) {
        ctrl.dispose();
        _ctrl = null;
        return;
      }
      await ctrl.setLooping(true);
      await ctrl.play();
      setState(() {
        _initialized = true;
        _playing = true;
        _loading = false;
      });
    } else if (_ctrl!.value.isPlaying) {
      await _ctrl!.pause();
    } else {
      await _ctrl!.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    const double size = 186;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          widget.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Progress ring (shown when playing)
              if (_playing && _ctrl != null)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _ctrl!,
                  builder: (_, val, __) {
                    final progress = val.duration.inMilliseconds > 0
                        ? (val.position.inMilliseconds /
                                val.duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;
                    return SizedBox(
                      width: size + 8,
                      height: size + 8,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 3,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          SeeUColors.accent,
                        ),
                        strokeCap: StrokeCap.round,
                      ),
                    );
                  },
                )
              else
                // Static ring
                Container(
                  width: size + 8,
                  height: size + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.isMine
                          ? SeeUColors.accent.withValues(alpha: 0.35)
                          : c.line,
                      width: 2,
                    ),
                  ),
                ),

              // Circular video or placeholder
              ClipOval(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: _initialized && _ctrl != null
                      ? VideoPlayer(_ctrl!)
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF1E3050), Color(0xFF0D1A35)],
                            ),
                          ),
                          child: CustomPaint(
                            painter: _FilmGrainPainter(circular: true),
                          ),
                        ),
                ),
              ),

              // Play/loading overlay (fades out when playing)
              if (!_playing)
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.42),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        )
                      : const Icon(
                          PhosphorIconsFill.play,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 5),

        // Time + receipts row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.sentTimeLabel,
                style: TextStyle(fontSize: 10, color: c.ink3),
              ),
              if (widget.isMine) ...[
                const SizedBox(width: 3),
                Icon(
                  (widget.isRead || widget.isDelivered)
                      ? PhosphorIconsBold.checks
                      : PhosphorIconsRegular.check,
                  size: 12,
                  color: widget.isRead ? SeeUColors.accent : c.ink4,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen video player
// ---------------------------------------------------------------------------

class VideoPlayerScreen extends StatefulWidget {
  final String url;
  const VideoPlayerScreen({super.key, required this.url});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _showControls = true;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _ctrl.addListener(_onUpdate);
    _ctrl.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      _ctrl.play();
      _scheduleHide();
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onUpdate);
    _ctrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    final playing = _ctrl.value.isPlaying;
    if (playing != _isPlaying) setState(() => _isPlaying = playing);
  }

  void _scheduleHide() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls && _isPlaying) _scheduleHide();
  }

  void _togglePlay() {
    if (_ctrl.value.isPlaying) {
      _ctrl.pause();
      setState(() => _showControls = true);
    } else {
      _ctrl.play();
      _scheduleHide();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video
            if (_initialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _ctrl.value.aspectRatio,
                  child: VideoPlayer(_ctrl),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white38,
                  strokeWidth: 2,
                ),
              ),

            // Controls overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Top/bottom gradient scrim
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.65),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.75),
                          ],
                          stops: const [0.0, 0.22, 0.72, 1.0],
                        ),
                      ),
                    ),

                    SafeArea(
                      child: Column(
                        children: [
                          // Top: close + download
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Row(
                              children: [
                                _CtrlBtn(
                                  icon: PhosphorIconsRegular.x,
                                  onTap: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ),

                          const Spacer(),

                          // Center: play/pause
                          GestureDetector(
                            onTap: _togglePlay,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.48),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                _isPlaying
                                    ? PhosphorIconsFill.pause
                                    : PhosphorIconsFill.play,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),

                          const Spacer(),

                          // Bottom: seek bar + timestamps
                          if (_initialized)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 20),
                              child: ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: _ctrl,
                                builder: (_, val, __) {
                                  final pos = val.position;
                                  final dur = val.duration;
                                  final progress = dur.inMilliseconds > 0
                                      ? (pos.inMilliseconds /
                                              dur.inMilliseconds)
                                          .clamp(0.0, 1.0)
                                      : 0.0;
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SliderTheme(
                                        data: SliderThemeData(
                                          trackHeight: 2.5,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                  enabledThumbRadius: 7),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                  overlayRadius: 14),
                                          activeTrackColor: SeeUColors.accent,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: Colors.white,
                                          overlayColor: SeeUColors.accent
                                              .withValues(alpha: 0.2),
                                        ),
                                        child: Slider(
                                          value: progress,
                                          onChanged: (v) {
                                            _ctrl.seekTo(Duration(
                                              milliseconds:
                                                  (dur.inMilliseconds * v)
                                                      .round(),
                                            ));
                                          },
                                        ),
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _fmt(pos),
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11),
                                          ),
                                          Text(
                                            _fmt(dur),
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper: control button pill
// ---------------------------------------------------------------------------

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CtrlBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subtle film-grain / line texture painter
// ---------------------------------------------------------------------------

class _FilmGrainPainter extends CustomPainter {
  final bool circular;
  const _FilmGrainPainter({this.circular = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const step = 20.0;
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
