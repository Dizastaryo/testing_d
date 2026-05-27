import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/design/design.dart';
import '../../video/fullscreen_video_player.dart';

// --- Action button (tappable) ------------------------------------------------

class PostActionButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;

  const PostActionButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.90,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.small),
          boxShadow: SeeUShadows.sm,
        ),
        child: Center(child: IconTheme(data: IconThemeData(size: 22, color: c.ink), child: icon)),
      ),
    );
  }
}

// --- Action button raw (no Tappable wrapper) ---------------------------------

class PostActionButtonRaw extends StatelessWidget {
  final Widget icon;
  const PostActionButtonRaw({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.small),
        boxShadow: SeeUShadows.sm,
      ),
      child: Center(child: icon),
    );
  }
}

// --- Expandable caption ------------------------------------------------------

class PostExpandableCaption extends StatefulWidget {
  final String postId;
  final String username;
  final String caption;
  const PostExpandableCaption({super.key, required this.postId, required this.username, required this.caption});

  @override
  State<PostExpandableCaption> createState() => _PostExpandableCaptionState();
}

class _PostExpandableCaptionState extends State<PostExpandableCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    const maxLength = 100;
    final isLong = widget.caption.length > maxLength;
    return RichText(
      text: TextSpan(children: [
        TextSpan(text: '${widget.username} ', style: SeeUTypography.body.copyWith(fontWeight: FontWeight.w700)),
        TextSpan(
          text: _expanded || !isLong ? widget.caption : '${widget.caption.substring(0, maxLength)}...',
          style: SeeUTypography.body),
        if (isLong && !_expanded)
          WidgetSpan(child: GestureDetector(
            onTap: () => setState(() => _expanded = true),
            child: Text(' ещё', style: SeeUTypography.body.copyWith(color: c.ink3)))),
      ]),
    );
  }
}

// --- Feed video player -------------------------------------------------------

class FeedVideoPlayer extends StatefulWidget {
  final String url;
  const FeedVideoPlayer({super.key, required this.url});

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _isMuted = true;
  bool _suspendedForFullscreen = false;

  late final Key _visibilityKey =
      Key('feed-video-${widget.url.hashCode}-${identityHashCode(this)}');

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url), httpHeaders: const {'Connection': 'keep-alive'});
    _controller!
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      }).catchError((e) {
        debugPrint('Feed video error: $e');
        if (mounted) setState(() => _hasError = true);
      });
  }

  @override
  void dispose() { _controller?.dispose(); super.dispose(); }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() => _isMuted = !_isMuted);
    _controller!.setVolume(_isMuted ? 0 : 1);
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!_initialized || _hasError || _suspendedForFullscreen) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final visible = info.visibleFraction > 0.5;
    if (visible && !ctrl.value.isPlaying) {
      ctrl.play();
    } else if (!visible && ctrl.value.isPlaying) {
      ctrl.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(child: GestureDetector(
          onTap: () {
            setState(() { _hasError = false; _initialized = false; });
            _controller?.dispose();
            _initController();
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(PhosphorIconsRegular.arrowClockwise, color: Colors.white38, size: 40),
            const SizedBox(height: 8),
            Text('Нажмите для повтора', style: SeeUTypography.caption.copyWith(color: Colors.white38, fontSize: 12)),
          ]),
        )),
      );
    }
    if (!_initialized || _controller == null) {
      return Container(color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2)));
    }
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: () {
          _suspendedForFullscreen = true;
          _controller?.pause();
          Navigator.of(context).push(PageRouteBuilder(
            opaque: false,
            pageBuilder: (_, __, ___) => FullscreenVideoPlayer(url: widget.url),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
          )).then((_) { if (!mounted) return; _suspendedForFullscreen = false; });
        },
        child: Stack(fit: StackFit.expand, children: [
          FittedBox(fit: BoxFit.cover,
            child: SizedBox(width: _controller!.value.size.width, height: _controller!.value.size.height,
              child: VideoPlayer(_controller!))),
          Positioned(bottom: 8, right: 8, child: GestureDetector(
            onTap: _toggleMute,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: Icon(_isMuted ? PhosphorIconsRegular.speakerSlash : PhosphorIconsRegular.speakerHigh, color: Colors.white, size: 18),
            ),
          )),
        ]),
      ),
    );
  }
}
