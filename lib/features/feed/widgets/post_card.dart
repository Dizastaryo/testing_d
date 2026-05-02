import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';
import '../../../core/design/design.dart';
import '../../../core/models/post.dart';
import '../../../core/providers/feed_provider.dart';

class PostCard extends ConsumerStatefulWidget {
  final Post post;
  final bool isDetail;

  const PostCard({super.key, required this.post, this.isDetail = false});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard>
    with TickerProviderStateMixin {
  late AnimationController _heartAnimController;
  late Animation<double> _heartScaleAnim;
  late Animation<double> _heartOpacityAnim;
  bool _showHeart = false;
  final PageController _pageController = PageController();

  // Reaction picker state
  // L09: Track current page for counter badge
  int _currentPage = 0;
  bool _showReactionPicker = false;
  late AnimationController _reactionPickerController;
  late Animation<double> _reactionPickerScaleAnim;
  late Animation<double> _reactionPickerOpacityAnim;
  String? _selectedEmoji;
  bool _showSelectedEmoji = false;

  static const List<String> _reactionEmojis = [
    '\u{1F525}', // fire
    '\u{2764}\u{FE0F}', // red heart
    '\u{1F602}', // laughing
    '\u{1F92F}', // exploding head
    '\u{1F44F}', // clap
  ];

  @override
  void initState() {
    super.initState();
    // L09: Listen to page changes for counter badge
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() => _currentPage = page);
      }
    });
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heartScaleAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: 1.2)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.2, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 20),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.0),
          weight: 40),
    ]).animate(_heartAnimController);
    _heartOpacityAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: 1.0),
          weight: 20),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.0),
          weight: 40),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 40),
    ]).animate(_heartAnimController);
    _heartAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _showHeart = false);
      }
    });

    // Reaction picker animation
    _reactionPickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _reactionPickerScaleAnim = CurvedAnimation(
      parent: _reactionPickerController,
      curve: Curves.easeOutBack,
    );
    _reactionPickerOpacityAnim = CurvedAnimation(
      parent: _reactionPickerController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    _reactionPickerController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    if (!widget.post.isLiked) {
      _likePost();
    }
    HapticFeedback.mediumImpact();
    setState(() => _showHeart = true);
    _heartAnimController.forward(from: 0);
  }

  void _likePost() {
    HapticFeedback.lightImpact();
    ref.read(feedProvider.notifier).toggleLike(widget.post.id);
  }

  void _savePost() {
    HapticFeedback.lightImpact();
    ref.read(feedProvider.notifier).toggleSave(widget.post.id);
  }

  void _showReactionPickerUI() {
    HapticFeedback.mediumImpact();
    setState(() => _showReactionPicker = true);
    _reactionPickerController.forward(from: 0);
  }

  void _hideReactionPicker() {
    _reactionPickerController.reverse().then((_) {
      if (mounted) {
        setState(() => _showReactionPicker = false);
      }
    });
  }

  void _selectReaction(String emoji) {
    HapticFeedback.lightImpact();
    if (!widget.post.isLiked) {
      ref.read(feedProvider.notifier).toggleLike(widget.post.id);
    }
    setState(() {
      _selectedEmoji = emoji;
      _showSelectedEmoji = true;
    });
    _hideReactionPicker();
    // Hide the selected emoji indicator after a brief moment
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _showSelectedEmoji = false);
      }
    });
  }

  void _onShareTap() {
    final c = context.seeuColors;
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIcons.link(),
                  color: c.ink),
              title: Text('Копировать ссылку', style: SeeUTypography.body),
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: 'https://seeu.app/post/${widget.post.id}'));
                Navigator.pop(ctx);
                // M19: mounted check before ScaffoldMessenger after Navigator.pop
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ссылка скопирована')),
                );
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.clockCounterClockwise(),
                  color: c.ink),
              title: Text('Поделиться в историю', style: SeeUTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                // M19: mounted check before ScaffoldMessenger after Navigator.pop
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Скоро будет доступно')),
                );
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.x(),
                  color: c.ink3),
              title: Text('Отмена',
                  style: SeeUTypography.body
                      .copyWith(color: c.ink3)),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    if (post.isWave) {
      return _buildWaveCard(context, post);
    }

    return GestureDetector(
      onTap: _showReactionPicker ? _hideReactionPicker : null,
      behavior: _showReactionPicker ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, post),
            const SizedBox(height: 10),
            _buildMedia(context, post),
            const SizedBox(height: 12),
            _buildActions(context, post),
            _buildLikesRow(context, post),
            _buildCaption(context, post),
            _buildCommentsPreview(context, post),
            _buildTimeRow(context, post),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Parse caption into headline words and tail text.
  /// First 4 words (or fewer) become the big headline; the rest is tail.
  ({String big, String conjunction, String big2, String tail}) _parseWaveCaption(
      String? caption) {
    final raw = (caption ?? '').trim();
    if (raw.isEmpty) {
      return (big: 'SEEU', conjunction: '·', big2: 'ВОПРОС', tail: '');
    }
    final words = raw.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return (big: words[0], conjunction: '', big2: '', tail: '');
    }
    if (words.length == 2) {
      return (big: words[0], conjunction: '·', big2: words[1], tail: '');
    }
    if (words.length == 3) {
      return (
        big: words[0],
        conjunction: words[1],
        big2: words[2],
        tail: ''
      );
    }
    // 4+ words: split into headline (first 3) and tail (rest)
    final headline = words.take(3).toList();
    final tail = words.skip(3).join(' ');
    return (
      big: headline[0],
      conjunction: headline[1],
      big2: headline[2],
      tail: tail
    );
  }

  Widget _buildWaveCard(BuildContext context, Post post) {
    const Color darkBg = Color(0xFF2B1610);
    const Color warmCream = Color(0xFFE6D6BE);
    const Color defaultAmber = Color(0xFFFFB547);

    final waveColor = post.waveColorValue != null
        ? Color(post.waveColorValue!)
        : defaultAmber;

    final parsed = _parseWaveCaption(post.caption);
    final eyebrowLabel = 'SEEU · ВОПРОС';

    return GestureDetector(
      onTap: _showReactionPicker ? _hideReactionPicker : null,
      behavior: _showReactionPicker
          ? HitTestBehavior.opaque
          : HitTestBehavior.deferToChild,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wave editorial card
            GestureDetector(
              onDoubleTap: _onDoubleTap,
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: darkBg,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: SeeUShadows.md,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Corner radial gradient overlays
                      Positioned(
                        top: -60,
                        right: -60,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                waveColor.withValues(alpha: 0.28),
                                waveColor.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -40,
                        left: -40,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                waveColor.withValues(alpha: 0.18),
                                waveColor.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Big decorative "?" background character
                      Positioned(
                        top: -10,
                        right: -12,
                        child: Text(
                          '?',
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 280,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w700,
                            color: waveColor.withValues(alpha: 0.18),
                            height: 1.0,
                          ),
                        ),
                      ),

                      // Main content
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top eyebrow: line + mono label
                            Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 1.5,
                                  color: waveColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  eyebrowLabel,
                                  style: TextStyle(
                                    fontFamily: 'Consolas',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: waveColor,
                                  ),
                                ),
                              ],
                            ),

                            const Spacer(),

                            // Left quote bar + typographic stack
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left accent bar
                                  Container(
                                    width: 3,
                                    decoration: BoxDecoration(
                                      color: waveColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Headline text stack
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Big word 1
                                        if (parsed.big.isNotEmpty)
                                          Text(
                                            parsed.big,
                                            style: const TextStyle(
                                              fontFamily: 'Georgia',
                                              fontSize: 60,
                                              fontWeight: FontWeight.w400,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.white,
                                              height: 0.95,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        // Conjunction (smaller, accent color)
                                        if (parsed.conjunction.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            parsed.conjunction,
                                            style: TextStyle(
                                              fontFamily: 'Consolas',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              letterSpacing: 0.8,
                                              color: waveColor.withValues(
                                                  alpha: 0.80),
                                            ),
                                          ),
                                        ],
                                        // Big word 2
                                        if (parsed.big2.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            parsed.big2,
                                            style: const TextStyle(
                                              fontFamily: 'Georgia',
                                              fontSize: 60,
                                              fontWeight: FontWeight.w400,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.white,
                                              height: 0.95,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        // Tail text
                                        if (parsed.tail.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Text(
                                            parsed.tail,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              color: warmCream,
                                              height: 1.4,
                                            ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Bottom row: "ответить" chip + emoji crumbs
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => context
                                      .push('/post/${post.id}/comments'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: waveColor.withValues(alpha: 0.18),
                                      borderRadius:
                                          BorderRadius.circular(SeeURadii.pill),
                                      border: Border.all(
                                        color:
                                            waveColor.withValues(alpha: 0.35),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      'ответить',
                                      style: TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                        color: waveColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '🍐🧀🍝',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Corner watermark
                      Positioned(
                        bottom: 12,
                        right: 14,
                        child: Text(
                          eyebrowLabel,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 9,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.6,
                            color: Colors.white.withValues(alpha: 0.20),
                          ),
                        ),
                      ),

                      // Double-tap heart animation
                      if (_showHeart)
                        Positioned.fill(
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _heartAnimController,
                              builder: (_, __) => Opacity(
                                opacity: _heartOpacityAnim.value,
                                child: Transform.scale(
                                  scale: _heartScaleAnim.value,
                                  child: const Icon(
                                    Icons.favorite,
                                    color: Colors.white,
                                    size: 80,
                                  ),
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
            const SizedBox(height: 12),
            // Actions row
            _buildWaveActions(context, post),
            _buildLikesRow(context, post),
            _buildCommentsPreview(context, post),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // U14: Shared action row builder used by both wave and normal posts (DRY)
  Widget _buildActionsRow(BuildContext context, Post post) {
    final c = context.seeuColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () {
                if (_showReactionPicker) {
                  _hideReactionPicker();
                } else {
                  _likePost();
                }
              },
              onLongPress: _showReactionPickerUI,
              child: _ActionButtonRaw(
                icon: PhosphorIcon(
                  post.isLiked
                      ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                      : PhosphorIcons.heart(),
                  color:
                      post.isLiked ? SeeUColors.like : c.ink,
                  size: 22,
                ),
              ),
            ),
            if (_showSelectedEmoji && _selectedEmoji != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  _selectedEmoji!,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            const SizedBox(width: 8),
            _ActionButton(
              icon: PhosphorIcon(PhosphorIcons.chatCircle()),
              onTap: () => context.push('/post/${post.id}/comments'),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              icon: PhosphorIcon(PhosphorIcons.shareFat()),
              onTap: _onShareTap,
            ),
            const Spacer(),
            _ActionButton(
              icon: PhosphorIcon(post.isSaved
                  ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                  : PhosphorIcons.bookmarkSimple()),
              onTap: _savePost,
            ),
          ],
        ),
        if (_showReactionPicker)
          Positioned(
            bottom: 50,
            left: 0,
            child: FadeTransition(
              opacity: _reactionPickerOpacityAnim,
              child: ScaleTransition(
                scale: _reactionPickerScaleAnim,
                alignment: Alignment.bottomLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    boxShadow: SeeUShadows.lg,
                    border: Border.all(
                      color: c.line,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _reactionEmojis.map((emoji) {
                      return GestureDetector(
                        onTap: () => _selectReaction(emoji),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWaveActions(BuildContext context, Post post) {
    return _buildActionsRow(context, post);
  }

  Widget _buildHeader(BuildContext context, Post post) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.push('/profile/${post.author.username}'),
            child: CircleAvatar(
              radius: 18,
              backgroundImage: post.author.avatarUrl != null
                  ? CachedNetworkImageProvider(post.author.avatarUrl!)
                  : null,
              backgroundColor: c.surface2,
              child: post.author.avatarUrl == null
                  ? Icon(PhosphorIcons.user(),
                      color: c.ink3, size: 18)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/profile/${post.author.username}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          post.author.username,
                          style: SeeUTypography.subtitle
                              .copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (post.author.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill),
                            color: SeeUColors.accent, size: 16),
                      ],
                    ],
                  ),
                  if (post.location != null && post.location!.isNotEmpty)
                    Text(
                      post.location!,
                      style: SeeUTypography.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showPostOptions(context, post),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(PhosphorIcons.dotsThreeOutline(),
                  size: 20, color: c.ink2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia(BuildContext context, Post post) {
    final c = context.seeuColors;
    if (post.media.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SeeURadii.card),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFE4D9), Color(0xFFFFF5D4)],
          ),
        ),
        child: Center(
          child: Icon(PhosphorIcons.imageSquare(),
              color: c.ink3, size: 48),
        ),
      );
    }
    final aspectRatio = post.media.first.aspectRatio ?? 1.0;
    final hasMultiple = post.media.length > 1;

    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SeeURadii.card),
          boxShadow: SeeUShadows.md,
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image carousel or single image
              if (hasMultiple)
                PageView.builder(
                  controller: _pageController,
                  itemCount: post.media.length,
                  itemBuilder: (_, index) => _buildMediaItem(post.media[index]),
                )
              else
                _buildMediaItem(post.media.first),

              // Double-tap heart animation
              if (_showHeart)
                Center(
                  child: AnimatedBuilder(
                    animation: _heartAnimController,
                    builder: (_, __) => Opacity(
                      opacity: _heartOpacityAnim.value,
                      child: Transform.scale(
                        scale: _heartScaleAnim.value,
                        child: Icon(
                          PhosphorIcons.heart(PhosphorIconsStyle.fill),
                          color: SeeUColors.accent,
                          size: 80,
                        ),
                      ),
                    ),
                  ),
                ),

              // Dot indicator for multiple images
              if (hasMultiple)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SmoothPageIndicator(
                      controller: _pageController,
                      count: post.media.length,
                      effect: WormEffect(
                        dotWidth: 6,
                        dotHeight: 6,
                        spacing: 5,
                        activeDotColor: SeeUColors.accent,
                        dotColor: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),

              // L09: Page counter badge with text (e.g. "1/3")
              if (hasMultiple)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(SeeURadii.pill),
                    ),
                    child: Text(
                      '${_currentPage + 1}/${post.media.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaItem(PostMedia media) {
    final c = context.seeuColors;
    if (media.type == MediaType.video) {
      return _FeedVideoPlayer(url: media.url);
    }
    return CachedNetworkImage(
      imageUrl: media.url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: c.surface2,
      ),
      errorWidget: (_, __, ___) => Container(
        color: c.surface2,
        child: Icon(PhosphorIcons.imageSquare(),
            color: c.ink3, size: 48),
      ),
    );
  }

  // U14: Delegates to shared _buildActionsRow
  Widget _buildActions(BuildContext context, Post post) {
    return _buildActionsRow(context, post);
  }

  Widget _buildLikesRow(BuildContext context, Post post) {
    final c = context.seeuColors;
    if (post.likesCount == 0) return const SizedBox.shrink();
    // M18: Guard likesCount == 1 with likedByUsername — avoid "и ещё 0"
    String likesText;
    if (post.likedByUsername != null) {
      if (post.likesCount == 1) {
        likesText = 'Нравится ${post.likedByUsername}';
      } else {
        likesText = 'Нравится ${post.likedByUsername} и ещё ${_formatCount(post.likesCount - 1)}';
      }
    } else {
      likesText = '${_formatCount(post.likesCount)} отметок «Нравится»';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        likesText,
        style:
            SeeUTypography.caption.copyWith(fontWeight: FontWeight.w700, color: c.ink),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  Widget _buildCaption(BuildContext context, Post post) {
    if (post.caption == null || post.caption!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _ExpandableCaption(
        postId: post.id,
        username: post.author.username,
        caption: post.caption!,
      ),
    );
  }

  Widget _buildCommentsPreview(BuildContext context, Post post) {
    final c = context.seeuColors;
    if (post.commentsCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => context.push('/post/${post.id}/comments'),
        child: SeeUChip(
          label: '${_formatCount(post.commentsCount)} комментариев',
          bgColor: c.accentSoft,
          fgColor: SeeUColors.accent,
        ),
      ),
    );
  }

  Widget _buildTimeRow(BuildContext context, Post post) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        timeago.format(post.createdAt, locale: 'ru', allowFromNow: true).toUpperCase(),
        style: SeeUTypography.micro,
      ),
    );
  }

  void _showPostOptions(BuildContext context, Post post) {
    final c = context.seeuColors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(PhosphorIcons.shareFat(),
                  color: c.ink),
              title: Text('Поделиться', style: SeeUTypography.body),
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: 'https://seeu.app/post/${post.id}'));
                Navigator.pop(context);
                // M19: mounted check before ScaffoldMessenger after Navigator.pop
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ссылка скопирована')),
                );
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.bookmarkSimple(),
                  color: c.ink),
              title: Text('Сохранить', style: SeeUTypography.body),
              onTap: () {
                _savePost();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading:
                  Icon(PhosphorIcons.flag(), color: SeeUColors.like),
              title: Text('Пожаловаться',
                  style: SeeUTypography.body
                      .copyWith(color: SeeUColors.like)),
              onTap: () {
                Navigator.pop(context);
                // M19: mounted check before ScaffoldMessenger after Navigator.pop
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Жалоба отправлена. Спасибо!')),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

// --- Action button (tappable) ------------------------------------------------

class _ActionButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.90,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.small),
          boxShadow: SeeUShadows.sm,
        ),
        child: Center(
          child: IconTheme(
            data: IconThemeData(
              size: 22,
              color: c.ink,
            ),
            child: icon,
          ),
        ),
      ),
    );
  }
}

