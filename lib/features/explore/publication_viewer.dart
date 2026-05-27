import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/format.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/post.dart';
import '../../core/providers/reels_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../widgets/share_sheet.dart';
import '../post/comments_screen.dart';
import '../reels/widgets/reel_overlay.dart';
import '../reels/widgets/reel_video_player.dart';

/// Vertical-swipe viewer for any publication. Replaces the old ReelsScreen
/// since the product model treats every post (photo, photo collection, or
/// video) as the same kind of «рилс».
///
/// Source of posts: [exploreProvider]. The viewer doesn't fetch its own
/// list — it shares state with the Explore grid so pagination and likes
/// stay consistent in both places.
///
/// `initialPostId` is the post the user tapped on. If it's not in
/// `exploreProvider.state.posts` (e.g. deeplink, stale state) — we land on
/// page 0 and the user can scroll to load more.
class PublicationViewer extends ConsumerStatefulWidget {
  final String initialPostId;
  /// Content filter: video = TikTok UI, photo = photo feed, all = mixed.
  final ContentType contentType;
  const PublicationViewer({
    super.key,
    required this.initialPostId,
    this.contentType = ContentType.all,
  });

  @override
  ConsumerState<PublicationViewer> createState() =>
      _PublicationViewerState();
}

class _PublicationViewerState extends ConsumerState<PublicationViewer> {
  late final PageController _pageCtrl;
  int _currentIndex = 0;
  bool _initialised = false;
  double _overscrollAccum = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  void _seekToInitial(List<Post> posts) {
    if (_initialised) return;
    // "first" = start from page 0 (used when opening reels without a specific post)
    if (widget.initialPostId == 'first') {
      _initialised = true;
      return;
    }
    final idx = posts.indexWhere((p) => p.id == widget.initialPostId);
    if (idx < 0) {
      _initialised = true;
      return;
    }
    // jumpToPage requires the controller to be attached, which happens after
    // first build. Schedule for the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients) {
        _pageCtrl.jumpToPage(idx);
        if (mounted) {
          setState(() {
            _currentIndex = idx;
            _initialised = true;
          });
        }
      }
    });
  }

  bool get _hasOwnProvider => widget.contentType != ContentType.all;

  void _onPageChanged(int idx, List<Post> posts) {
    setState(() => _currentIndex = idx);
    if (idx >= posts.length - 3) {
      if (_hasOwnProvider) {
        ref.read(contentFeedProvider(widget.contentType).notifier).loadMore();
      } else {
        ref.read(exploreProvider.notifier).loadMore();
      }
    }
  }

  String _videoUrl(Post post) {
    final videoMedia = post.media.firstWhere(
      (m) => m.type == MediaType.video,
      orElse: () => post.media.first,
    );
    final url = videoMedia.url;
    if (url.startsWith('http')) return url;
    return '${AppConfig.apiOrigin}$url';
  }

  void _openCommentsSheet(Post post) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, __) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: CommentsScreen(postId: post.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ct = widget.contentType;
    final bool isVideoMode = ct == ContentType.video;

    // Pick provider based on mode
    final List<Post> posts;
    final bool isLoading;
    final bool isLoadingMore;
    if (_hasOwnProvider) {
      final cs = ref.watch(contentFeedProvider(ct));
      posts = cs.posts;
      isLoading = cs.isLoading;
      isLoadingMore = cs.isLoadingMore;
    } else {
      final es = ref.watch(exploreProvider);
      posts = es.posts;
      isLoading = es.isLoading;
      isLoadingMore = es.isLoadingMore;
    }

    if (posts.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Контент не найден',
                        style: TextStyle(color: Colors.white70),
                      ),
              ),
              _BackButton(onTap: () => context.pop()),
            ],
          ),
        ),
      );
    }

    _seekToInitial(posts);

    return Scaffold(
      backgroundColor: Colors.black,
      body: NotificationListener<OverscrollNotification>(
        onNotification: (n) {
          if (_currentIndex == 0 && n.overscroll < 0) {
            _overscrollAccum += n.overscroll.abs();
            if (_overscrollAccum > 80) {
              _overscrollAccum = 0;
              context.pop();
            }
            return true;
          }
          return false;
        },
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            _overscrollAccum = 0;
            return false;
          },
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageCtrl,
                scrollDirection: Axis.vertical,
                itemCount: posts.length,
                allowImplicitScrolling: true,
                onPageChanged: (i) => _onPageChanged(i, posts),
                itemBuilder: (_, i) {
                  final post = posts[i];
                  final isCurrent = i == _currentIndex;
                  if (_hasOwnProvider) {
                    final notifier = ref.read(contentFeedProvider(ct).notifier);
                    if (isVideoMode) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ReelVideoPlayer(
                            key: ValueKey('reel-${post.id}'),
                            url: _videoUrl(post),
                            isActive: isCurrent,
                          ),
                          ReelOverlay(
                            post: post,
                            isLiked: post.isLiked,
                            isSaved: post.isSaved,
                            onLike: () => notifier.toggleLike(post.id),
                            onComment: () => _openCommentsSheet(post),
                            onShare: () => showShareSheet(
                              context: context,
                              url: 'https://seeu.app/post/${post.id}',
                              title: post.caption ?? '',
                              forwardablePostId: post.id,
                            ),
                            onSave: () => notifier.toggleSave(post.id),
                            onAvatarTap: () => context.push('/profile/${post.author.username}'),
                          ),
                        ],
                      );
                    }
                    // Photo mode — reuse existing _PublicationPage but with own provider actions
                    return _PublicationPage(post: post, isCurrent: isCurrent);
                  }
                  return _PublicationPage(
                    post: post,
                    isCurrent: isCurrent,
                  );
                },
              ),
              if (isLoadingMore)
                const Positioned(
                  top: 60,
                  right: 16,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(PhosphorIcons.arrowLeft(),
              color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One full-screen publication page: media + overlay
// ---------------------------------------------------------------------------

class _PublicationPage extends ConsumerStatefulWidget {
  final Post post;
  final bool isCurrent;
  const _PublicationPage({required this.post, required this.isCurrent});

  @override
  ConsumerState<_PublicationPage> createState() =>
      _PublicationPageState();
}

class _PublicationPageState extends ConsumerState<_PublicationPage> {
  final PageController _mediaCtrl = PageController();
  int _mediaIndex = 0;

  // Lazy: only created for video media, kept while page is current,
  // disposed when scrolled away.
  final Map<int, VideoPlayerController> _videoCtrls = {};

  @override
  void initState() {
    super.initState();
    _ensureVideoFor(0);
  }

  @override
  void didUpdateWidget(covariant _PublicationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrent != widget.isCurrent) {
      _syncVideoPlayback();
    }
  }

  @override
  void dispose() {
    for (final c in _videoCtrls.values) {
      c.dispose();
    }
    _mediaCtrl.dispose();
    super.dispose();
  }

  void _ensureVideoFor(int idx) {
    final media = widget.post.media;
    if (idx < 0 || idx >= media.length) return;
    if (media[idx].type != MediaType.video) return;
    if (_videoCtrls.containsKey(idx)) return;
    final url = media[idx].url;
    if (url.isEmpty) return;
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoCtrls[idx] = ctrl;
    ctrl
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) {
          _syncVideoPlayback();
          setState(() {});
        }
      }).catchError((_) {});
  }

  void _syncVideoPlayback() {
    for (final entry in _videoCtrls.entries) {
      final shouldPlay = widget.isCurrent && entry.key == _mediaIndex;
      if (shouldPlay) {
        entry.value.play();
      } else {
        entry.value.pause();
      }
    }
  }

  void _onMediaChanged(int idx) {
    setState(() => _mediaIndex = idx);
    _ensureVideoFor(idx);
    // Free controllers for media slides outside the [idx-1, idx+1] window —
    // for posts with 5+ videos in a carousel, this keeps live controller
    // count bounded at 3 instead of growing to N.
    final keep = {idx - 1, idx, idx + 1};
    final toRemove = _videoCtrls.keys.where((k) => !keep.contains(k)).toList();
    for (final k in toRemove) {
      _videoCtrls[k]?.dispose();
      _videoCtrls.remove(k);
    }
    _syncVideoPlayback();
  }

  /// REELS-6: long-press → bottom-sheet с «Не интересно» (fire-and-forget
  /// POST /posts/:id/view — feed/explore queries filter'ят viewed-посты).
  void _showLongPressMenu(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(PhosphorIconsRegular.eyeSlash,
                  color: Colors.white70),
              title: const Text(
                'Не интересно',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Реже показывать подобные посты',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                // Reuse FEED-5 endpoint — view = filter from future feeds.
                try {
                  await ref
                      .read(apiClientProvider)
                      .post(ApiEndpoints.viewPost(widget.post.id));
                } catch (_) {}
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Спасибо, учтём — реже будем показывать'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final media = post.media;

    return GestureDetector(
      onLongPress: () => _showLongPressMenu(context, ref),
      child: Stack(
      fit: StackFit.expand,
      children: [
        if (media.isEmpty)
          Container(color: Colors.grey.shade900)
        else
          PageView.builder(
            controller: _mediaCtrl,
            scrollDirection: Axis.horizontal,
            physics: media.length > 1
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: media.length,
            onPageChanged: _onMediaChanged,
            itemBuilder: (_, i) => _MediaSlide(
              media: media[i],
              videoCtrl: _videoCtrls[i],
              isActive: widget.isCurrent && _mediaIndex == i,
            ),
          ),

        // Subtle bottom gradient so caption stays readable on bright media.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 240,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Carousel dots (multi-media only).
        if (media.length > 1)
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: _CarouselDots(
              count: media.length,
              active: _mediaIndex,
            ),
          ),

        // Right-side action column.
        Positioned(
          right: 8,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: _ActionColumn(post: post),
          ),
        ),

        // Bottom info: author, caption.
        Positioned(
          left: 12,
          right: 76, // leave space for action column
          bottom: 24,
          child: SafeArea(
            top: false,
            child: _PublicationInfo(post: post),
          ),
        ),
      ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single media slide (photo OR video)
// ---------------------------------------------------------------------------

class _MediaSlide extends StatelessWidget {
  final PostMedia media;
  final VideoPlayerController? videoCtrl;
  final bool isActive;
  const _MediaSlide({
    required this.media,
    required this.videoCtrl,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    if (media.type == MediaType.video) {
      if (videoCtrl == null || !videoCtrl!.value.isInitialized) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if ((media.thumbnailUrl ?? '').isNotEmpty)
              CachedNetworkImage(
                  imageUrl: media.thumbnailUrl!, fit: BoxFit.cover)
            else
              Container(color: Colors.grey.shade900),
            const Center(
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            ),
          ],
        );
      }
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: videoCtrl!.value.size.width,
          height: videoCtrl!.value.size.height,
          child: VideoPlayer(videoCtrl!),
        ),
      );
    }
    // Photo
    return CachedNetworkImage(
      imageUrl: media.url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: Colors.grey.shade900),
      errorWidget: (_, __, ___) => Container(
        color: Colors.grey.shade900,
        child: const Center(
          child: Icon(PhosphorIconsRegular.imageBroken, color: Colors.white54, size: 48),
        ),
      ),
    );
  }
}

