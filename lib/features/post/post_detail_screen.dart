import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/models/post.dart';
import '../../core/analytics/interest_tracker.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/providers/feed_provider.dart';
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
    HapticFeedback.lightImpact();
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                    color: context.seeuColors.ink2),
                title: Text('Не показывать', style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // Раньше пункт только показывал «Пост скрыт», ничего не
                  // делая. Теперь — как «не интересно» в ленте: negative
                  // interest-сигнал + пометка просмотренным + убрать из
                  // ленты + закрыть экран.
                  ref
                      .read(apiClientProvider)
                      .post(ApiEndpoints.viewPost(post.id))
                      .ignore();
                  ref.read(interestTrackerProvider).track(
                        eventType: 'not_interested',
                        entityType: 'post',
                        entityId: post.id,
                        authorId: post.author.id,
                        source: 'post_detail_menu',
                      );
                  ref.read(feedProvider.notifier).removePost(post.id);
                  showSeeUSnackBar(context, 'Пост скрыт',
                      icon: PhosphorIcons.eyeSlash());
                  Navigator.of(context).maybePop();
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
    final topInset = MediaQuery.of(context).padding.top + 56;

    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          postAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: SeeUColors.accent),
            ),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
                  const SizedBox(height: 16),
                  Text('Не удалось загрузить пост',
                      style: SeeUTypography.body.copyWith(color: c.ink2)),
                  const SizedBox(height: 16),
                  SeeUButton(
                    label: 'Повторить',
                    variant: SeeUButtonVariant.primary,
                    width: 120,
                    height: 44,
                    onTap: () =>
                        ref.refresh(_postDetailProvider(widget.postId)),
                  ),
                ],
              ),
            ),
            data: (post) => ListView(
              padding: EdgeInsets.only(top: topInset),
              children: [
                PostCard(post: post, isDetail: true),
                // Hairline-разделитель между медиа и quick-actions.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child:
                      Divider(height: 0.5, thickness: 0.5, color: c.line),
                ),
                const SizedBox(height: 12),
                // Quick action bar below post
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _QuickAction(
                        icon: PhosphorIcons.shareFat(),
                        label: 'Поделиться',
                        onTap: () => _onShare(post),
                      ),
                      const SizedBox(width: 8),
                      _QuickAction(
                        icon: PhosphorIcons.chatCircle(),
                        label: 'Комментарии',
                        onTap: () =>
                            context.push('/post/${widget.postId}/comments'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SeeUGlassBar(
              blur: 28,
              kicker: 'Публикация',
              title: Text('Пост',
                  style: SeeUTypography.displayS.copyWith(color: c.ink)),
              leading: IconButton(
                icon: Icon(PhosphorIcons.arrowLeft(), size: 22, color: c.ink),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                postAsync.whenOrNull(
                      data: (post) => IconButton(
                        icon: Icon(
                            PhosphorIcons.dotsThree(PhosphorIconsStyle.bold),
                            size: 22,
                            color: c.ink),
                        onPressed: () => _onMore(post),
                      ),
                    ) ??
                    const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Плоский quick-action чип под постом: surface2 + hairline-бордюр c.line.
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c.ink2),
            const SizedBox(width: 6),
            Text(label,
                style: SeeUTypography.caption
                    .copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
