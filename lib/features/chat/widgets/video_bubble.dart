import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/design.dart';

// ---------------------------------------------------------------------------
// Regular video attachment bubble (from file picker / gallery)
// ---------------------------------------------------------------------------

class VideoBubble extends StatefulWidget {
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

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  Uint8List? _thumbnail;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (kIsWeb) return;
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: AppConfig.absUrl(widget.videoUrl),
        imageFormat: ImageFormat.JPEG,
        maxHeight: 320,
        quality: 82,
      );
      if (mounted && bytes != null) setState(() => _thumbnail = bytes);
    } catch (_) {}
  }

  void _openPlayer(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VideoPlayerScreen(url: AppConfig.absUrl(widget.videoUrl)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () => _openPlayer(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.small),
        child: SizedBox(
          width: 220,
          height: 140,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Реальное превью кадра (или нейтральный плейсхолдер, пока грузится)
              if (_thumbnail != null)
                Image.memory(_thumbnail!,
                    fit: BoxFit.cover, gaplessPlayback: true)
              else
                Container(color: c.surface2),

              // Единый scrim для читаемости оверлеев
              const DecoratedBox(
                decoration: BoxDecoration(color: SeeUColors.lightScrim),
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
                    color: SeeUColors.mediumScrim,
                    borderRadius: BorderRadius.circular(SeeURadii.small),
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
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SeeUColors.mediumScrim,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.sentTimeLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                      if (widget.isMine) ...[
                        const SizedBox(width: 3),
                        Icon(
                          (widget.isRead || widget.isDelivered)
                              ? PhosphorIconsBold.checks
                              : PhosphorIconsRegular.check,
                          size: 12,
                          color: widget.isRead ? Colors.white : Colors.white54,
                        ),
                      ],
                    ],
                  ),
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
  Uint8List? _thumbnail;

  static const double _size = 220;
  static const double _ringGap = 6;
  static const double _ringWidth = 3.5;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (kIsWeb) return;
    try {
      final url = AppConfig.absUrl(widget.videoUrl);
      final bytes = await VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 320,
        quality: 82,
      );
      if (mounted && bytes != null) setState(() => _thumbnail = bytes);
    } catch (_) {}
  }

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
    HapticFeedback.mediumImpact();
    if (_ctrl == null) {
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
    final ringSize = _size + _ringGap * 2 + _ringWidth * 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ── Outer glow shadow ──────────────────────────────
                Container(
                  width: ringSize,
                  height: ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: SeeUColors.accent.withValues(alpha: 0.15),
                        blurRadius: 20,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),

                // ── Progress ring ─────────────────────────────────
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
                        width: ringSize,
                        height: ringSize,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: _ringWidth,
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              SeeUColors.accent),
                          strokeCap: StrokeCap.round,
                        ),
                      );
                    },
                  )
                else
                  // Idle ring — subtle
                  SizedBox(
                    width: ringSize,
                    height: ringSize,
                    child: CustomPaint(
                      painter: _IdleRingPainter(ringWidth: _ringWidth),
                    ),
                  ),

                // ── Circle: video player / thumbnail / placeholder ─
                ClipOval(
                  child: SizedBox(
                    width: _size,
                    height: _size,
                    child: _initialized && _ctrl != null
                        // Playing: actual video
                        ? FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _ctrl!.value.size.width,
                              height: _ctrl!.value.size.height,
                              child: VideoPlayer(_ctrl!),
                            ),
                          )
                        : _thumbnail != null
                            // Thumbnail loaded — show it with dark vignette
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    _thumbnail!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                                  // Subtle dark vignette so play button pops
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        center: Alignment.center,
                                        radius: 0.8,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.35),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            // Placeholder while thumbnail loads — shimmer
                            : Builder(
                                builder: (ctx) {
                                  final c = ctx.seeuColors;
                                  return Shimmer.fromColors(
                                    baseColor: c.surface2,
                                    highlightColor: c.surface,
                                    child: Container(color: Colors.white),
                                  );
                                },
                              ),
                  ),
                ),

                // ── Play / pause / loading overlay ────────────────
                AnimatedOpacity(
                  opacity: _playing ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: _playing,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.46),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 1.5,
                        ),
                      ),
                      child: _loading
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              PhosphorIconsFill.play,
                              color: Colors.white,
                              size: 30,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Time + receipts — centered dark pill ──────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.sentTimeLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.isMine) ...[
                const SizedBox(width: 4),
                Icon(
                  (widget.isRead || widget.isDelivered)
                      ? PhosphorIconsBold.checks
                      : PhosphorIconsRegular.check,
                  size: 13,
                  color: widget.isRead
                      ? SeeUColors.accent
                      : Colors.white.withValues(alpha: 0.45),
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
// Idle ring painter — subtle gradient arc
// ---------------------------------------------------------------------------

class _IdleRingPainter extends CustomPainter {
  final double ringWidth;
  const _IdleRingPainter({required this.ringWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.08),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final r = (size.width - ringWidth) / 2;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), r, paint);
  }

  @override
  bool shouldRepaint(_IdleRingPainter old) => old.ringWidth != ringWidth;
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
