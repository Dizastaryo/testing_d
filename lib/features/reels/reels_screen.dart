import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/design/tokens.dart';
import '../../core/models/post.dart';

// ---------------------------------------------------------------------------
// Data model (converted from Post)
// ---------------------------------------------------------------------------

class _Reel {
  final String id;
  final String userId;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final bool isVerified;
  final String videoUrl; // full URL to video
  final String caption;
  final List<String> tags;
  final int likes;
  final int comments;
  final int shares;
  final int duration;

  _Reel({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    this.isVerified = false,
    required this.videoUrl,
    required this.caption,
    required this.tags,
    required this.likes,
    required this.comments,
    this.shares = 0,
    this.duration = 30,
  });

  factory _Reel.fromPost(Post post) {
    final serverBase = ApiEndpoints.baseUrl.replaceAll('/api/v1', '');
    final videoMedia =
        post.media.where((m) => m.type == MediaType.video).toList();
    var url = videoMedia.isNotEmpty ? videoMedia.first.url : '';
    if (url.startsWith('/')) url = serverBase + url;
    final tagRegex = RegExp(r'#(\w+)');
    final tags = tagRegex
        .allMatches(post.caption ?? '')
        .map((m) => m.group(1)!)
        .toList();
    return _Reel(
      id: post.id,
      userId: post.author.id,
      username: post.author.username,
      fullName: post.author.fullName,
      avatarUrl: post.author.avatarUrl,
      isVerified: post.author.isVerified,
      videoUrl: url,
      caption: post.caption ?? '',
      tags: tags,
      likes: post.likesCount,
      comments: post.commentsCount,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}М';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}К';
  return '$n';
}

// ---------------------------------------------------------------------------
// Floating emoji particle
// ---------------------------------------------------------------------------

class _EmojiParticle {
  final String id;
  final String emoji;
  final double x;
  final double rotation;
  _EmojiParticle({
    required this.id,
    required this.emoji,
    required this.x,
    required this.rotation,
  });
}

class _HeartParticle {
  final String id;
  final double x;
  final double y;
  _HeartParticle({required this.id, required this.x, required this.y});
}

// ---------------------------------------------------------------------------
// Main ReelsScreen widget
// ---------------------------------------------------------------------------

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen>
    with TickerProviderStateMixin {
  // API loading state
  bool _loading = true;
  List<_Reel> _reels = [];

  // Current reel index & tab
  int _idx = 0;
  int _tabIdx = 1; // "Для тебя" active by default

  // Playback state
  bool _playing = true;

  // Progress 0.0 → 1.0 for current reel
  double _progress = 0.0;

  // Per-reel state maps
  final Map<String, bool> _likedMap = {};
  final Map<String, bool> _savedMap = {};
  final Map<String, bool> _followingMap = {};
  final Set<String> _expandedCaptions = {};

  // Animations
  late AnimationController _progressController;
  late AnimationController _pauseIndicatorController;
  late AnimationController _discController;

  // Reaction picker
  bool _reactionPickerVisible = false;

  // Floating emoji bursts
  final List<_EmojiParticle> _emojiBurst = [];

  // Double-tap hearts
  final List<_HeartParticle> _doubleTapHearts = [];

  // Swipe drag
  double _dragOffset = 0.0;
  bool _dragging = false;

  // Tap detection
  int _tapCount = 0;
  DateTime? _lastTap;

  final List<String> _tabs = ['Подписки', 'Для тебя', 'Рядом'];
  final List<String> _reactions = ['🔥', '❤️', '😂', '🤯', '👏', '✨'];

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..addListener(_onProgressTick)
      ..addStatusListener(_onProgressStatus);

    _pauseIndicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _discController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _loadReels();
  }

  Future<void> _loadReels() async {
    try {
      // Read auth token
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final token = await storage.read(key: 'access_token');

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      ));

