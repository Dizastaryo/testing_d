import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/video.dart';

/// Dedicated Dio for the video service. The default `apiClientProvider`
/// targets `ApiEndpoints.baseUrl` (api on 8001), but videos live on 8002.
final _videoApiProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.videoBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final root = ref.read(apiClientProvider);
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final tok = await root.getAccessToken();
      if (tok != null && tok.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $tok';
      }
      handler.next(options);
    },
  ));
  return dio;
});

final _videoDetailProvider =
    FutureProvider.autoDispose.family<Video, String>((ref, id) async {
  final dio = ref.read(_videoApiProvider);
  final r = await dio.get('/videos/$id');
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  return Video.fromJson(data as Map<String, dynamic>);
});

class _VideoCommentItem {
  final String id;
  final String text;
  final DateTime createdAt;
  final String username;
  final String avatarUrl;
  final String userId;
  _VideoCommentItem({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.username,
    required this.avatarUrl,
    required this.userId,
  });
  factory _VideoCommentItem.fromJson(Map<String, dynamic> j) {
    final u = (j['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return _VideoCommentItem(
      id: j['id'] as String,
      text: j['text'] as String? ?? '',
      createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      username: u['username'] as String? ?? '',
      avatarUrl: u['avatar_url'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
    );
  }
}

final _videoCommentsProvider = FutureProvider.autoDispose
    .family<List<_VideoCommentItem>, String>((ref, id) async {
  final dio = ref.read(_videoApiProvider);
  final r = await dio.get('/videos/$id/comments',
      queryParameters: {'limit': 100});
  final data =
      r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  final items = (data as Map)['items'] as List? ?? [];
  return items
      .map((e) => _VideoCommentItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

class VideoDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const VideoDetailScreen({super.key, required this.id});

  @override
  ConsumerState<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends ConsumerState<VideoDetailScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _initialized = false;
  bool _hasError = false;
  String? _errorText;
  bool _viewSent = false;

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _setupPlayer(String url) async {
    if (_videoController != null) return;
    final vc = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = vc;
    try {
      await vc.initialize();
      if (!mounted) return;
      _chewieController = ChewieController(
        videoPlayerController: vc,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        showControlsOnInitialize: true,
        // Chewie's default Material controls already include:
        //   play/pause, scrubber, current/total time, skip ±10s, fullscreen,
        //   mute, speed picker. Customising the colours below to match brand.
        materialProgressColors: ChewieProgressColors(
          playedColor: SeeUColors.accent,
          handleColor: SeeUColors.accent,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white12,
        ),
        placeholder: Container(color: Colors.black),
        errorBuilder: (_, errorMessage) => Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Не удалось воспроизвести видео\n$errorMessage',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
      vc.addListener(_onPlayerTick);
      setState(() => _initialized = true);
    } catch (e) {
      debugPrint('VideoDetail init error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorText = e.toString();
        });
      }
    }
  }

  void _onPlayerTick() {
    if (!_viewSent && (_videoController?.value.position.inSeconds ?? 0) > 1) {
      _viewSent = true;
      _markViewed();
    }
  }

  Future<void> _markViewed() async {
    try {
      await ref.read(_videoApiProvider).post('/videos/${widget.id}/view');
    } catch (_) {}
  }

  Future<void> _toggleLike(Video video) async {
    final dio = ref.read(_videoApiProvider);
    try {
      if (video.isLiked) {
        await dio.delete('/videos/${widget.id}/like');
      } else {
        await dio.post('/videos/${widget.id}/like');
      }
      ref.invalidate(_videoDetailProvider(widget.id));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final async = ref.watch(_videoDetailProvider(widget.id));

    return Scaffold(
      backgroundColor: Colors.black,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _LoadFailure(message: e.toString(), onClose: () => context.pop()),
        data: (video) {
          if (!_initialized && !_hasError && _videoController == null) {
            _setupPlayer(video.videoUrl);
          }
          return SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                // Status-bar safe top spacer + close button overlay handled by Chewie
                // when fullscreen; in normal view we draw our own thin top bar.
                Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 4,
                    left: 4,
                    right: 16,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(PhosphorIcons.dotsThreeOutline(), color: Colors.white),
                        onPressed: () => _showActions(context, video),
                      ),
                    ],
                  ),
                ),

                // Player. Both vertical (9:16) and cinematic (21:9) видео
                // должны полностью помещаться в контейнере. Контейнер фикс по
                // высоте (60% экрана), видео внутри — `fit: contain`, чёрные
                // полосы по бокам/сверху-снизу — это правильное поведение.
                _PlayerStage(
                  hasError: _hasError,
                  initialized: _initialized,
                  thumbnailUrl: video.thumbnailUrl,
                  errorText: _errorText,
                  controller: _videoController,
                  chewieController: _chewieController,
                ),

                // Meta + actions
                Expanded(
                  child: Container(
                    color: c.surface,
                    padding: const EdgeInsets.all(16),
                    child: ListView(
                      children: [
                        Text(
                          video.title,
                          style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${video.viewsFormatted} просмотров · ${video.durationFormatted}',
                          style: TextStyle(fontSize: 12, color: c.ink2),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: c.surface2,
                              backgroundImage:
                                  (video.user?.avatarUrl ?? '').isNotEmpty
                                      ? NetworkImage(video.user!.avatarUrl)
                                      : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('@${video.user?.username ?? '???'}',
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (video.user?.fullName.isNotEmpty == true)
                                    Text(video.user!.fullName,
                                        style: TextStyle(fontSize: 12, color: c.ink2)),
                                ],
                              ),
                            ),
                            _IconAction(
                              icon: video.isLiked
                                  ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                                  : PhosphorIcons.heart(),
                              color: video.isLiked ? SeeUColors.like : c.ink,
                              label: '${video.likesCount}',
                              onTap: () => _toggleLike(video),
                            ),
                          ],
                        ),
                        if (video.description.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(video.description,
                              style: TextStyle(color: c.ink2, height: 1.4)),
                        ],
                        const SizedBox(height: 24),
                        _VideoCommentsSection(videoId: widget.id),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showActions(BuildContext context, Video video) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIcons.flag(), color: SeeUColors.like),
              title: const Text('Пожаловаться'),
              onTap: () {
                Navigator.pop(sheetCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Жалоба на видео — скоро')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds the player area at a fixed maximum height (60% of screen) and
/// letterboxes the actual video inside. Works for any aspect ratio — vertical
/// reels-style 9:16, horizontal 16:9, cinematic 21:9 — without overflow.
class _PlayerStage extends StatelessWidget {
  final bool hasError;
  final bool initialized;
  final String thumbnailUrl;
  final String? errorText;
  final VideoPlayerController? controller;
  final ChewieController? chewieController;

  const _PlayerStage({
    required this.hasError,
    required this.initialized,
    required this.thumbnailUrl,
    required this.errorText,
    required this.controller,
    required this.chewieController,
  });

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final maxH = screenH * 0.6;

    Widget content;
    if (hasError) {
      content = Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Не удалось воспроизвести видео\n${errorText ?? ''}',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (initialized && controller != null && chewieController != null) {
      final aspect = controller!.value.aspectRatio;
      content = LayoutBuilder(
        builder: (_, constraints) {
          final maxW = constraints.maxWidth;
          // Pick the largest size that fits within (maxW × maxH) at given aspect.
          double w = maxW;
          double h = w / aspect;
          if (h > maxH) {
            h = maxH;
            w = h * aspect;
          }
          return Center(
            child: SizedBox(
              width: w,
              height: h,
              child: Chewie(controller: chewieController!),
            ),
          );
        },
      );
    } else {
      content = Stack(
        alignment: Alignment.center,
        children: [
          if (thumbnailUrl.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(imageUrl: thumbnailUrl, fit: BoxFit.cover),
            ),
          const CircularProgressIndicator(),
        ],
      );
    }

    return Container(
      width: double.infinity,
      height: maxH,
      color: Colors.black,
      child: content,
    );
  }
}

class _VideoCommentsSection extends ConsumerStatefulWidget {
  final String videoId;
  const _VideoCommentsSection({required this.videoId});

  @override
  ConsumerState<_VideoCommentsSection> createState() => _VideoCommentsSectionState();
}

class _VideoCommentsSectionState extends ConsumerState<_VideoCommentsSection> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.me);
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      if (mounted) setState(() => _myUserId = data['id'] as String?);
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final dio = ref.read(_videoApiProvider);
      await dio.post('/videos/${widget.videoId}/comments', data: {'text': text});
      _ctrl.clear();
      ref.invalidate(_videoCommentsProvider(widget.videoId));
      ref.invalidate(_videoDetailProvider(widget.videoId));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить: ${apiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(_VideoCommentItem item) async {
    try {
      final dio = ref.read(_videoApiProvider);
      await dio.delete('/video-comments/${item.id}');
      ref.invalidate(_videoCommentsProvider(widget.videoId));
      ref.invalidate(_videoDetailProvider(widget.videoId));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: ${apiErrorMessage(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final async = ref.watch(_videoCommentsProvider(widget.videoId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(PhosphorIcons.chatCircle(PhosphorIconsStyle.bold),
                size: 18, color: c.ink),
            const SizedBox(width: 8),
            Text('Комментарии',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Написать комментарий…',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(PhosphorIcons.paperPlaneTilt(PhosphorIconsStyle.fill),
                      color: SeeUColors.accent),
            ),
          ],
        ),
        const SizedBox(height: 12),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Не удалось загрузить комментарии: $e',
                style: TextStyle(color: c.ink2)),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Пока нет комментариев. Будь первым.',
                    style: TextStyle(color: c.ink3)),
              );
            }
            return Column(
              children: items
                  .map((item) => _CommentTile(
                        item: item,
                        canDelete: _myUserId != null && _myUserId == item.userId,
                        onDelete: () => _delete(item),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final _VideoCommentItem item;
  final bool canDelete;
  final VoidCallback onDelete;
  const _CommentTile({
    required this.item,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: c.surface2,
            backgroundImage:
                item.avatarUrl.isNotEmpty ? NetworkImage(item.avatarUrl) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('@${item.username}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text(_relativeTime(item.createdAt),
                        style: TextStyle(fontSize: 11, color: c.ink3)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(item.text, style: const TextStyle(height: 1.3)),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: c.ink3,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'только что';
    if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
    if (d.inHours < 24) return '${d.inHours} ч назад';
    if (d.inDays < 7) return '${d.inDays} дн назад';
    return '${t.day}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  }
}

class _LoadFailure extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _LoadFailure({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Не удалось загрузить видео\n$message',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onClose, child: const Text('Назад')),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _IconAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
