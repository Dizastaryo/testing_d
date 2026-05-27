import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/models/post.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/share_sheet.dart';
import '../feed/widgets/post_card.dart';

final _postDetailProvider =
    FutureProvider.family<Post, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiEndpoints.postById(id));
  final data = resp.data;
  final postData = data is Map && data.containsKey('data') ? data['data'] : data;
  return Post.fromJson(postData as Map<String, dynamic>);
});

class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  /// Опциональный comment_id для deep-link из уведомления.
  /// PostDetailScreen открывает CommentsScreen с автоскроллом к нему.
  final String? focusedCommentId;

  const PostDetailScreen({
    super.key,
    required this.postId,
    this.focusedCommentId,
  });

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.focusedCommentId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.push(
            '/post/${widget.postId}/comments?commentId=${widget.focusedCommentId}',
          );
        }
      });
    }
  }

  void _onShare(Post post) {
    HapticFeedback.lightImpact();
    showShareSheet(
      context: context,
      url: postShareUrl(post.id),
      title: 'Поделиться постом',
      subtitle: post.author.username.isNotEmpty
          ? '@${post.author.username}'
          : null,
      forwardablePostId: post.id,
    );
  }

  void _onMore(Post post) {
    final c = context.seeuColors;
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(PhosphorIcons.flag(PhosphorIconsStyle.fill),
                    color: SeeUColors.error),
                title: Text('Пожаловаться',
                    style: SeeUTypography.body
                        .copyWith(color: SeeUColors.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showReportSheet(
                    context: context,
                    ref: ref,
                    targetType: 'post',
                    targetId: post.id,
                  );
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.eyeSlash(PhosphorIconsStyle.fill),
                    color: c.ink2),
                title: Text('Не показывать', style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Пост скрыт',
                          style: SeeUTypography.body
                              .copyWith(color: Colors.white)),
                      backgroundColor: SeeUColors.textSecondary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(SeeURadii.small)),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final postAsync = ref.watch(_postDetailProvider(widget.postId));

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Пост', style: SeeUTypography.subtitle),
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(),
              size: 22, color: c.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          postAsync.whenOrNull(
                data: (post) => IconButton(
                  icon: Icon(PhosphorIcons.dotsThree(PhosphorIconsStyle.bold),
                      size: 22, color: c.ink),
                  onPressed: () => _onMore(post),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: postAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: SeeUColors.accent),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.warning(),
                  size: 48, color: c.ink3),
              const SizedBox(height: 16),
              Text('Не удалось загрузить пост',
                  style: SeeUTypography.body
                      .copyWith(color: c.ink2)),
              const SizedBox(height: 16),
              SeeUButton(
                label: 'Повторить',
                variant: SeeUButtonVariant.primary,
                width: 120,
                height: 44,
                onTap: () => ref.refresh(_postDetailProvider(widget.postId)),
              ),
            ],
          ),
        ),
        data: (post) => ListView(
          children: [
            PostCard(post: post, isDetail: true),
            // Quick action bar below post
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Tappable.scaled(
                    onTap: () => _onShare(post),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius:
                            BorderRadius.circular(SeeURadii.pill),
                        border:
                            Border.all(color: c.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIcons.shareFat(),
                              size: 16, color: c.ink2),
                          const SizedBox(width: 6),
                          Text('Поделиться',
                              style: SeeUTypography.caption.copyWith(
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tappable.scaled(
                    onTap: () {
                      context.push('/post/${widget.postId}/comments');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius:
                            BorderRadius.circular(SeeURadii.pill),
                        border:
                            Border.all(color: c.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIcons.chatCircle(),
                              size: 16, color: c.ink2),
                          const SizedBox(width: 6),
                          Text('Комментарии',
                              style: SeeUTypography.caption.copyWith(
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
