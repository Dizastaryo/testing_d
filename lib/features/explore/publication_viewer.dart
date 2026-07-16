import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/format.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/post.dart';
import '../../core/providers/content_feed_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../widgets/share_sheet.dart';
import '../post/comments_screen.dart';
import '../reels/widgets/reel_overlay.dart';
import '../reels/widgets/reel_video_player.dart';

/// Vertical-swipe viewer for any publication. Replaces the old ReelsScreen
/// since the product model treats every post (photo, photo collection, or
/// video) as the same kind of «рилс».
///
/// Source of posts: [contentFeedProvider] (video/photo mode) или
/// [exploreProvider] (all). Грид «Интересного» живёт на ДРУГОЙ выборке
/// (/explore, ExploreItem), поэтому тапнутый пост может отсутствовать в
/// ленте вьюера — тогда `ensurePost` дотягивает его по id и вставляет
/// первым, чтобы открылся именно тот пост, на который нажали.
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
  bool _ensureRequested = false;
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
      // Тапнутого поста нет в этой выборке (грид «Интересного» живёт на
      // /explore, а вьюер — на /posts/explore) — раньше молча открывался
      // первый пост чужой ленты. Дотягиваем пост по id: после вставки
      // state обновится, build перезапустит _seekToInitial и найдёт его.
      if (!_ensureRequested) {
        _ensureRequested = true;
        if (_hasOwnProvider) {
          ref
              .read(contentFeedProvider(widget.contentType).notifier)
              .ensurePost(widget.initialPostId);
        } else {
          ref
              .read(exploreProvider.notifier)
              .ensurePost(widget.initialPostId);
        }
      } else {
        // Повторный проход после попытки — поста нет/недоступен.
        _initialised = true;
      }
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
    // Guard: a post with no media would crash `post.media.first` below.
    if (post.media.isEmpty) return '';
    final videoMedia = post.media.firstWhere(
      (m) => m.type == MediaType.video,
      orElse: () => post.media.first,
    );
    final url = videoMedia.url;
    if (url.startsWith('http')) return url;
    return '${AppConfig.apiOrigin}$url';
  }

  void _openCommentsSheet(Post post) =>
      _showPublicationComments(context, post.id);

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
                    : Text(
                        'Контент не найден',
                        style: SeeUTypography.body
                            .copyWith(color: Colors.white70),
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
                      final videoUrl = _videoUrl(post);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (videoUrl.isEmpty)
                            Container(
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: Text(
                                'Видео недоступно',
                                style: SeeUTypography.body
                                    .copyWith(color: Colors.white54),
                              ),
                            )
                          else
                            ReelVideoPlayer(
                              key: ValueKey('reel-${post.id}'),
                              url: videoUrl,
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
                    return _PublicationPage(
                      post: post,
                      isCurrent: isCurrent,
                      notifier: notifier,
                    );
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
      child: Align(
        alignment: Alignment.topLeft,
        child: SeeUGlassCircleButton(
          onTap: onTap,
          size: 40,
          blur: 18,
          icon: Icon(PhosphorIcons.caretLeft(),
              color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// Общий glass-sheet с комментариями (используется и viewer'ом, и action-
/// колонкой) — видео продолжает играть позади.
void _showPublicationComments(BuildContext context, String postId) {
  showSeeUBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final mq = MediaQuery.of(sheetCtx);
      final double height = (mq.size.height * 0.7 - mq.viewInsets.bottom)
          .clamp(mq.size.height * 0.35, mq.size.height * 0.9);
      return Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SizedBox(
          height: height,
          child: CommentsScreen(postId: postId),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// One full-screen publication page: media + overlay
// ---------------------------------------------------------------------------

class _PublicationPage extends ConsumerStatefulWidget {
  final Post post;
  final bool isCurrent;
  /// When the viewer runs on its own [contentFeedProvider] feed, like/save
  /// actions must hit THAT notifier (not [exploreProvider]) so the
  /// buttons and counts stay in sync. Null = shared exploreProvider path.
  final ContentFeedNotifier? notifier;
  const _PublicationPage({
    required this.post,
    required this.isCurrent,
    this.notifier,
  });

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

  // Looped music overlay for posts that carry a track (photo OR video).
  AudioPlayer? _musicPlayer;
  bool _musicResolving = false;
  // Last seen position per video index — used to detect a loop wrap so the
  // music can re-sync to the chosen start (keeps dance reels in time).
  final Map<int, Duration> _lastVidPos = {};

  @override
  void initState() {
    super.initState();
    _ensureVideoFor(0);
    _syncMusic();
  }

  @override
  void didUpdateWidget(covariant _PublicationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrent != widget.isCurrent) {
      _syncVideoPlayback();
      _syncMusic();
    }
  }

  @override
  void dispose() {
    for (final c in _videoCtrls.values) {
      c.dispose();
    }
    _musicPlayer?.dispose();
    _mediaCtrl.dispose();
    super.dispose();
  }

  /// Posts with a chosen track play it looped while on screen. It enters at the
  /// chosen start offset; once the song ends it restarts from the beginning
  /// (LoopMode.all). The video player isn't muted here — that's already decided
  /// at publish time (a muted video file = only the track is heard; a kept one
  /// = the user deliberately wanted their audio plus the track).
  Future<void> _syncMusic() async {
    final id = widget.post.audioTrackId;
    if (id == null || id.isEmpty) return;

    if (!widget.isCurrent) {
      try { await _musicPlayer?.pause(); } catch (_) {}
      return;
    }

    if (_musicPlayer == null && !_musicResolving) {
      _musicResolving = true;
      try {
        final api = ref.read(apiClientProvider);
        final r = await api.get(ApiEndpoints.audioTrackById(id));
        if (!mounted) return;
        final data = (r.data is Map && (r.data as Map).containsKey('data'))
            ? r.data['data']
            : r.data;
        final track = AudioTrack.fromJson(data as Map<String, dynamic>);
        if (track.playbackUrl.isEmpty) return;
        final player = AudioPlayer();
        await player.setUrl(track.playbackUrl);
        await player.setLoopMode(LoopMode.all);
        await player.seek(Duration(seconds: widget.post.audioStartSeconds));
        // The page may have been disposed (or scrolled away) during the awaits
        // above. Don't stash a player dispose() never saw, and don't let it play.
        if (!mounted) {
          await player.dispose();
          return;
        }
        _musicPlayer = player;
      } catch (e) {
        debugPrint('publication music load: $e');
        return;
      } finally {
        _musicResolving = false;
      }
    }

    if (mounted && widget.isCurrent) {
      try { await _musicPlayer?.play(); } catch (_) {}
    }
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
      ..addListener(() => _onVideoTick(idx, ctrl))
      ..initialize().then((_) {
        if (mounted) {
          _syncVideoPlayback();
          setState(() {});
        }
      }).catchError((_) {});
  }

  /// Detect when the active video loops back to the start and re-seek the music
  /// to the chosen offset, so a video recorded to a beat stays in time on every
  /// repeat instead of drifting.
  void _onVideoTick(int idx, VideoPlayerController ctrl) {
    if (!mounted || _musicPlayer == null) return;
    if (idx != _mediaIndex || !widget.isCurrent) return;
    final pos = ctrl.value.position;
    final prev = _lastVidPos[idx] ?? Duration.zero;
    if (prev > const Duration(milliseconds: 600) &&
        pos < const Duration(milliseconds: 250)) {
      _musicPlayer!.seek(Duration(seconds: widget.post.audioStartSeconds));
    }
    _lastVidPos[idx] = pos;
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
    final c = context.seeuColors;
    showSeeUBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ПУБЛИКАЦИЯ',
                    style: SeeUTypography.kicker
                        .copyWith(color: SeeUColors.accent),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Действия',
                    style: SeeUTypography.displayS.copyWith(color: c.ink),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(PhosphorIconsRegular.eyeSlash, color: c.ink),
              title: Text(
                'Не интересно',
                style: SeeUTypography.body.copyWith(color: c.ink),
              ),
              subtitle: Text(
                'Реже показывать подобные посты',
                style: SeeUTypography.caption.copyWith(color: c.ink3),
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
                showSeeUSnackBar(
                  context,
                  'Спасибо, учтём — реже будем показывать',
                  icon: PhosphorIcons.eyeSlash(),
                );
              },
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
    final media = post.media;

    return GestureDetector(
      onLongPress: () => _showLongPressMenu(context, ref),
      child: Stack(
      fit: StackFit.expand,
      children: [
        if (media.isEmpty)
          Container(color: SeeUColors.darkSurface2)
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
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    SeeUColors.transparentBlack,
                    SeeUColors.mediumScrim,
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
            child: _ActionColumn(post: post, notifier: widget.notifier),
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
  const _MediaSlide({
    required this.media,
    required this.videoCtrl,
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
              Container(color: SeeUColors.darkSurface2),
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
      placeholder: (_, __) => Container(color: SeeUColors.darkSurface2),
      errorWidget: (_, __, ___) => Container(
        color: SeeUColors.darkSurface2,
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
  final ContentFeedNotifier? notifier;
  const _ActionColumn({required this.post, this.notifier});

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
          // Лайкнутое сердце всюду красное (лента/рилс/истории) — тут был
          // единственный экран с коралловым.
          color: post.isLiked ? SeeUColors.like : Colors.white,
          onTap: () {
            HapticFeedback.lightImpact();
            if (notifier != null) {
              notifier!.toggleLike(post.id);
            } else {
              ref.read(exploreProvider.notifier).toggleLike(post.id);
            }
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
            _showPublicationComments(context, post.id);
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
            if (notifier != null) {
              notifier!.toggleSave(post.id);
            } else {
              ref.read(exploreProvider.notifier).toggleSave(post.id);
            }
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
                  style: SeeUTypography.caption.copyWith(
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
                style: SeeUTypography.subtitle.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  shadows: const [
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
            style: SeeUTypography.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w400,
              height: 1.35,
              shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
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
        showSeeUSnackBar(
          context,
          'Музыка готова — запиши свой реелс',
          icon: PhosphorIcons.musicNote(),
          duration: const Duration(seconds: 2),
        );
      },
      // Стеклянный pill поверх медиа: blur + градиент + светлый hairline.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.14),
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.8,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'МУЗЫКА',
                  style: SeeUTypography.kicker
                      .copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsRegular.musicNote,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Использовать музыку',
                      style: SeeUTypography.caption.copyWith(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// REELS-4: global state — выбранный audio_track_id для следующего захода в
/// camera. media_prepare_screen на init читает + сбрасывает в null.
/// Future: extend to {trackId, startSec} когда audio-trimmer прикрутят.
final selectedAudioForCameraProvider = StateProvider<String?>((_) => null);