      // Load from both feed and explore to get all video posts
      final results = await Future.wait([
        dio.get('${ApiEndpoints.baseUrl}/feed').catchError((_) => Response(requestOptions: RequestOptions(), data: {'data': []})),
        dio.get('${ApiEndpoints.baseUrl}/explore').catchError((_) => Response(requestOptions: RequestOptions(), data: {'data': []})),
      ]);

      final allPosts = <Post>[];
      final seenIds = <String>{};
      for (final response in results) {
        final data = response.data;
        final listData = data is Map && data.containsKey('data') ? data['data'] : data;
        if (listData is List) {
          for (final j in listData) {
            final post = Post.fromJson(j as Map<String, dynamic>);
            if (!seenIds.contains(post.id)) {
              seenIds.add(post.id);
              allPosts.add(post);
            }
          }
        }
      }

      final videoPosts = allPosts
          .where((p) => p.media.any((m) => m.type == MediaType.video))
          .toList();

      if (mounted) {
        setState(() {
          _reels = videoPosts.map((p) => _Reel.fromPost(p)).toList();
          _loading = false;
        });
        if (_reels.isNotEmpty) _startProgress();
      }
    } catch (e) {
      debugPrint('Reels load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _progressController
      ..removeListener(_onProgressTick)
      ..removeStatusListener(_onProgressStatus)
      ..dispose();
    _pauseIndicatorController.dispose();
    _discController.dispose();
    super.dispose();
  }

  void _onProgressTick() {
    setState(() => _progress = _progressController.value);
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _nextReel();
    }
  }

  void _startProgress() {
    if (_reels.isEmpty) return;
    _progressController.duration =
        Duration(seconds: _reels[_idx].duration);
    _progressController.reset();
    if (_playing) _progressController.forward();
  }

  void _goTo(int newIdx) {
    if (_reels.isEmpty) return;
    if (newIdx < 0 || newIdx >= _reels.length) return;
    setState(() {
      _idx = newIdx;
      _progress = 0.0;
      _dragOffset = 0.0;
    });
    _startProgress();
  }

  void _nextReel() => _goTo(_idx + 1);
  void _prevReel() => _goTo(_idx - 1);

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _progressController.forward();
      _discController.repeat();
      _pauseIndicatorController.reverse();
    } else {
      _progressController.stop();
      _discController.stop();
      _pauseIndicatorController.forward();
    }
  }

  void _toggleLike(String reelId) {
    final wasLiked = _likedMap[reelId] ?? false;
    setState(() => _likedMap[reelId] = !wasLiked);
    if (!wasLiked) _burstEmoji('❤️');
    _callApi(() async {
      final dio = await _authedDio();
      if (!wasLiked) {
        await dio.post('${ApiEndpoints.baseUrl}/posts/$reelId/like');
      } else {
        await dio.delete('${ApiEndpoints.baseUrl}/posts/$reelId/like');
      }
    });
  }

  void _toggleSave(String reelId) {
    final wasSaved = _savedMap[reelId] ?? false;
    setState(() => _savedMap[reelId] = !wasSaved);
    _callApi(() async {
      final dio = await _authedDio();
      if (!wasSaved) {
        await dio.post('${ApiEndpoints.baseUrl}/posts/$reelId/save');
      } else {
        await dio.delete('${ApiEndpoints.baseUrl}/posts/$reelId/save');
      }
    });
  }

  void _toggleFollow(String username) {
    final wasFollowing = _followingMap[username] ?? false;
    setState(() => _followingMap[username] = !wasFollowing);
    _callApi(() async {
      final dio = await _authedDio();
      if (!wasFollowing) {
        await dio.post('${ApiEndpoints.baseUrl}/users/$username/follow');
      } else {
        await dio.delete('${ApiEndpoints.baseUrl}/users/$username/follow');
      }
    });
  }

  Future<Dio> _authedDio() async {
    final dio = Dio();
    const storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
    final token = await storage.read(key: 'access_token');
    if (token != null) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }
    return dio;
  }

  void _callApi(Future<void> Function() fn) {
    fn().catchError((_) {});
  }

  void _burstEmoji(String emoji) {
    final rng = math.Random();
    final particle = _EmojiParticle(
      id: UniqueKey().toString(),
      emoji: emoji,
      x: 40.0 + rng.nextDouble() * 40.0,
      rotation: (rng.nextDouble() - 0.5) * 0.5,
    );
    setState(() => _emojiBurst.add(particle));
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _emojiBurst.remove(particle));
    });
  }

  void _doubleTapAt(Offset position) {
    if (_reels.isEmpty) return;
    final reel = _reels[_idx];
    final particle = _HeartParticle(
      id: UniqueKey().toString(),
      x: position.dx,
      y: position.dy,
    );
    setState(() => _doubleTapHearts.add(particle));
    if (!(_likedMap[reel.id] ?? false)) _toggleLike(reel.id);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _doubleTapHearts.remove(particle));
    });
  }

  void _onTap(TapUpDetails details) {
    final now = DateTime.now();
    if (_lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 280)) {
      // Double tap
      _tapCount = 0;
      _lastTap = null;
      _doubleTapAt(details.localPosition);
    } else {
      _tapCount = 1;
      _lastTap = now;
      Future.delayed(const Duration(milliseconds: 290), () {
        if (_tapCount == 1) _togglePlay();
        _tapCount = 0;
      });
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset += d.delta.dy;
      _dragging = true;
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    setState(() => _dragging = false);
    if (_dragOffset < -60) {
      _nextReel();
    } else if (_dragOffset > 60) {
      _prevReel();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  void _onLongPressLike() {
    setState(() => _reactionPickerVisible = true);
  }

  void _pickReaction(String emoji) {
    if (_reels.isEmpty) return;
    final reel = _reels[_idx];
    if (!(_likedMap[reel.id] ?? false)) _toggleLike(reel.id);
    _burstEmoji(emoji);
    setState(() => _reactionPickerVisible = false);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_loading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: SeeUColors.darkBg,
          body: const Center(
            child: CircularProgressIndicator(color: SeeUColors.accent),
          ),
        ),
      );
    }

    // Empty state
    if (_reels.isEmpty) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: SeeUColors.darkBg,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsRegular.videoCamera,
                    color: Colors.white54, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Нет рилсов',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/feed');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Назад',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final reel = _reels[_idx];
    final isLiked = _likedMap[reel.id] ?? false;
    final isSaved = _savedMap[reel.id] ?? false;
    final isFollowing = _followingMap[reel.username] ?? false;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: SeeUColors.darkBg,
        body: GestureDetector(
          onTapUp: _onTap,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Video background ──
              AnimatedSlide(
                offset: Offset(0, _dragging ? _dragOffset / 800 : 0),
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                child: _ReelBackground(
                  reel: reel,
                  playing: _playing,
                  nextReel: _idx + 1 < _reels.length ? _reels[_idx + 1] : null,
                ),
              ),

              // ── Top vignette + bottom vignette overlay ──
              _Vignette(),

              // ── Pause indicator ──
              if (!_playing) _PauseIndicator(),

              // ── Double-tap heart bursts ──
              ..._doubleTapHearts.map(
                (h) => Positioned(
                  left: h.x - 60,
                  top: h.y - 60,
                  child: _DoubleTapHeart(key: ValueKey(h.id)),
                ),
              ),

              // ── Progress bar at top ──
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 16,
                right: 16,
                child: _ProgressBar(
                  reels: _reels,
                  currentIdx: _idx,
                  progress: _progress,
                ),
              ),

              // ── Top tabs ──
              Positioned(
                top: MediaQuery.of(context).padding.top + 36,
                left: 0,
                right: 0,
                child: _TopTabs(
                  tabs: _tabs,
                  activeIdx: _tabIdx,
                  onTab: (i) => setState(() => _tabIdx = i),
                ),
              ),

              // ── Close button (top-right) ──
              Positioned(
                top: MediaQuery.of(context).padding.top + 38,
                right: 12,
                child: GestureDetector(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/feed');
                    }
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      PhosphorIconsBold.x,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),

              // ── Action rail (right) ──
              Positioned(
                right: 12,
                bottom: 110,
                child: _ActionRail(
                  reel: reel,
                  isLiked: isLiked,
                  isSaved: isSaved,
                  discController: _discController,
                  playing: _playing,
                  onLike: () => _toggleLike(reel.id),
                  onLongPressLike: _onLongPressLike,
                  onSave: () => _toggleSave(reel.id),
                  onComment: () {},
                  onRemix: () {},
                  onShare: () {},
                  onAudio: () {},
                ),
              ),

              // ── Reaction picker ──
              if (_reactionPickerVisible)
                Positioned(
                  right: 70,
                  bottom: 470,
                  child: _ReactionPicker(
                    reactions: _reactions,
                    onPick: _pickReaction,
                    onDismiss: () =>
                        setState(() => _reactionPickerVisible = false),
                  ),
                ),

              // ── Floating emoji burst ──
              if (_emojiBurst.isNotEmpty)
                Positioned(
                  right: 28,
                  bottom: 540,
                  width: 80,
                  height: 200,
                  child: _EmojiBurstLayer(particles: _emojiBurst),
                ),

              // ── Bottom info card ──
              Positioned(
                left: 14,
                right: 80,
                bottom: 90,
                child: _BottomCard(
                  reel: reel,
                  isFollowing: isFollowing,
                  captionExpanded: _expandedCaptions.contains(reel.id),
                  onFollow: () => _toggleFollow(reel.username),
                  onToggleCaption: () {
                    setState(() {
                      if (_expandedCaptions.contains(reel.id)) {
                        _expandedCaptions.remove(reel.id);
                      } else {
                        _expandedCaptions.add(reel.id);
                      }
                    });
                  },
                  onAudio: () {},
                  onProfile: () {},
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
// Reel background — video player
// ---------------------------------------------------------------------------

class _ReelBackground extends StatefulWidget {
  final _Reel reel;
  final bool playing;
  final _Reel? nextReel; // preload next
  const _ReelBackground({
    required this.reel,
    this.playing = true,
    this.nextReel,
  });

  @override
  State<_ReelBackground> createState() => _ReelBackgroundState();
}

class _ReelBackgroundState extends State<_ReelBackground> {
  VideoPlayerController? _controller;
  VideoPlayerController? _nextController; // preloaded
  bool _initialized = false;
  bool _hasError = false;
  String? _preloadedUrl;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _preloadNext();
  }

  void _initVideo() {
    _hasError = false;
    _initialized = false;

    // Check if we already preloaded this video
    if (_nextController != null &&
        _preloadedUrl == widget.reel.videoUrl) {
      _controller = _nextController;
      _nextController = null;
      _preloadedUrl = null;
      if (_controller!.value.isInitialized) {
        _initialized = true;
        _controller!.setLooping(true);
        if (widget.playing) _controller!.play();
        if (mounted) setState(() {});
        return;
      }
    }

    _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.reel.videoUrl),
      httpHeaders: const {'Connection': 'keep-alive'},
    );
    _controller!
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          if (widget.playing) {
            _controller!.play();
          }
        }
      }).catchError((e) {
        debugPrint('Video init error: $e');
        if (mounted) setState(() => _hasError = true);
      });
  }

  void _preloadNext() {
    final nextUrl = widget.nextReel?.videoUrl;
    if (nextUrl == null || nextUrl.isEmpty || nextUrl == _preloadedUrl) return;

    _nextController?.dispose();
    _preloadedUrl = nextUrl;
    _nextController = VideoPlayerController.networkUrl(
      Uri.parse(nextUrl),
      httpHeaders: const {'Connection': 'keep-alive'},
    );
    _nextController!.initialize().catchError((e) {
      debugPrint('Preload error: $e');
      _nextController?.dispose();
      _nextController = null;
      _preloadedUrl = null;
    });
  }

  @override
  void didUpdateWidget(covariant _ReelBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reel changed → switch video
    if (oldWidget.reel.id != widget.reel.id) {
      _controller?.dispose();
      _controller = null;
      _initVideo();
      _preloadNext();
      return;
    }

    // Play/pause sync
    if (oldWidget.playing != widget.playing && _initialized && _controller != null) {
      if (widget.playing) {
        _controller!.play();
      } else {
        _controller!.pause();
      }
    }

    // Preload next changed
    if (oldWidget.nextReel?.id != widget.nextReel?.id) {
      _preloadNext();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _nextController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white38, size: 48),
              SizedBox(height: 12),
              Text(
                'Не удалось загрузить видео',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    if (!_initialized || _controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white24,
            strokeWidth: 2.5,
          ),
        ),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vignette overlay
// ---------------------------------------------------------------------------

class _Vignette extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.22, 0.60, 1.0],
            colors: [
              Color(0xCC0E0C0A),
              Color(0x000E0C0A),
              Color(0x000E0C0A),
              Color(0xD90E0C0A),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pause indicator
// ---------------------------------------------------------------------------

class _PauseIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (_, v, child) => Transform.scale(
            scale: 0.7 + 0.3 * v,
            child: Opacity(opacity: v, child: child),
          ),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 42),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Double-tap heart pop animation
