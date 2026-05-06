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

  // Current reel index
  int _idx = 0;

  // Playback state
  bool _playing = true;

  // Progress 0.0 → 1.0 for current reel (used by timer auto-advance)
  // ignore: unused_field
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

  // PageView controller
  late PageController _pageController;

  // Tap detection
  int _tapCount = 0;
  DateTime? _lastTap;

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

    _pageController = PageController();
    _loadReels();
  }

  Future<void> _loadReels() async {
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final token = await storage.read(key: 'access_token');

      final dio = Dio(BaseOptions(
        baseUrl: ApiEndpoints.videoBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      ));

      final response = await dio.get('/reels/feed', queryParameters: {'tab': 'foryou', 'limit': '20'});
      final data = response.data;
      final listData = data is Map && data.containsKey('data') ? data['data'] : data;

      final serverBase = ApiEndpoints.videoBaseUrl.replaceAll('/api/v1', '');

      if (mounted && listData is List) {
        setState(() {
          _reels = listData.map((j) {
            final r = j as Map<String, dynamic>;
            final user = r['user'] as Map<String, dynamic>? ?? {};
            final mediaUrls = (r['media_urls'] as List<dynamic>?)?.cast<String>() ?? [];
            // Use first media URL as video/photo
            var url = mediaUrls.isNotEmpty ? mediaUrls.first : '';
            if (url.startsWith('/')) url = serverBase + url;
            final tagRegex = RegExp(r'#(\w+)');
            final caption = r['caption']?.toString() ?? '';
            final tags = (r['hashtags'] as List<dynamic>?)?.cast<String>() ?? tagRegex.allMatches(caption).map((m) => m.group(1)!).toList();
            var avatarUrl = user['avatar_url']?.toString() ?? '';
            if (avatarUrl.startsWith('/')) avatarUrl = '${ApiEndpoints.baseUrl.replaceAll('/api/v1', '')}$avatarUrl';
            return _Reel(
              id: r['id']?.toString() ?? '',
              userId: r['user_id']?.toString() ?? '',
              username: user['username']?.toString() ?? '',
              fullName: user['full_name']?.toString() ?? '',
              avatarUrl: avatarUrl,
              isVerified: (user['is_verified'] ?? false) as bool,
              videoUrl: url,
              caption: caption,
              tags: tags,
              likes: r['likes_count'] ?? 0,
              comments: r['comments_count'] ?? 0,
              shares: r['shares_count'] ?? 0,
              duration: r['duration_seconds'] ?? 15,
            );
          }).toList();
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
    _pageController.dispose();
    super.dispose();
  }

  void _onProgressTick() {
    setState(() => _progress = _progressController.value);
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // Auto-advance to next reel
      if (_idx + 1 < _reels.length) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
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
    });
    _startProgress();
  }

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

  void _openComments(String postId) {
    // Pause video while comments are open
    final wasPlaying = _playing;
    if (_playing) _togglePlay();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(postId: postId),
    ).then((_) {
      if (wasPlaying && !_playing) _togglePlay();
    });
  }

  void _shareReel(_Reel reel) {
    final text = '${reel.caption}\n\nПосмотри рилс от @${reel.username} в SeeU!';
    // Use clipboard as a simple share fallback
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка скопирована'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: SeeUColors.darkBg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Vertical PageView ──
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _reels.length,
              onPageChanged: (i) => _goTo(i),
              itemBuilder: (context, index) {
                final reel = _reels[index];
                return GestureDetector(
                  onTapUp: _onTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ReelBackground(
                        reel: reel,
                        playing: _playing && _idx == index,
                        nextReel: index + 1 < _reels.length ? _reels[index + 1] : null,
                      ),
                      _Vignette(),
                    ],
                  ),
                );
              },
            ),

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

            // ── Title "Рилсы" at top ──
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: const Text(
                'Рилсы',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  shadows: [Shadow(color: Color(0x66000000), blurRadius: 8)],
                ),
              ),
            ),

            // ── Close button (top-right) ──
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
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
            if (_reels.isNotEmpty) ...[
              Builder(builder: (context) {
                final reel = _reels[_idx];
                final isLiked = _likedMap[reel.id] ?? false;
                final isSaved = _savedMap[reel.id] ?? false;
                final isFollowing = _followingMap[reel.username] ?? false;

                return Stack(
                  children: [
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
                        onComment: () => _openComments(reel.id),
                        onShare: () => _shareReel(reel),
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
                        onProfile: () => context.push('/profile/${reel.username}'),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ],
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

        // Share
        _RailButton(
          icon: const Icon(PhosphorIconsRegular.paperPlaneTilt,
              color: Colors.white, size: 26),
          label: 'отпр.',
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
                    'Оригинальный звук — @${reel.username}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
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

// ---------------------------------------------------------------------------
// Comments bottom sheet
// ---------------------------------------------------------------------------

class _CommentsSheet extends StatefulWidget {
  final String postId;
  const _CommentsSheet({required this.postId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  List<dynamic> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final token = await storage.read(key: 'access_token');
      final dio = Dio(BaseOptions(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ));
      final resp = await dio.get(
        '${ApiEndpoints.baseUrl}/posts/${widget.postId}/comments',
      );
      final data = resp.data;
      final list = data is Map && data.containsKey('data') ? data['data'] : data;
      if (mounted) {
        setState(() {
          _comments = list is List ? list : [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final token = await storage.read(key: 'access_token');
      final dio = Dio(BaseOptions(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ));
      await dio.post(
        '${ApiEndpoints.baseUrl}/posts/${widget.postId}/comments',
        data: {'text': text},
      );
      _loadComments();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1410),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          const Text(
            'Комментарии',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Divider(color: Colors.white12, height: 20),

          // Comments list
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: SeeUColors.accent, strokeWidth: 2,
                    ),
                  )
                : _comments.isEmpty
                    ? const Center(
                        child: Text(
                          'Пока нет комментариев',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) {
                          final c = _comments[i] as Map<String, dynamic>;
                          final user = c['user'] as Map<String, dynamic>? ?? {};
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFF2A1F18),
                                  child: Text(
                                    (user['username']?.toString() ?? '?')[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white70, fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '@${user['username'] ?? ''}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c['text']?.toString() ?? '',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // Input
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Комментировать...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendComment,
                  child: Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(
                      color: SeeUColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      PhosphorIconsBold.paperPlaneTilt,
                      color: Colors.white, size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
