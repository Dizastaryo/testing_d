import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';
import '../../../core/providers/realtime_provider.dart';
import '../../../core/providers/story_provider.dart';
import 'story_poll_overlay.dart';
import 'story_viewers_sheet.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/models/story.dart';
import '../../stories/text_story_compose_screen.dart';
import 'story_circle.dart';

class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storyState = ref.watch(storyProvider);
    final authState = ref.watch(authProvider);
    final me = authState.user;

    if (storyState.isLoading) {
      return _buildShimmer();
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: storyState.storyGroups.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: StoryCircle(
                imageUrl: me?.avatarUrl,
                username: 'Ваша история',
                isOwn: true,
                onTap: () => context.push('/story/create'),
              ),
            );
          }
          final group = storyState.storyGroups[index - 1];
          // PROFILE-3: зелёный ring если в группе есть хоть одна CF-story.
          final hasCloseFriends =
              group.stories.any((s) => s.isCloseFriendsOnly);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: StoryCircle(
              imageUrl: group.author.avatarUrl,
              username: group.author.username,
              isSeen: group.allSeen,
              hasCloseFriendsStory: hasCloseFriends,
              onTap: () => _openStoryViewer(
                  context, storyState.storyGroups, index - 1, me?.id),
            ),
          );
        },
      ),
    );
  }

  void _openStoryViewer(
      BuildContext context, List<StoryGroup> groups, int groupIndex, String? currentUserId) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => StoryViewerRoute(
          groups: groups,
          initialGroupIndex: groupIndex,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return SizedBox(
      height: 100,
      child: SeeUShimmer(
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: 6,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShimmerBox(width: 68, height: 68, radius: SeeURadii.pill),
                  const SizedBox(height: 5),
                  ShimmerBox(width: 52, height: 10, radius: 5),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Inline story viewer route wrapper
class StoryViewerRoute extends StatelessWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;
  final String? currentUserId;

  const StoryViewerRoute({
    super.key,
    required this.groups,
    required this.initialGroupIndex,
    this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return SwipeToDismiss(
      downOnly: true,
      child: _InlineStoryViewer(
        groups: groups,
        initialGroupIndex: initialGroupIndex,
        currentUserId: currentUserId,
      ),
    );
  }
}

class _InlineStoryViewer extends ConsumerStatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;
  final String? currentUserId;

  const _InlineStoryViewer({
    required this.groups,
    required this.initialGroupIndex,
    this.currentUserId,
  });

  @override
  ConsumerState<_InlineStoryViewer> createState() =>
      _InlineStoryViewerState();
}

class _InlineStoryViewerState extends ConsumerState<_InlineStoryViewer>
    with TickerProviderStateMixin {
  late int _groupIndex;
  late int _storyIndex;
  late AnimationController _progressController;
  // H24: _pageController removed — not attached to any PageView; _groupIndex is changed directly via setState

  // Reply state
  bool _isReplyOpen = false;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();

  // Like state: track liked story IDs
  final Set<String> _likedStoryIds = {};

  /// Per-session realtime override of `views_count`. When the server
  /// pushes `story.view.added`, we stash the new count here and use it in
  /// build over `widget.groups[i].viewsCount`. Stays empty until at least
  /// one event arrives. Cleared on dispose with the State itself.
  final Map<String, int> _liveViewsOverride = {};
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  // Like animation
  AnimationController? _likeAnimController;
  Animation<double>? _likeScaleAnim;
  bool _showCenterHeart = false;

  // Emoji reaction animation
  AnimationController? _emojiAnimController;
  Animation<double>? _emojiScaleAnim;
  String? _activeEmoji;

  // Heart button scale animation
  AnimationController? _heartBtnAnimController;
  Animation<double>? _heartBtnScaleAnim;

  // Swipe tracking
  bool _isSwiping = false;
  // M17: Track long-press state to prevent onTapUp from firing after long-press
  bool _isLongPressing = false;

  // ── Audio playback ─────────────────────────────────────────────────────
  // Photo-stories с audio_track_id играют Spotify-style фоновую музыку.
  // Кэш track-метадаты по UUID, чтобы повторно не дёргать /audio-tracks/:id
  // при возврате к уже-проигранной story.
  AudioPlayer? _audioPlayer;
  final Map<String, AudioTrack?> _audioCache = {};
  String? _currentLoadedTrackId; // последний загруженный URL в плеер

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _storyIndex = 0;

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        if (!mounted) return;
        // Defensive guard: even if the progress controller somehow finishes
        // (race between `.stop()` in `_openReply` and a pending status tick,
        // a hot-reload, etc.) while the reply sheet is open, do NOT advance
        // — the user is mid-typing and getting yanked to the next story is
        // the bug audit-flagged in P1.
        if (_isReplyOpen) return;
        _nextStory();
      });
    _progressController.forward();

    // Audio: пробуем стартануть music для первой story в фоне (не ждём).
    _audioPlayer = AudioPlayer();
    _syncAudio();

    // Subscribe to realtime view-count pushes (`story.view.added`) so the
    // open viewer's «X views» badge updates live as new viewers arrive,
    // instead of being stale from when the sheet was opened.
    _wsSub = ref.listenManual<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.type != 'story.view.added' || evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          final id = p['story_id']?.toString() ?? '';
          final n = p['views_count'];
          if (id.isEmpty || n is! num) return;
          if (!mounted) return;
          setState(() => _liveViewsOverride[id] = n.toInt());
        });
      },
    );

    // Center heart animation
    _likeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() => _showCenterHeart = false);
        }
      });
    _likeScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.4), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(CurvedAnimation(
      parent: _likeAnimController!,
      curve: Curves.easeOut,
    ));

    // Emoji reaction animation
    _emojiAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() => _activeEmoji = null);
        }
      });
    _emojiScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.6), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.6, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(CurvedAnimation(
      parent: _emojiAnimController!,
      curve: Curves.easeOut,
    ));

    // Heart button bounce
    _heartBtnAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heartBtnScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _heartBtnAnimController!,
      curve: Curves.easeInOut,
    ));

    // M14: Named listener so it can be removed in dispose
    _replyController.addListener(_onReplyChanged);
  }

  // M14: Named reply listener for proper cleanup
  void _onReplyChanged() => setState(() {});

  @override
  void dispose() {
    _wsSub?.close();
    _progressController.dispose();
    _likeAnimController?.dispose();
    _emojiAnimController?.dispose();
    _heartBtnAnimController?.dispose();
    _replyController.removeListener(_onReplyChanged);
    _replyController.dispose();
    _replyFocusNode.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  StoryGroup get _currentGroup => widget.groups[_groupIndex];
  Story get _currentStory => _currentGroup.stories[_storyIndex];

  /// STORY-3: вызывается из _StoryPollOverlay после успешного POST.
  /// Локально обновляет story.poll чтобы вся UI увидела новые counts без
  /// re-fetch. Группа stories хранится в `widget.groups[_groupIndex].stories`,
  /// но Story.copyWith создаёт новый instance — заменяем в списке.
  void _updateStoryPoll(String storyId, StoryPoll updatedPoll) {
    final stories = widget.groups[_groupIndex].stories;
    for (var i = 0; i < stories.length; i++) {
      if (stories[i].id == storyId) {
        stories[i] = stories[i].copyWith(poll: updatedPoll);
        if (mounted) setState(() {});
        return;
      }
    }
  }

  void _nextStory() {
    if (_isReplyOpen) return;
    _progressController.reset();
    if (_storyIndex < _currentGroup.stories.length - 1) {
      setState(() => _storyIndex++);
      // M15: mounted check before forward after potential navigation
      if (!mounted) return;
      _progressController.forward();
    } else if (_groupIndex < widget.groups.length - 1) {
      // H24: setState directly, no PageController needed
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      if (!mounted) return;
      _progressController.forward();
    } else {
      Navigator.of(context).pop();
    }
    _syncAudio();
  }

  void _prevStory() {
    if (_isReplyOpen) return;
    _progressController.reset();
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
    } else if (_groupIndex > 0) {
      // H24: setState directly, no PageController needed
      setState(() {
        _groupIndex--;
        _storyIndex = widget.groups[_groupIndex].stories.length - 1;
      });
    }
    if (!mounted) return;
    _progressController.forward();
    _syncAudio();
  }

  void _nextGroup() {
    if (_groupIndex < widget.groups.length - 1) {
      _progressController.reset();
      // H24: setState directly, no PageController needed
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      if (!mounted) return;
      _progressController.forward();
      _syncAudio();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prevGroup() {
    if (_groupIndex > 0) {
      _progressController.reset();
      // H24: setState directly, no PageController needed
      setState(() {
        _groupIndex--;
        _storyIndex = 0;
      });
      if (!mounted) return;
      _progressController.forward();
      _syncAudio();
    }
  }

  /// Подгоняет аудио-плеер под current story:
  /// - audio_track_id null или mediaType=video → stop + clear (видео-сторис
  ///   звучит сам, дублировать не надо).
  /// - есть id → fetch из кэша или /audio-tracks/:id → setUrl + play.
  Future<void> _syncAudio() async {
    final story = _currentStory;
    final player = _audioPlayer;
    if (player == null) return;

    final trackId = story.audioTrackId;
    if (trackId == null || trackId.isEmpty ||
        story.mediaType == StoryMediaType.video) {
      if (_currentLoadedTrackId != null) {
        await player.stop();
        _currentLoadedTrackId = null;
      }
      return;
    }
    if (_currentLoadedTrackId == trackId && player.playing) return;

    // Load (через кэш) и play.
    AudioTrack? track = _audioCache[trackId];
    if (track == null && !_audioCache.containsKey(trackId)) {
      try {
        final api = ref.read(apiClientProvider);
        final r = await api.get(ApiEndpoints.audioTrackById(trackId));
        final data = r.data is Map && (r.data as Map).containsKey('data')
            ? r.data['data']
            : r.data;
        if (data is Map<String, dynamic>) {
          track = AudioTrack.fromJson(data);
        }
      } catch (_) {
        track = null;
      }
      _audioCache[trackId] = track;
    }
    if (track == null || track.audioUrl.isEmpty) return;
    if (!mounted) return;
    try {
      await player.setUrl(track.audioUrl);
      // MUSIC-7: seek на offset до play если juzер выбрал не-начало трека.
      if (story.audioStartSeconds > 0) {
        await player.seek(Duration(seconds: story.audioStartSeconds));
      }
      _currentLoadedTrackId = trackId;
      await player.play();
      if (mounted) setState(() {});
    } catch (_) {/* network/decoding error — silent */}
  }

  void _openReply() {
    _progressController.stop();
    setState(() => _isReplyOpen = true);
    _replyFocusNode.requestFocus();
  }

  void _closeReply() {
    _replyFocusNode.unfocus();
    _replyController.clear();
    setState(() => _isReplyOpen = false);
    _progressController.forward();
  }

  void _sendReply() {
    if (_replyController.text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    _replyController.clear();
    _replyFocusNode.unfocus();
    setState(() => _isReplyOpen = false);
    _progressController.forward();
    // M16: mounted check before ScaffoldMessenger
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Сообщение отправлено'),
        backgroundColor: SeeUColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleLike() {
    HapticFeedback.mediumImpact();
    final storyId = _currentStory.id;
    final bool wasLiked = _likedStoryIds.contains(storyId);
    setState(() {
      if (wasLiked) {
        _likedStoryIds.remove(storyId);
      } else {
        _likedStoryIds.add(storyId);
        _showCenterHeart = true;
        _likeAnimController!.reset();
        _likeAnimController!.forward();
      }
    });
    _heartBtnAnimController!.reset();
    _heartBtnAnimController!.forward();
    // Call API in background
    _likeStoryApi(storyId, !wasLiked);
  }

  Future<void> _likeStoryApi(String storyId, bool isNowLiked) async {
    try {
      final api = ref.read(apiClientProvider);
      if (isNowLiked) {
        await api.post(ApiEndpoints.likeStory(storyId));
      } else {
        await api.delete(ApiEndpoints.likeStory(storyId));
      }
    } catch (_) {}
  }

  Widget _buildOwnStoryBottom(Story story) {
    final live = _liveViewsOverride[story.id] ?? story.viewsCount;
    return GestureDetector(
      onTap: () => _openViewersSheet(story),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PhosphorIcon(
              PhosphorIcons.eye(),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              live == 0
                  ? 'Пока никто не посмотрел'
                  : '$live ${_pluralViewers(live)}',
              style: SeeUTypography.body.copyWith(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            PhosphorIcon(
              PhosphorIcons.caretUp(),
              color: Colors.white70,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  String _pluralViewers(int n) {
    final m100 = n % 100;
    final m10 = n % 10;
    if (m100 >= 11 && m100 <= 14) return 'просмотров';
    if (m10 == 1) return 'просмотр';
    if (m10 >= 2 && m10 <= 4) return 'просмотра';
    return 'просмотров';
  }

  Future<void> _openViewersSheet(Story story) async {
    HapticFeedback.lightImpact();
    _progressController.stop();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StoryViewersSheet(storyId: story.id),
    );
    if (mounted && !_isReplyOpen) {
      _progressController.forward();
    }
  }

  void _reactWithEmoji(String emoji) {
    HapticFeedback.lightImpact();
    _progressController.stop();
    setState(() => _activeEmoji = emoji);
    _emojiAnimController!.reset();
    _emojiAnimController!.forward().then((_) {
      if (mounted && !_isReplyOpen) {
        _progressController.forward();
      }
    });
    // Fire-and-forget: provider does optimistic update + rollback on failure.
    // We intentionally don't await — the emoji animation runs immediately and
    // the network call shouldn't block the UI feedback loop.
    final storyId = _currentStory.id;
    ref.read(storyProvider.notifier).toggleReaction(storyId, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final story = _currentStory;
    final group = _currentGroup;
    final isLiked = _likedStoryIds.contains(story.id);
    final isOwnStory = widget.currentUserId != null &&
        group.author.id == widget.currentUserId;

    // Derive a per-group accent color for gradient backgrounds
    final List<List<Color>> gradientPalette = [
      [const Color(0xFF6A3DE8), const Color(0xFFB06AB3)],
      [const Color(0xFFFF5A3C), const Color(0xFFFF9A44)],
      [const Color(0xFF0F2027), const Color(0xFF203A43)],
      [const Color(0xFF1A1A2E), const Color(0xFF16213E)],
      [const Color(0xFF134E5E), const Color(0xFF71B280)],
    ];
    final gradientColors =
        gradientPalette[_groupIndex % gradientPalette.length];

    final bool hasValidUrl =
        story.mediaUrl.isNotEmpty;

    Widget storyImageWidget;
    if (story.isText) {
      // STORY-1: text-сторис — рендерим background-preset из bg_color +
      // центрированный текст из textOverlay.
      final bg = textStoryBackgroundFor(story.bgColor);
      storyImageWidget = Container(
        decoration: BoxDecoration(
          gradient: bg.gradient,
          color: bg.color,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          story.textOverlay ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: bg.textColor,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      );
    } else if (!hasValidUrl) {
      // No URL — show gradient background immediately
      storyImageWidget = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
      );
    } else {
      storyImageWidget = CachedNetworkImage(
        imageUrl: story.mediaUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(
                color: Colors.white54, strokeWidth: 2),
          ),
        ),
        errorWidget: (_, __, ___) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Main gesture + content layer
          GestureDetector(
        onTapDown: (details) {
          if (_isReplyOpen) return;
          _progressController.stop();
        },
        onTapUp: (details) {
          // M17: Ignore tap-up if a long-press was in progress
          if (_isLongPressing) return;
          if (_isReplyOpen) {
            _closeReply();
            return;
          }
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 2) {
            _prevStory();
          } else {
            _nextStory();
          }
        },
        onLongPressStart: (_) {
          if (_isReplyOpen) return;
          _isLongPressing = true;
          _progressController.stop();
        },
        onLongPressEnd: (_) {
          if (_isReplyOpen) return;
          _isLongPressing = false;
          _progressController.forward();
        },
        onHorizontalDragStart: (details) {
          if (_isReplyOpen) return;
          _isSwiping = true;
          _progressController.stop();
        },
        onHorizontalDragEnd: (details) {
          if (!_isSwiping || _isReplyOpen) return;
          _isSwiping = false;
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -300) {
            _nextGroup();
          } else if (velocity > 300) {
            _prevGroup();
          } else {
            _progressController.forward();
          }
        },
        onVerticalDragEnd: (details) {
          if (_isReplyOpen) return;
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Story image / gradient background
            SizedBox.expand(child: storyImageWidget),

            // Top gradient
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 140,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Bottom gradient
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Progress bars (4px height)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    children:
                        List.generate(group.stories.length, (i) {
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(
                            left: i == 0 ? 0 : 1.5,
                            right:
                                i == group.stories.length - 1 ? 0 : 1.5,
                          ),
                          height: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: i < _storyIndex
                                ? Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(2),
                                    ),
                                  )
                                : i == _storyIndex
                                    ? AnimatedBuilder(
                                        animation: _progressController,
                                        builder: (_, __) => Stack(
                                          children: [
                                            Container(
                                              color: Colors.white
                                                  .withValues(
                                                      alpha: 0.35),
                                            ),
                                            FractionallySizedBox(
                                              widthFactor:
                                                  Curves.easeOutQuad.transform(
                                                      _progressController.value),
                                              child: Container(
                                                decoration:
                                                    BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(2),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.35),
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),

            // User info header (avatar + username + time; X button is in outer Stack)
            Positioned(
              top: 0,
              left: 0,
              right: 56, // leave space for the X button in the outer stack
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 28, left: 12, right: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundImage: group.author.avatarUrl != null
                            ? NetworkImage(group.author.avatarUrl!)
                            : null,
                        backgroundColor: Colors.grey,
                        child: group.author.avatarUrl == null
                            ? Text(
                                group.author.username[0].toUpperCase(),
                                style: SeeUTypography.caption
                                    .copyWith(color: Colors.white),
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.author.username,
                                style: SeeUTypography.subtitle.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              formatRelativeTime(story.createdAt),
                              style: SeeUTypography.caption.copyWith(
                                color:
                                    Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Music tag — Instagram-style плашка с названием трека.
            // Показывается только когда story имеет audio_track_id и трек
            // уже подгружен в кэш. До загрузки — ничего не рендерим (всё
            // равно музыка ещё не играет).
            if (story.audioTrackId != null &&
                _audioCache[story.audioTrackId] != null)
              Positioned(
                bottom: 100,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsBold.musicNote,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        '${_audioCache[story.audioTrackId!]!.title} · '
                        '${_audioCache[story.audioTrackId!]!.artist}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // STORY-3: интерактивный poll-overlay. Позиционируется в (x,y)
            // фракциях экрана, viewer тапает option → POST → state apdate.
            // Автор не видит интерактивные кнопки — для него просто превью.
            if (story.poll != null)
              LayoutBuilder(builder: (ctx, cs) {
                final p = story.poll!;
                final isAuthor = widget.currentUserId == story.author.id;
                return Positioned(
                  left: (p.x.clamp(0.0, 0.9)) * cs.maxWidth,
                  top: (p.y.clamp(0.0, 0.85)) * cs.maxHeight,
                  child: StoryPollOverlay(
                    storyId: story.id,
                    poll: p,
                    readOnly: isAuthor,
                    onVoted: (updated) {
                      // Обновляем story-state in-place чтобы вся группа
                      // увидела новые counts без re-fetch.
                      _updateStoryPoll(story.id, updated);
                    },
                  ),
                );
              }),

            // Text overlay (для photo/video сторис с подписью).
            // Для text-сторис текст уже отрендерен внутри storyImageWidget —
            // здесь не дублируем.
            if (!story.isText &&
                story.textOverlay != null &&
                story.textOverlay!.isNotEmpty)
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius:
                        BorderRadius.circular(SeeURadii.small),
                  ),
                  child: Text(
                    story.textOverlay!,
                    style: SeeUTypography.title.copyWith(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // Center heart animation
            if (_showCenterHeart && _likeScaleAnim != null)
              Center(
                child: AnimatedBuilder(
                  animation: _likeScaleAnim!,
                  builder: (_, __) => Transform.scale(
                    scale: _likeScaleAnim!.value,
                    child: const Icon(
                      Icons.favorite,
                      color: SeeUColors.like,
                      size: 100,
                    ),
                  ),
                ),
              ),

            // Center emoji reaction animation
            if (_activeEmoji != null && _emojiScaleAnim != null)
              Center(
                child: AnimatedBuilder(
                  animation: _emojiScaleAnim!,
                  builder: (_, __) => Transform.scale(
                    scale: _emojiScaleAnim!.value,
                    child: Text(
                      _activeEmoji!,
                      style: const TextStyle(fontSize: 80),
                    ),
                  ),
                ),
              ),

            // View count (bottom-left)
            Positioned(
              bottom: 130,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      PhosphorIcons.eye(),
                      color: Colors.white.withValues(alpha: 0.85),
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_liveViewsOverride[story.id] ?? story.viewsCount}',
                      style: SeeUTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom section: viewers (own) or emoji reactions + reply bar (others)
            if (!_isReplyOpen)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: isOwnStory
                        ? _buildOwnStoryBottom(story)
                        : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Emoji quick-react row
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: kQuickReactionEmojis.map((emoji) {
                              return GestureDetector(
                                onTap: () => _reactWithEmoji(emoji),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.white
                                        .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      emoji,
                                      style:
                                          const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        // Reply bar + like button
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _openReply,
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.5),
                                    ),
                                    borderRadius: BorderRadius.circular(
                                        SeeURadii.pill),
                                  ),
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          'Отправить сообщение...',
                                          style: SeeUTypography.body
                                              .copyWith(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(
                                                right: 12),
                                        child: PhosphorIcon(
                                          PhosphorIcons
                                              .paperPlaneTilt(),
                                          color: Colors.white
                                              .withValues(
                                                  alpha: 0.5),
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: _toggleLike,
                              child: AnimatedBuilder(
                                animation: _heartBtnScaleAnim!,
                                builder: (_, child) =>
                                    Transform.scale(
                                  scale: _heartBtnScaleAnim!.value,
                                  child: child,
                                ),
                                child: Icon(
                                  isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isLiked
                                      ? SeeUColors.like
                                      : Colors.white
                                          .withValues(alpha: 0.8),
                                  size: 28,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Reply text field overlay
            if (_isReplyOpen)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.85),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyController,
                              focusNode: _replyFocusNode,
                              autofocus: true,
                              style: SeeUTypography.body.copyWith(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              cursorColor: SeeUColors.accent,
                              decoration: InputDecoration(
                                hintText: 'Ответить...',
                                hintStyle:
                                    SeeUTypography.body.copyWith(
                                  color: Colors.white54,
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: Colors.white
                                    .withValues(alpha: 0.12),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          SeeURadii.pill),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          SeeURadii.pill),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          SeeURadii.pill),
                                  borderSide: const BorderSide(
                                    color: SeeUColors.accent,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              textInputAction:
                                  TextInputAction.send,
                              onSubmitted: (_) => _sendReply(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedOpacity(
                            opacity: _replyController.text
                                    .trim()
                                    .isNotEmpty
                                ? 1.0
                                : 0.4,
                            duration:
                                const Duration(milliseconds: 150),
                            child: GestureDetector(
                              onTap: _sendReply,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _replyController.text
                                          .trim()
                                          .isNotEmpty
                                      ? SeeUColors.accent
                                      : Colors.white.withValues(
                                          alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.send_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
          ),
          ),
          // Close button — always works, above everything.
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: IconButton(
                  icon: PhosphorIcon(PhosphorIcons.x(),
                      color: Colors.white, size: 26),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Закрыть',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