// --- Action button raw (no Tappable wrapper, used for custom gesture) --------

class _ActionButtonRaw extends StatelessWidget {
  final Widget icon;

  const _ActionButtonRaw({
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      width: 44,
      height: 44,
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

class _ExpandableCaption extends StatefulWidget {
  final String postId;
  final String username;
  final String caption;

  const _ExpandableCaption({
    required this.postId,
    required this.username,
    required this.caption,
  });

  @override
  State<_ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<_ExpandableCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    const maxLength = 100;
    final isLong = widget.caption.length > maxLength;

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '${widget.username} ',
            style: SeeUTypography.body
                .copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: _expanded || !isLong
                ? widget.caption
                : '${widget.caption.substring(0, maxLength)}...',
            style: SeeUTypography.body,
          ),
          if (isLong && !_expanded)
            WidgetSpan(
              child: GestureDetector(
                onTap: () => setState(() => _expanded = true),
                child: Text(
                  ' ещё',
                  style: SeeUTypography.body
                      .copyWith(color: c.ink3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Video player for feed posts ─────────────────────────────────────────

class _FeedVideoPlayer extends StatefulWidget {
  final String url;
  const _FeedVideoPlayer({required this.url});

  @override
  State<_FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<_FeedVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _showPlayIcon = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setLooping(true)
      ..setVolume(0) // muted by default in feed
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      setState(() => _showPlayIcon = true);
    } else {
      _controller.play();
      setState(() => _showPlayIcon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
        ),
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller.value.size.width,
              height: _controller.value.size.height,
              child: VideoPlayer(_controller),
            ),
          ),
          // Play icon overlay
          if (_showPlayIcon)
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
              ),
            ),
          // Video indicator
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Видео', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
