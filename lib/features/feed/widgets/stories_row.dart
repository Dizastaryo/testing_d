import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/story_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/models/story.dart';
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
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: StoryCircle(
              imageUrl: group.author.avatarUrl,
              username: group.author.username,
              isSeen: group.allSeen,
              onTap: () => _openStoryViewer(
                  context, storyState.storyGroups, index - 1),
            ),
          );
        },
      ),
    );
  }

  void _openStoryViewer(
      BuildContext context, List<StoryGroup> groups, int groupIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            StoryViewerRoute(groups: groups, initialGroupIndex: groupIndex),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
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

  const StoryViewerRoute({
    super.key,
    required this.groups,
    required this.initialGroupIndex,
  });

  @override
  Widget build(BuildContext context) {
    return _InlineStoryViewer(
      groups: groups,
      initialGroupIndex: initialGroupIndex,
    );
  }
}

class _InlineStoryViewer extends StatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;

  const _InlineStoryViewer({
    required this.groups,
    required this.initialGroupIndex,
  });

  @override
  State<_InlineStoryViewer> createState() => _InlineStoryViewerState();
}

class _InlineStoryViewerState extends State<_InlineStoryViewer>
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

  static const List<String> _quickEmojis = [
    '\u{1F525}',
    '\u{2764}\u{FE0F}',
    '\u{1F602}',
    '\u{1F92F}',
    '\u{1F44F}',
  ];

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _storyIndex = 0;

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          _nextStory();
        }
      });
    _progressController.forward();

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
    _progressController.dispose();
    _likeAnimController?.dispose();
    _emojiAnimController?.dispose();
    _heartBtnAnimController?.dispose();
    _replyController.removeListener(_onReplyChanged);
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  StoryGroup get _currentGroup => widget.groups[_groupIndex];
  Story get _currentStory => _currentGroup.stories[_storyIndex];

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
    }
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
    setState(() {
      if (_likedStoryIds.contains(storyId)) {
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
    // M16: mounted check before ScaffoldMessenger
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Реакция отправлена'),
        backgroundColor: SeeUColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final story = _currentStory;
    final group = _currentGroup;
    final isLiked = _likedStoryIds.contains(story.id);

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
    if (!hasValidUrl) {
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
            storyImageWidget,

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
                                                  _progressController
                                                      .value,
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
                              _timeAgo(story.createdAt),
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

            // Text overlay
            if (story.textOverlay != null &&
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
                      '${story.viewsCount}',
                      style: SeeUTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom section: emoji reactions + reply bar
            if (!_isReplyOpen)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Emoji quick-react row
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: _quickEmojis.map((emoji) {
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    // U10: Return 'только что' for stories less than 1 minute old
    if (diff.inSeconds < 60) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
