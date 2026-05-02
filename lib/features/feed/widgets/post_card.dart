import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:timeago/timeago.dart' as timeago;
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
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIcons.link(),
                  color: SeeUColors.textPrimary),
              title: Text('Копировать ссылку', style: SeeUTypography.body),
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: 'https://seeu.app/post/${widget.post.id}'));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ссылка скопирована')),
                );
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.clockCounterClockwise(),
                  color: SeeUColors.textPrimary),
              title: Text('Поделиться в историю', style: SeeUTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Скоро будет доступно')),
                );
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.x(),
                  color: SeeUColors.textTertiary),
              title: Text('Отмена',
                  style: SeeUTypography.body
                      .copyWith(color: SeeUColors.textTertiary)),
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

  Widget _buildWaveCard(BuildContext context, Post post) {
    final waveColor = post.waveColorValue != null
        ? Color(post.waveColorValue!)
        : SeeUColors.accent;

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
            // Wave body with colored background
            GestureDetector(
              onDoubleTap: _onDoubleTap,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 200),
                decoration: BoxDecoration(
                  color: waveColor,
                  borderRadius: BorderRadius.circular(SeeURadii.card),
                  boxShadow: SeeUShadows.md,
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header inside wave
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => context
                                    .push('/profile/${post.author.username}'),
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundImage: post.author.avatarUrl != null
                                      ? CachedNetworkImageProvider(
                                          post.author.avatarUrl!)
                                      : null,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.3),
                                  child: post.author.avatarUrl == null
                                      ? Icon(PhosphorIcons.user(),
                                          color: Colors.white, size: 16)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => context
                                      .push('/profile/${post.author.username}'),
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          post.author.username,
                                          style: SeeUTypography.subtitle
                                              .copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (post.author.isVerified) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          PhosphorIcons.sealCheck(
                                              PhosphorIconsStyle.fill),
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              Text(
                                timeago
                                    .format(post.createdAt,
                                        locale: 'ru', allowFromNow: true)
                                    .toUpperCase(),
                                style: SeeUTypography.micro
                                    .copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Wave text centered
                          Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                post.caption ?? '',
                                style: SeeUTypography.body.copyWith(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
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
            const SizedBox(height: 12),
            // Actions row with white-on-wave style
            _buildWaveActions(context, post),
            _buildLikesRow(context, post),
            _buildCommentsPreview(context, post),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveActions(BuildContext context, Post post) {
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
                      post.isLiked ? SeeUColors.like : SeeUColors.textPrimary,
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
                    color: SeeUColors.surface,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    boxShadow: SeeUShadows.lg,
                    border: Border.all(
                      color: SeeUColors.borderSubtle,
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

  Widget _buildHeader(BuildContext context, Post post) {
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
              backgroundColor: SeeUColors.surfaceElevated,
              child: post.author.avatarUrl == null
                  ? Icon(PhosphorIcons.user(),
                      color: SeeUColors.textTertiary, size: 18)
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
                  size: 20, color: SeeUColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia(BuildContext context, Post post) {
    if (post.media.isEmpty) return const SizedBox.shrink();
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

              // Page counter badge (top-right)
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
                    child: Icon(
                      PhosphorIcons.squaresFour(),
                      color: Colors.white,
                      size: 16,
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
    return CachedNetworkImage(
      imageUrl: media.url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: SeeUColors.surfaceElevated,
      ),
      errorWidget: (_, __, ___) => Container(
        color: SeeUColors.surfaceElevated,
        child: Icon(PhosphorIcons.imageSquare(),
            color: SeeUColors.textTertiary, size: 48),
      ),
    );
  }

  Widget _buildActions(BuildContext context, Post post) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          children: [
            // Like button with long-press for reaction picker
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
                  color: post.isLiked ? SeeUColors.like : SeeUColors.textPrimary,
                  size: 22,
                ),
              ),
            ),
            // Brief selected emoji indicator
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
        // Reaction picker overlay
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: SeeUColors.surface,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    boxShadow: SeeUShadows.lg,
                    border: Border.all(
                      color: SeeUColors.borderSubtle,
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

  Widget _buildLikesRow(BuildContext context, Post post) {
    if (post.likesCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        post.likedByUsername != null
            ? 'Нравится ${post.likedByUsername} и ещё ${_formatCount(post.likesCount - 1)}'
            : '${_formatCount(post.likesCount)} отметок «Нравится»',
        style:
            SeeUTypography.caption.copyWith(fontWeight: FontWeight.w700, color: SeeUColors.textPrimary),
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
    if (post.commentsCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => context.push('/post/${post.id}/comments'),
        child: SeeUChip(
          label: '${_formatCount(post.commentsCount)} комментариев',
          bgColor: SeeUColors.accentSoft,
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
    showModalBottomSheet(
      context: context,
      backgroundColor: SeeUColors.surface,
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
                color: SeeUColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(PhosphorIcons.shareFat(),
                  color: SeeUColors.textPrimary),
              title: Text('Поделиться', style: SeeUTypography.body),
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: 'https://seeu.app/post/${post.id}'));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ссылка скопирована')),
                );
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.bookmarkSimple(),
                  color: SeeUColors.textPrimary),
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
    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.90,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: SeeUColors.surfaceElevated,
          borderRadius: BorderRadius.circular(SeeURadii.small),
          boxShadow: SeeUShadows.sm,
        ),
        child: Center(
          child: IconTheme(
            data: IconThemeData(
              size: 22,
              color: SeeUColors.textPrimary,
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
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: SeeUColors.surfaceElevated,
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
                      .copyWith(color: SeeUColors.textTertiary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
