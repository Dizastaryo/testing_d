import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/design/design.dart';
import '../../../core/models/post.dart';
import '../../../core/providers/blocks_provider.dart';
import '../../../core/providers/feed_provider.dart';
import '../../../widgets/report_sheet.dart';
import '../../../widgets/share_sheet.dart';
import 'post_card_widgets.dart';

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
  // Burst — particle-эффект поверх большой anim'ы. Два GlobalKey'а потому что
  // wave-layout и normal-layout рендерятся в разных Stack'ах, на экране в
  // момент времени только один — пуляем burst в оба (другой просто null'ится).
  final GlobalKey<SeeUHeartBurstState> _burstKeyWave =
      GlobalKey<SeeUHeartBurstState>();
  final GlobalKey<SeeUHeartBurstState> _burstKeyNormal =
      GlobalKey<SeeUHeartBurstState>();
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
    // Particle-burst — стреляем в оба ключа, ответит только тот что mounted.
    _burstKeyWave.currentState?.burst();
    _burstKeyNormal.currentState?.burst();
  }

  void _likePost() {
    HapticFeedback.lightImpact();
    ref.read(feedProvider.notifier).toggleLike(widget.post.id);
  }

  void _savePost() {
    HapticFeedback.lightImpact();
    ref.read(feedProvider.notifier).toggleSave(widget.post.id);
  }

  Future<void> _confirmBlockAuthor() async {
    final author = widget.post.author;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Заблокировать @${author.username}?'),
        content: const Text(
          'Вы перестанете видеть посты и истории этого пользователя, '
          'а он — ваши. Подписки удалятся в обе стороны.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE74C3C)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final err = await ref.read(blocksProvider.notifier).block(author.username);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось заблокировать: $err')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('@${author.username} заблокирован')),
    );
    // Drop this post from the local feed cache so the UI matches the new visibility.
    ref.read(feedProvider.notifier).removePost(widget.post.id);
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
    // Persisted via FeedNotifier (toggle = same emoji removes, different
    // upserts). Server fan-outs `post.reaction` over WS so other viewers
    // see the count change too.
    ref.read(feedProvider.notifier).toggleReaction(widget.post.id, emoji);
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
    // Для CHAT-5 «Поделиться в сторис» прокидываем first media + author.
    // Если у поста нет media (чисто текстовый wave) — params null и tile
    // в sheet'е не появится.
    final firstMedia =
        widget.post.media.isNotEmpty ? widget.post.media.first : null;
    showShareSheet(
      context: context,
      url: postShareUrl(widget.post.id),
      title: 'Поделиться постом',
      subtitle: widget.post.author.username.isNotEmpty
          ? '@${widget.post.author.username}'
          : null,
      forwardablePostId: widget.post.id,
      sharedPostMediaUrl: firstMedia?.url,
      sharedPostMediaType: firstMedia?.type.name,
      sharedPostAuthor: widget.post.author.username,
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
            _buildReactionPills(context, post),
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
                            fontFamily: 'Fraunces',
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
                                    fontFamily: 'JetBrains Mono',
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
                                              fontFamily: 'Fraunces',
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
                                              fontFamily: 'JetBrains Mono',
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
                                              fontFamily: 'Fraunces',
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
                                        fontFamily: 'JetBrains Mono',
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
                            fontFamily: 'JetBrains Mono',
                            fontSize: 9,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.6,
                            color: Colors.white.withValues(alpha: 0.20),
                          ),
                        ),
                      ),

                      // Double-tap heart animation + particle burst overlay
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
                      Positioned.fill(
                        child: Center(
                          child: SeeUHeartBurst(
                            key: _burstKeyWave,
                            color: Colors.white,
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
              child: PostActionButtonRaw(
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
            PostActionButton(
              icon: PhosphorIcon(PhosphorIcons.chatCircle()),
              onTap: () => context.push('/post/${post.id}/comments'),
            ),
            const SizedBox(width: 8),
            PostActionButton(
              icon: PhosphorIcon(PhosphorIcons.shareFat()),
              onTap: _onShareTap,
            ),
            const Spacer(),
            PostActionButton(
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
                    children: kQuickReactionEmojis.map((emoji) {
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
            child: SizedBox(
              width: 44,
              height: 44,
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
    final aspectRatio = (post.media.first.aspectRatio ?? 1.0).clamp(0.1, 3.0);
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

              // Double-tap heart animation + particle burst
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
              Center(
                child: SeeUHeartBurst(key: _burstKeyNormal),
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
                    // BUG-16: micro-typography token + white override для
                    // counter-badge поверх media. Раньше inline fontSize:12.
                    child: Text(
                      '${_currentPage + 1}/${post.media.length}',
                      style: SeeUTypography.micro.copyWith(
                        color: Colors.white,
                        fontSize: 12,
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
      return FeedVideoPlayer(url: media.url);
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

  /// Aggregate emoji-reaction pills under the action row. Mirrors the
  /// chat-message reaction strip: tap a pill to toggle (same emoji = unreact,
  /// new emoji = upsert). Only renders when there's at least one reaction.
  Widget _buildReactionPills(BuildContext context, Post post) {
    if (post.reactions.isEmpty) return const SizedBox.shrink();
    final c = context.seeuColors;
    final entries = post.reactions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: entries.map((e) {
          final mine = e.key == post.myReaction;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(feedProvider.notifier).toggleReaction(post.id, e.key);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: mine ? SeeUColors.accentSoft : c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: mine ? SeeUColors.accent : c.line,
                  width: mine ? 1 : 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.key, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    formatCount(e.value),
                    style: SeeUTypography.caption.copyWith(
                      fontSize: 12,
                      color: mine ? SeeUColors.accent : c.ink2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLikesRow(BuildContext context, Post post) {
    final c = context.seeuColors;
    if (post.likesCount <= 0) return const SizedBox.shrink();
    String likesText;
    final hasNamed = post.likedByUsername != null && post.likesCount > 0;
    if (hasNamed) {
      if (post.likesCount == 1) {
        likesText = 'Нравится ${post.likedByUsername}';
      } else {
        likesText = 'Нравится ${post.likedByUsername} и ещё ${formatCount(post.likesCount - 1)}';
      }
    } else {
      likesText = '${formatCount(post.likesCount)} отметок «Нравится»';
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
      child: PostExpandableCaption(
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
          label: '${formatCount(post.commentsCount)} комментариев',
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
        formatRelativeTime(post.createdAt),
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
                Navigator.pop(context);
                if (!mounted) return;
                showShareSheet(
                  context: context,
                  url: postShareUrl(post.id),
                  title: 'Поделиться постом',
                  subtitle: post.author.username.isNotEmpty
                      ? '@${post.author.username}'
                      : null,
                  forwardablePostId: post.id,
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
                if (!mounted) return;
                showReportSheet(
                  context: context,
                  ref: ref,
                  targetType: 'post',
                  targetId: widget.post.id,
                );
              },
            ),
            ListTile(
              leading: const PhosphorIcon(PhosphorIconsRegular.prohibit, color: Color(0xFFE74C3C)),
              title: Text('Заблокировать автора',
                  style: SeeUTypography.body
                      .copyWith(color: const Color(0xFFE74C3C))),
              onTap: () {
                Navigator.pop(context);
                if (!mounted) return;
                _confirmBlockAuthor();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

}

// --- Action button (tappable) ------------------------------------------------