class _CarouselDots extends StatelessWidget {
  final int count;
  final int active;
  const _CarouselDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Right-side actions
// ---------------------------------------------------------------------------

class _ActionColumn extends ConsumerWidget {
  final Post post;
  const _ActionColumn({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: post.isLiked
              ? PhosphorIconsFill.heart
              : PhosphorIconsRegular.heart,
          label: formatCount(post.likesCount),
          color: post.isLiked ? SeeUColors.accent : Colors.white,
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(exploreProvider.notifier)
                .toggleLike(post.id);
          },
        ),
        const SizedBox(height: 18),
        _ActionButton(
          icon: PhosphorIconsRegular.chatCircle,
          label: formatCount(post.commentsCount),
          color: Colors.white,
          onTap: () {
            HapticFeedback.lightImpact();
            // REELS-5: comments в bottom-sheet вместо push на отдельный
            // screen — видео продолжает играть позади.
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => DraggableScrollableSheet(
                initialChildSize: 0.7,
                minChildSize: 0.4,
                maxChildSize: 0.95,
                expand: false,
                builder: (_, controller) => ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: CommentsScreen(postId: post.id),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        _ActionButton(
          icon: PhosphorIconsRegular.paperPlaneTilt,
          label: 'Поделиться',
          color: Colors.white,
          showLabel: false,
          onTap: () {
            HapticFeedback.lightImpact();
            // CHAT-5: прокидываем media-params чтобы в share-sheet
            // появился пункт «Поделиться в сторис».
            final firstMedia =
                post.media.isNotEmpty ? post.media.first : null;
            showShareSheet(
              context: context,
              url: postShareUrl(post.id),
              title: 'Поделиться постом',
              subtitle: post.author.username.isNotEmpty
                  ? '@${post.author.username}'
                  : null,
              forwardablePostId: post.id,
              sharedPostMediaUrl: firstMedia?.url,
              sharedPostMediaType: firstMedia?.type.name,
              sharedPostAuthor: post.author.username,
            );
          },
        ),
        const SizedBox(height: 18),
        _ActionButton(
          icon: post.isSaved
              ? PhosphorIconsFill.bookmarkSimple
              : PhosphorIconsRegular.bookmarkSimple,
          label: '',
          color: post.isSaved ? SeeUColors.accent : Colors.white,
          showLabel: false,
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(exploreProvider.notifier)
                .toggleSave(post.id);
          },
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool showLabel;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: color, size: 28),
            ),
            if (showLabel && label.isNotEmpty) ...[
              Text(label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Author + caption
// ---------------------------------------------------------------------------

class _PublicationInfo extends ConsumerWidget {
  final Post post;
  const _PublicationInfo({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (post.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReactionStrip(post: post),
          ),
        GestureDetector(
          onTap: () => context.push('/profile/${post.author.username}'),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                backgroundImage:
                    (post.author.avatarUrl ?? '').isNotEmpty
                        ? CachedNetworkImageProvider(post.author.avatarUrl!)
                        : null,
                child: (post.author.avatarUrl ?? '').isEmpty
                    ? const Icon(PhosphorIconsRegular.user,
                        color: Colors.white70, size: 18)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                '@${post.author.username}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  shadows: [
                    Shadow(blurRadius: 4, color: Colors.black54)
                  ],
                ),
              ),
            ],
          ),
        ),
        if ((post.caption ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            post.caption!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.35,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
        ],
        // REELS-4: audio-track pill. Tap → camera с pre-selected track.
        if ((post.audioTrackId ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          _AudioPill(audioTrackId: post.audioTrackId!),
        ],
      ],
    );
  }
}

/// REELS-4: pill «🎵 Использовать музыку» — tap пушит trackId в
/// `selectedAudioForCameraProvider` + переходит в /camera. Media-prepare на
/// той стороне может прочитать provider и pre-select track для overlay'а.
class _AudioPill extends ConsumerWidget {
  final String audioTrackId;
  const _AudioPill({required this.audioTrackId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(selectedAudioForCameraProvider.notifier).state = audioTrackId;
        context.push('/camera');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Музыка готова — запиши свой реелс ✨'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsRegular.musicNote, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            const Text(
              'Использовать музыку',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// REELS-4: global state — выбранный audio_track_id для следующего захода в
/// camera. media_prepare_screen на init читает + сбрасывает в null.
/// Future: extend to {trackId, startSec} когда audio-trimmer прикрутят.
final selectedAudioForCameraProvider = StateProvider<String?>((_) => null);

/// Aggregate emoji-reaction pills shown above the username on the fullscreen
/// viewer. Dark-bg variant of the chat/feed pill: white-on-glass when others
/// reacted, accent fill+border when it's *my* reaction.
class _ReactionStrip extends ConsumerWidget {
  final Post post;
  const _ReactionStrip({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = post.reactions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries.map((e) {
        final mine = e.key == post.myReaction;
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(exploreProvider.notifier)
                .toggleReaction(post.id, e.key);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: mine
                  ? SeeUColors.accent.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: mine ? SeeUColors.accent : Colors.white24,
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
                  style: TextStyle(
                    fontSize: 12,
                    color: mine ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w600,
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