// ---------------------------------------------------------------------------

class _DoubleTapHeart extends StatefulWidget {
  const _DoubleTapHeart({super.key});

  @override
  State<_DoubleTapHeart> createState() => _DoubleTapHeartState();
}

class _DoubleTapHeartState extends State<_DoubleTapHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.3, end: 1.2)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.2, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 30),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 30),
    ]).animate(_ctrl);
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Icon(
            PhosphorIconsBold.heart,
            size: 120,
            color: SeeUColors.like,
            shadows: const [
              Shadow(color: Color(0x99FF3B6B), blurRadius: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress bar at top
// ---------------------------------------------------------------------------

class _ProgressBar extends StatelessWidget {
  final List<_Reel> reels;
  final int currentIdx;
  final double progress;

  const _ProgressBar({
    required this.reels,
    required this.currentIdx,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(reels.length, (i) {
        double fillFraction;
        if (i < currentIdx) {
          fillFraction = 1.0;
        } else if (i == currentIdx) {
          fillFraction = progress;
        } else {
          fillFraction = 0.0;
        }
        return Expanded(
          child: Container(
            height: 2.5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fillFraction.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Top tabs
// ---------------------------------------------------------------------------

class _TopTabs extends StatelessWidget {
  final List<String> tabs;
  final int activeIdx;
  final ValueChanged<int> onTab;

  const _TopTabs({
    required this.tabs,
    required this.activeIdx,
    required this.onTab,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: tabs.asMap().entries.map((e) {
        final isActive = e.key == activeIdx;
        return GestureDetector(
          onTap: () => onTab(e.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.value,
                  style: TextStyle(
                    fontFamily: 'Segoe UI',
                    fontSize: 15,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.6),
                    shadows: const [
                      Shadow(color: Color(0x4D000000), blurRadius: 8),
                    ],
                    letterSpacing: -0.01 * 15,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: isActive ? 4 : 0,
                  height: isActive ? 4 : 0,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Action rail (right side)
// ---------------------------------------------------------------------------

class _ActionRail extends StatelessWidget {
  final _Reel reel;
  final bool isLiked;
  final bool isSaved;
  final AnimationController discController;
  final bool playing;
  final VoidCallback onLike;
  final VoidCallback onLongPressLike;
  final VoidCallback onSave;
  final VoidCallback onComment;
  final VoidCallback onRemix;
  final VoidCallback onShare;
  final VoidCallback onAudio;

  const _ActionRail({
    required this.reel,
    required this.isLiked,
    required this.isSaved,
    required this.discController,
    required this.playing,
    required this.onLike,
    required this.onLongPressLike,
    required this.onSave,
    required this.onComment,
    required this.onRemix,
    required this.onShare,
    required this.onAudio,
  });

  @override
  Widget build(BuildContext context) {
    final likeCount = reel.likes + (isLiked ? 1 : 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like button (with long-press → reaction picker)
        GestureDetector(
          onLongPress: onLongPressLike,
          child: _RailButton(
            icon: Icon(
              isLiked ? PhosphorIconsBold.heart : PhosphorIconsRegular.heart,
              color: isLiked ? SeeUColors.like : Colors.white,
              size: 28,
            ),
            label: _fmt(likeCount),
            highlight: isLiked,
            highlightColor: const Color(0x2EFF3B6B),
            onTap: onLike,
          ),
        ),
        const SizedBox(height: 22),

        // Comments
        _RailButton(
          icon: const Icon(PhosphorIconsRegular.chatCircle,
              color: Colors.white, size: 26),
          label: _fmt(reel.comments),
          onTap: onComment,
        ),
        const SizedBox(height: 22),

        // Remix
        _RailButton(
          icon: const Icon(PhosphorIconsRegular.arrowsClockwise,
              color: Colors.white, size: 26),
          label: 'ремикс',
          onTap: onRemix,
        ),
        const SizedBox(height: 22),

        // Share
        _RailButton(
          icon: const Icon(PhosphorIconsRegular.paperPlaneTilt,
              color: Colors.white, size: 26),
          label: _fmt(reel.shares),
          onTap: onShare,
        ),
        const SizedBox(height: 22),

        // Bookmark / save
        _RailButton(
          icon: Icon(
            isSaved
                ? PhosphorIconsBold.bookmarkSimple
                : PhosphorIconsRegular.bookmarkSimple,
            color: isSaved ? SeeUColors.amber : Colors.white,
            size: 26,
          ),
          highlight: isSaved,
          highlightColor: const Color(0x2EFFB547),
          onTap: onSave,
        ),
        const SizedBox(height: 22),

        // Spinning audio disc
        GestureDetector(
          onTap: onAudio,
          child: AnimatedBuilder(
            animation: discController,
            builder: (_, child) => Transform.rotate(
              angle: playing ? discController.value * 2 * math.pi : 0.0,
              child: child,
            ),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [SeeUColors.accent, Color(0xFFFFB547)],
                ),
              ),
              padding: const EdgeInsets.all(3),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0xFF1A1410), Color(0xFF2A1F18)],
                    stops: [0.3, 1.0],
                  ),
                ),
                child: const Center(
                  child: Icon(PhosphorIconsBold.musicNote,
                      color: SeeUColors.amber, size: 14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rail button (icon + optional label)
// ---------------------------------------------------------------------------

class _RailButton extends StatefulWidget {
  final Widget icon;
  final String? label;
  final bool highlight;
  final Color highlightColor;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    this.label,
    this.highlight = false,
    this.highlightColor = const Color(0x40000000),
    required this.onTap,
  });

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.88,
      upperBound: 1.0,
    );
    _ctrl.value = 1.0;
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _ctrl.reverse();
  void _onTapUp(TapUpDetails _) {
    _ctrl.forward();
    widget.onTap();
  }

  void _onTapCancel() => _ctrl.forward();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: AnimatedBuilder(
            animation: _scale,
            builder: (_, child) =>
                Transform.scale(scale: _scale.value, child: child),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.highlight
                    ? widget.highlightColor
                    : Colors.black.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(child: widget.icon),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.label!,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              shadows: [Shadow(color: Color(0x80000000), blurRadius: 4)],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reaction picker
// ---------------------------------------------------------------------------

class _ReactionPicker extends StatelessWidget {
  final List<String> reactions;
  final ValueChanged<String> onPick;
  final VoidCallback onDismiss;

  const _ReactionPicker({
    required this.reactions,
    required this.onPick,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (_, v, child) =>
          Transform.scale(scale: v, alignment: Alignment.bottomRight, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: reactions.map((em) {
            return GestureDetector(
              onTap: () => onPick(em),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                child: Text(em, style: const TextStyle(fontSize: 22)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Emoji burst layer
// ---------------------------------------------------------------------------

class _EmojiBurstLayer extends StatelessWidget {
  final List<_EmojiParticle> particles;
  const _EmojiBurstLayer({required this.particles});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: particles.map((p) {
        return _FloatingEmoji(
          key: ValueKey(p.id),
          emoji: p.emoji,
          x: p.x,
          rotation: p.rotation,
        );
      }).toList(),
    );
  }
}

class _FloatingEmoji extends StatefulWidget {
  final String emoji;
  final double x;
  final double rotation;
  const _FloatingEmoji({
    super.key,
    required this.emoji,
    required this.x,
    required this.rotation,
  });

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _offset;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
    _offset = Tween<double>(begin: 0.0, end: -180.0)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_ctrl);
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 65),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Positioned(
        right: widget.x,
        bottom: _offset.value,
        child: Opacity(
          opacity: _opacity.value,
          child: Transform.rotate(
            angle: widget.rotation,
            child: Text(widget.emoji,
                style: const TextStyle(fontSize: 28)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom card
// ---------------------------------------------------------------------------

class _BottomCard extends StatelessWidget {
  final _Reel reel;
  final bool isFollowing;
  final bool captionExpanded;
  final VoidCallback onFollow;
  final VoidCallback onToggleCaption;
  final VoidCallback onAudio;
  final VoidCallback onProfile;

  const _BottomCard({
    required this.reel,
    required this.isFollowing,
    required this.captionExpanded,
    required this.onFollow,
    required this.onToggleCaption,
    required this.onAudio,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final cap = reel.caption;
    final isLong = cap.length > 80;
    final shown =
        (captionExpanded || !isLong) ? cap : '${cap.substring(0, 80)}…';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Creator row
        Row(
          children: [
            GestureDetector(
              onTap: onProfile,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [SeeUColors.accent, Color(0xFFFFB547)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        reel.username.isNotEmpty
                            ? reel.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '@${reel.username}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: Color(0x66000000), blurRadius: 4),
                      ],
                    ),
                  ),
                  if (reel.isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(PhosphorIconsBold.seal,
                        color: SeeUColors.amber, size: 16),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Follow button
            GestureDetector(
              onTap: onFollow,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isFollowing
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isFollowing
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white,
                  ),
                ),
                child: Text(
                  isFollowing ? 'Подписан' : 'Подписаться',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isFollowing
                        ? Colors.white
                        : const Color(0xFF161310),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Caption
        GestureDetector(
          onTap: onToggleCaption,
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.white,
                shadows: [Shadow(color: Color(0x80000000), blurRadius: 4)],
              ),
              children: [
                ..._buildCaptionSpans(shown),
                if (isLong && !captionExpanded)
                  const TextSpan(
                    text: ' ещё',
                    style: TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Tags
        if (reel.tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: reel.tags.map((t) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '#$t',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 10),

        // Audio strip
        GestureDetector(
          onTap: onAudio,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.musicNote,
                    color: Colors.white, size: 14),
                const SizedBox(width: 8),
                // Mini waveform
                Row(
                  children: List.generate(4, (i) {
                    final h = [8.0, 14.0, 10.0, 16.0][i];
                    return Container(
                      width: 2,
                      height: h,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    );
                  }),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    reel.username,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(PhosphorIconsRegular.caretRight,
                    color: Colors.white, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<TextSpan> _buildCaptionSpans(String text) {
    final spans = <TextSpan>[];
    final parts = text.split(' ');
    for (int i = 0; i < parts.length; i++) {
      final word = parts[i];
      final isTag = word.startsWith('#');
      spans.add(TextSpan(
        text: i == 0 ? word : ' $word',
        style: isTag
            ? const TextStyle(
                color: SeeUColors.amber,
                fontWeight: FontWeight.w600,
              )
            : null,
      ));
    }
    return spans;
  }
}
