import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(SeeURadii.small),
          border: Border.all(color: c.line, width: 0.5),
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
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(SeeURadii.small),
        border: Border.all(color: c.line, width: 0.5),
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
  final String? thumbnailUrl;
  const FeedVideoPlayer({super.key, required this.url, this.thumbnailUrl});

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _isMuted = true;
  bool _suspendedForFullscreen = false;
  // Windowing: a controller only exists while the cell is in the viewport
  // (visibleFraction > 0.5). Mirrors publication_viewer's bounded-controller
  // approach so the feed never holds many live decoders at once.
  bool _active = false;
  // Guards against init races / dispose-after-async: each (re)create bumps the
  // token; a pending initialize() whose token is stale tears itself down.
  int _initToken = 0;

  late final Key _visibilityKey =
      Key('feed-video-${widget.url.hashCode}-${identityHashCode(this)}');

  @override
  void initState() {
    super.initState();
    // No controller until the cell scrolls into the viewport window.
  }

  Future<void> _createController() async {
    if (_controller != null) return;
    final token = ++_initToken;
    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.url), httpHeaders: const {'Connection': 'keep-alive'});
    _controller = ctrl;
    ctrl
      ..setLooping(true)
      ..setVolume(_isMuted ? 0 : 1);
    try {
      await ctrl.initialize();
      if (!mounted || token != _initToken) {
        // Superseded (disposed / left viewport) while awaiting — tear down.
        await ctrl.dispose();
        return;
      }
      setState(() => _initialized = true);
      if (_active && !_suspendedForFullscreen) ctrl.play();
    } catch (e) {
      debugPrint('Feed video error: $e');
      if (!mounted || token != _initToken) {
        await ctrl.dispose();
        return;
      }
      setState(() => _hasError = true);
    }
  }

  /// Tears down the controller and reverts to the thumbnail. Invalidates any
  /// in-flight initialize() via the token bump so it disposes itself.
  void _disposeController() {
    _initToken++;
    final ctrl = _controller;
    _controller = null;
    _initialized = false;
    ctrl?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() => _isMuted = !_isMuted);
    _controller!.setVolume(_isMuted ? 0 : 1);
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (_suspendedForFullscreen) return;
    final shouldActivate = info.visibleFraction > 0.5;
    if (shouldActivate == _active) return;
    _active = shouldActivate;
    if (shouldActivate) {
      if (_controller == null) {
        if (!_hasError) _createController();
      } else if (_initialized && !_controller!.value.isPlaying) {
        _controller!.play();
      }
    } else {
      // Left the viewport window — free the decoder, fall back to thumbnail.
      if (mounted) {
        setState(_disposeController);
      } else {
        _disposeController();
      }
    }
  }

  Widget _buildThumbnail() {
    final thumb = widget.thumbnailUrl;
    if (thumb != null && thumb.isNotEmpty) {
      final cacheWidth = ((MediaQuery.sizeOf(context).width - 32) *
              MediaQuery.devicePixelRatioOf(context))
          .round();
      return CachedNetworkImage(
        imageUrl: thumb,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        maxWidthDiskCache: cacheWidth,
        placeholder: (_, __) => Container(color: Colors.black),
        errorWidget: (_, __, ___) => Container(color: Colors.black),
      );
    }
    return Container(color: Colors.black);
  }

  @override
  Widget build(BuildContext context) {
    // VisibilityDetector must always be mounted so we can detect when the cell
    // enters/leaves the viewport window — even while showing the thumbnail.
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(child: GestureDetector(
          onTap: () {
            _disposeController();
            setState(() => _hasError = false);
            _active = true;
            _createController();
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(PhosphorIconsRegular.arrowClockwise, color: Colors.white70, size: 40),
            const SizedBox(height: 8),
            Text('Нажмите для повтора', style: SeeUTypography.caption.copyWith(color: Colors.white70)),
          ]),
        )),
      );
    }
    if (!_initialized || _controller == null) {
      // Off-screen or still loading — show the thumbnail (no live decoder).
      return _buildThumbnail();
    }
    return GestureDetector(
      onTap: () {
        _suspendedForFullscreen = true;
        _controller?.pause();
        Navigator.of(context).push(PageRouteBuilder(
          opaque: false,
          pageBuilder: (_, __, ___) => FullscreenVideoPlayer(url: widget.url),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        )).then((_) {
          if (!mounted) return;
          _suspendedForFullscreen = false;
          if (_active && _initialized) _controller?.play();
        });
      },
      child: Stack(fit: StackFit.expand, children: [
        FittedBox(fit: BoxFit.cover,
          child: SizedBox(width: _controller!.value.size.width, height: _controller!.value.size.height,
            child: VideoPlayer(_controller!))),
        Positioned(bottom: 8, right: 8, child: SeeUGlassCircleButton(
          onTap: _toggleMute,
          size: 44,
          blur: 18,
          icon: Icon(_isMuted ? PhosphorIconsRegular.speakerSlash : PhosphorIconsRegular.speakerHigh, color: Colors.white, size: 18),
        )),
      ]),
    );
  }
}
